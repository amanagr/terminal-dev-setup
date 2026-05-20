#!/usr/bin/env bash
# create-worktree.sh — provision a Zulip dev environment using Vagrant + Docker.
#
# Always ensures the canonical clone exists at ~/work/zulip first; non-"zulip"
# names are then added as linked `git worktree`s of that main clone — they
# share .git/, so branches/commits are visible from every worktree.
#
# Each worktree gets its own Docker container managed by Vagrant. We use
# Zulip's documented recommended setup (`vagrant up --provider=docker`),
# which means the Vagrantfile already in the Zulip repo drives everything:
# image build (tools/setup/dev-vagrant-docker/Dockerfile, Ubuntu 22.04 +
# systemctl3 + the `vagrant` user) and provision (tools/setup/vagrant-provision
# → ./tools/provision, ~10–20 min on first up). Bugs reproduce on the
# upstream-supported config — easy to file upstream.
#
# Synced folders inside the container (set by Zulip's Vagrantfile):
#   ./             → __dir__  (i.e., /Users/$USER/work/<name>; same path inside)
#   git_common_dir → git_common_dir  (shared .git visible across worktrees)
# So /Users/$USER/work/<name> resolves directly inside the container too.
# The container's $HOME is /home/vagrant — a *different* path.
#
# Per-worktree port: Zulip's Vagrantfile reads HOST_PORT from the global
# ~/.zulip-vagrant-config. We allocate a port per worktree (sequential,
# stride 10 — the Vagrantfile forwards host_port, +3, +4) stored in
# ~/.config/terminal-dev-setup/worktree-ports.tsv, then rewrite a managed
# block in ~/.zulip-vagrant-config before every `vagrant up`. Each running
# container's port mapping is pinned at `docker run` time, so parallel
# worktrees coexist — but never `vagrant reload` without re-running this
# script (the file may currently hold a different worktree's port).
#
# Usage: create-worktree.sh [--rebuild] <name>
#   --rebuild   `vagrant destroy -f` this worktree's container and re-up
#               (keeps the working tree and branch intact)
#
# Re-running with the same name resumes from wherever a previous run died.

set -euo pipefail

# ---------- Config ----------
REPO_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"

WORKTREE_ROOT="$HOME/work"
MAIN_NAME="zulip"
MAIN_WORKTREE="$WORKTREE_ROOT/$MAIN_NAME"

ORIGIN_URL="git@github.com:amanagr/zulip.git"
UPSTREAM_URL="git@github.com:zulip/zulip.git"

PORTS_DIR="$HOME/.config/terminal-dev-setup"
PORTS_FILE="$PORTS_DIR/worktree-ports.tsv"
ZULIP_VAGRANT_CONFIG="$HOME/.zulip-vagrant-config"
BASE_PORT=9991            # Matches Zulip's Vagrantfile default.
PORT_STRIDE=10            # Vagrantfile uses host_port, +3, +4 — 10 gives slack.
MANAGED_BEGIN="# >>> managed-by: create-worktree.sh >>>"
MANAGED_END="# <<< managed-by: create-worktree.sh <<<"

usage() { cat <<'EOF'
Usage: create-worktree.sh [--rebuild] <name>
  --rebuild   `vagrant destroy -f` this worktree's container and re-up
              (keeps the working tree and branch intact)

Always ensures the canonical clone at ~/work/zulip exists first; non-"zulip"
names become linked git worktrees of it. Re-runs resume from wherever a
previous run died.
EOF
}

# ---------- Args ----------
REBUILD=0
NAME=""
for arg in "$@"; do
    case "$arg" in
        --rebuild)  REBUILD=1 ;;
        -h|--help)  usage; exit 0 ;;
        -*)         echo "Unknown flag: $arg" >&2; exit 2 ;;
        *)          [ -z "$NAME" ] || { echo "Multiple names: '$NAME' '$arg'" >&2; exit 2; }
                    NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || { usage >&2; exit 2; }

case "$NAME" in
    HEAD|head|main|.|..) echo "'$NAME' is reserved — pick a different name" >&2; exit 2 ;;
    .*|-*|*[!A-Za-z0-9._-]*)
        echo "'$NAME': use [A-Za-z0-9._-], must start with an alphanumeric" >&2
        exit 2 ;;
esac

DIR="$WORKTREE_ROOT/$NAME"

step() { printf '\n== %s ==\n' "$*"; }


# ---------- 1. Prereqs ----------
step "Prerequisites"
missing=()
for cmd in git vagrant docker jq; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
[ ${#missing[@]} -eq 0 ] || {
    echo "Missing: ${missing[*]} — see ../host/CLAUDE.md for install hints" >&2; exit 1
}
git check-ref-format "refs/heads/$NAME" 2>/dev/null || {
    echo "'$NAME' is not a legal git branch name" >&2; exit 2
}
# `docker version` exits non-zero if the daemon isn't reachable (Docker
# Desktop not running) — exit code is what matters, not parsing output.
docker version >/dev/null 2>&1 || {
    echo "Docker daemon isn't reachable — launch Docker Desktop and retry" >&2; exit 1
}
echo "ok"


# ---------- 2. Main clone ----------
step "Main clone at $MAIN_WORKTREE"
if [ -d "$MAIN_WORKTREE/.git" ]; then
    [ -f "$MAIN_WORKTREE/tools/provision" ] || {
        echo "$MAIN_WORKTREE looks incomplete — rm -rf and re-run" >&2; exit 1
    }
    echo "already present"
else
    mkdir -p "$WORKTREE_ROOT"
    git clone --config pull.rebase=true "$ORIGIN_URL" "$MAIN_WORKTREE"
fi


# ---------- 3. Upstream remote ----------
step "Configure upstream remote"
git -C "$MAIN_WORKTREE" remote add upstream "$UPSTREAM_URL" 2>/dev/null \
    || git -C "$MAIN_WORKTREE" remote set-url upstream "$UPSTREAM_URL"
git -C "$MAIN_WORKTREE" fetch upstream


# ---------- 4. Worktree ----------
if [ "$NAME" = "$MAIN_NAME" ]; then
    step "Fast-forward main in $MAIN_WORKTREE"
    # Skip the refresh if the worktree is dirty or in detached HEAD — don't
    # risk discarding user work-in-progress. The container build below still
    # runs; only the upstream catch-up is skipped.
    branch=$(git -C "$MAIN_WORKTREE" symbolic-ref --short -q HEAD || true)
    if [ -z "$branch" ] \
            || ! git -C "$MAIN_WORKTREE" diff --quiet HEAD \
            || ! git -C "$MAIN_WORKTREE" diff --staged --quiet; then
        echo "skipped — $MAIN_WORKTREE has uncommitted changes or is in detached HEAD"
        echo "        commit/stash and re-run to refresh main from upstream"
    elif git -C "$MAIN_WORKTREE" show-ref --verify --quiet refs/heads/main; then
        git -C "$MAIN_WORKTREE" checkout main
        git -C "$MAIN_WORKTREE" pull --ff-only upstream main
    else
        git -C "$MAIN_WORKTREE" checkout -b main upstream/main
        git -C "$MAIN_WORKTREE" pull --ff-only upstream main
    fi
else
    step "Add linked worktree $DIR on branch $NAME"
    git -C "$MAIN_WORKTREE" worktree prune
    if git -C "$MAIN_WORKTREE" worktree list --porcelain | grep -Fxq "worktree $DIR" \
            && [ -d "$DIR" ]; then
        echo "already a worktree"
    elif [ -e "$DIR" ] || [ -L "$DIR" ]; then
        echo "$DIR exists but isn't a registered worktree — remove it and re-run." >&2
        exit 1
    elif git -C "$MAIN_WORKTREE" show-ref --verify --quiet "refs/heads/$NAME"; then
        git -C "$MAIN_WORKTREE" worktree add "$DIR" "$NAME"
    else
        git -C "$MAIN_WORKTREE" worktree add -b "$NAME" "$DIR" upstream/main
    fi
fi


# ---------- 5+6. Allocate HOST_PORT and pin it in ~/.zulip-vagrant-config ----------
# Both steps share a lock so two concurrent invocations don't:
#  - both read max=9991 from an empty tsv and assign the same next port, or
#  - both write the global config with different HOST_PORTs and clobber each other.
# macOS doesn't ship flock(1). Use a noclobber lockfile: `set -C; echo $$ > FILE`
# atomically creates the file with our PID as content, or fails if it exists.
# (mkdir-then-write-pid races: the file would exist for a moment with no pid.)
# The lock sits under XDG_RUNTIME_DIR (or /tmp on macOS, which has no
# XDG_RUNTIME_DIR) — transient location that survives `rm -rf $PORTS_DIR`.
step "Allocate HOST_PORT for '$NAME' (lock-guarded)"
mkdir -p "$PORTS_DIR"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/create-worktree.$UID.lock"
LOCK_WAIT_MAX=120  # seconds before bailing on a stuck lock
# Sanity-check the lock dir up-front. `set -C; echo > FILE` exits 1 for
# both EEXIST (lock taken) AND any other I/O error (missing parent dir,
# read-only fs, ENOSPC). Without this check the wait loop would spin
# 120 s on those cases, claiming "another create-worktree.sh is running".
# The `||` block fires the error: `[ ... ] && [ ... ]` returning false
# is safe under `set -e` because we're on the LHS of `||`.
lock_parent=$(dirname "$LOCK_FILE")
[ -d "$lock_parent" ] && [ -w "$lock_parent" ] || {
    echo "create-worktree.sh: lock dir $lock_parent is missing or unwritable" >&2
    exit 1
}
# umask narrows the lock to user-only (0600) so the /tmp fallback case
# can't be DoS'd by a hostile co-user writing their own PID into it.
# XDG_RUNTIME_DIR is already 0700; this is defense-in-depth. `umask -p`
# emits "umask 0022" form designed to be re-evaluated; round-trips
# cleanly even if the user has POSIX symbolic-umask mode set.
old_umask=$(umask -p)
umask 077
# Cleanup trap on EXIT + the three common-interrupt signals. SIGKILL is
# uncatchable per POSIX; the stale-PID reclaim below handles that case.
# `rm -f` (not `rmdir`) — the lock is a file. Restore umask too in case
# we bail on LOCK_WAIT_MAX before reaching the post-loop restore.
trap 'rm -f "$LOCK_FILE"; eval "$old_umask" 2>/dev/null || true' EXIT INT TERM HUP
waited=0
while ! ( set -C; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; do
    # Try to reclaim an orphaned lock: if the file's PID points at a
    # process that no longer exists, it's stale (kill -9 / OOM / hard
    # reboot). Read once into a variable so an in-flight rewrite by a
    # racer can't shift the value between check and message.
    # `|| true` is load-bearing on macOS bash 3.2 — `set -e` aborts on
    # a failed command substitution there (POSIX has since been
    # clarified; bash 4.4+ doesn't, but the macOS system bash is
    # frozen at 3.2 for GPLv3 reasons).
    holder_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if [ -n "$holder_pid" ] && ! kill -0 "$holder_pid" 2>/dev/null; then
        echo "stale lock from PID $holder_pid — reclaiming"
        # Re-verify after delete: if a fresh acquirer raced in between
        # our read and our delete, their lock's PID differs from $holder_pid.
        # Don't delete what we didn't validate. (Theoretical hole: PID
        # recycling could still match; the window is small and the
        # consequence is a double-acquire — acceptable trade-off.)
        current=$(cat "$LOCK_FILE" 2>/dev/null || true)
        if [ "$current" = "$holder_pid" ]; then
            rm -f "$LOCK_FILE"
        fi
        continue
    fi
    if [ "$waited" -ge "$LOCK_WAIT_MAX" ]; then
        echo "create-worktree.sh: $LOCK_FILE held for >${LOCK_WAIT_MAX}s — bailing." >&2
        echo "If you're sure no other run is active, \`rm -f $LOCK_FILE\` and retry." >&2
        exit 1
    fi
    echo "another create-worktree.sh is running — waiting (${waited}s/${LOCK_WAIT_MAX}s)…"
    sleep 1
    waited=$((waited + 1))
done
eval "$old_umask"

touch "$PORTS_FILE"
PORT=$(awk -F'\t' -v n="$NAME" '$1==n {print $2; exit}' "$PORTS_FILE")
if [ -z "$PORT" ]; then
    # Next stride above the current max (or BASE_PORT if file is empty).
    # Only consider rows where $2 is a valid port number; skip malformed
    # lines so a stray edit can't push allocations into nonsense ranges.
    PORT=$(awk -F'\t' -v base="$BASE_PORT" -v stride="$PORT_STRIDE" '
        BEGIN { max = base - stride }
        $2 ~ /^[0-9]+$/ && $2+0 >= base && $2+0 < 65536 && $2+0 > max { max = $2+0 }
        END { print max + stride }
    ' "$PORTS_FILE")
    printf '%s\t%s\n' "$NAME" "$PORT" >> "$PORTS_FILE"
fi
echo "$NAME → host port $PORT (dev server: http://localhost:$PORT)"

step "Pin HOST_PORT $PORT in $ZULIP_VAGRANT_CONFIG"
touch "$ZULIP_VAGRANT_CONFIG"
# Strip any previous managed block, then re-append. Preserves unrelated
# lines (e.g., HTTP_PROXY, GUEST_MEMORY_MB) the user added by hand.
awk -v b="$MANAGED_BEGIN" -v e="$MANAGED_END" '
    $0==b { skip=1; next }
    $0==e { skip=0; next }
    !skip { print }
' "$ZULIP_VAGRANT_CONFIG" > "$ZULIP_VAGRANT_CONFIG.new"
cat >> "$ZULIP_VAGRANT_CONFIG.new" <<EOF
$MANAGED_BEGIN
# Rewritten on every \`create-worktree.sh <name>\` run. Format is
# whitespace-separated key value — see Zulip's Vagrantfile.
HOST_PORT $PORT
$MANAGED_END
EOF
mv "$ZULIP_VAGRANT_CONFIG.new" "$ZULIP_VAGRANT_CONFIG"

# Release the lock now — the shared state (worktree-ports.tsv +
# ~/.zulip-vagrant-config) is consistent. Holding it across `vagrant up`'s
# 10–20 min runtime would force every concurrent invocation to bail on
# LOCK_WAIT_MAX. There's a small race window: a sibling could rewrite
# ~/.zulip-vagrant-config with its own HOST_PORT while our `vagrant up`
# hasn't yet `docker run`-ed its container. In practice Vagrant reads
# the file once early in its run and the docker port-mapping is pinned
# at create-container time, so this is a sub-second window.
#
# Past this point a Ctrl-C leaves no script-level state to clean up
# (the lock is released, the temp file isn't created yet, and `vagrant
# up` / `vagrant destroy` manage their own state).
rm -f "$LOCK_FILE"
trap - EXIT INT TERM HUP


# ---------- 7. Optional rebuild ----------
if [ "$REBUILD" = 1 ]; then
    step "Rebuild requested — \`vagrant destroy -f\` in $DIR"
    if [ -d "$DIR/.vagrant" ]; then
        ( cd "$DIR" && vagrant destroy -f )
    else
        echo "no existing Vagrant state to destroy"
    fi
fi


# ---------- 8. Bring the container up (image build + Zulip provision) ----------
step "vagrant up --provider=docker in $DIR"
# First run: builds the Ubuntu 22.04 image (Zulip's Dockerfile) and runs
# tools/setup/vagrant-provision → ./tools/provision (~10–20 min, downloads
# every Zulip dependency). Re-runs are no-ops if already up.
( cd "$DIR" && vagrant up --provider=docker )


# ---------- 9. Post-up provisioning (claude, gh, aliases, env, bashrc) ----------
step "Install claude/gh + drop aliases & claude settings into the container"

# vagrant upload doesn't auto-create parent dirs; mkdir first.
( cd "$DIR" && vagrant ssh --no-tty -c "
    mkdir -p \$HOME/.claude \$HOME/.config/terminal-dev-setup \$HOME/.local/bin
" )

# Aliases (verbatim from vm/bash-aliases.sh).
( cd "$DIR" && vagrant upload \
    "$REPO_DIR/vm/bash-aliases.sh" \
    /home/vagrant/.config/terminal-dev-setup/aliases.sh )

# Claude settings: single source of truth is host/claude-settings.json;
# strip the `hooks` block (those reference ~/.local/bin/claude-*.sh scripts
# that don't exist headless and don't make sense without a desktop session).
# Install the cleanup trap BEFORE mktemp so a SIGINT in the window between
# file creation and trap-set doesn't leak the temp file. `${var:-}` keeps
# the trap safe to fire even if mktemp hasn't run yet.
# `mktemp -t prefix` on BSD/macOS is a different command (the prefix is just
# a string, not a template) — explicit `prefix.XXXXXX` template is portable.
filtered_settings=
trap 'rm -f "${filtered_settings:-}"' EXIT INT TERM HUP
filtered_settings=$(mktemp "${TMPDIR:-/tmp}/claude-settings.json.XXXXXX")
jq 'del(.hooks)' "$REPO_DIR/host/claude-settings.json" > "$filtered_settings"
( cd "$DIR" && vagrant upload "$filtered_settings" /home/vagrant/.claude/settings.json )

# Bash setup inside the container: install claude/gh if missing, write
# ~/.zulip-dev-env.sh, and manage the ~/.bashrc block.
ZULIP_EXTERNAL_HOST="localhost:$PORT"
# shellcheck disable=SC2087  # heredoc expansion is intentional — $REPO_DIR,
# $DIR, $ZULIP_EXTERNAL_HOST expand on the host; the inner \$HOME / \$begin
# stay literal so they expand inside the container.
( cd "$DIR" && vagrant ssh --no-tty -c "bash -s" ) <<EOF
set -euo pipefail

# Zulip's provision installs git/curl/jq; verify they're present before
# we lean on them. vagrant-provision has already run by now, so these
# should all be there from Zulip's own ./tools/provision.
for cmd in git curl jq; do
    command -v "\$cmd" >/dev/null || {
        echo "warn: \$cmd missing in container — Zulip provision should have installed it" >&2
    }
done

git config --global core.editor vim

# ~/.local/bin isn't on PATH in vagrant ssh's non-login non-interactive
# shell, so \`command -v claude\` misses an already-installed claude and
# would reinstall on every re-run. Prepend ~/.local/bin so the check is
# accurate.
export PATH="\$HOME/.local/bin:\$PATH"

if ! command -v claude >/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
fi

# gh: GitHub CLI via the official apt repo, idempotent.
if ! command -v gh >/dev/null 2>&1; then
    (
        sudo mkdir -p -m 755 /etc/apt/keyrings /etc/apt/sources.list.d
        # Two statements — `&&`-chained would suspend set -e for the LHS,
        # so a failed mktemp would leave \$gh_tmp empty and curl would write
        # to "/keyring.gpg" without the trap fix-up firing.
        gh_tmp=\$(mktemp -d)
        trap 'rm -rf "\$gh_tmp"' EXIT
        curl -fsSL -o "\$gh_tmp/keyring.gpg" \\
            https://cli.github.com/packages/githubcli-archive-keyring.gpg
        sudo install -m 0644 -o root -g root \\
            "\$gh_tmp/keyring.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg
        arch=\$(dpkg --print-architecture)
        echo "deb [arch=\$arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \\
            | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh
    )
fi

# Outer EOF already expanded \$ZULIP_EXTERNAL_HOST / \$DIR on the host.
# Quote the inner tag so the container's bash treats the body literally and
# we don't accidentally re-expand any \$FOO that a future edit might add.
# Heredoc-quoting trap: if you want to write a \$RUNTIME_VAR to the file
# that should be expanded each time ~/.zulip-dev-env.sh is sourced, you
# can't add it here — the quoted heredoc preserves \$ literally. Either
# concatenate a separate unquoted heredoc or use printf with \\\$.
cat > \$HOME/.zulip-dev-env.sh <<'ENV'
export EXTERNAL_HOST="$ZULIP_EXTERNAL_HOST"
export WORKTREE_DIR="$DIR"
ENV

touch ~/.bashrc
# Strip any prior managed block, then re-append. Single-quoted sed pattern
# so the literal markers don't tangle with shell expansion.
sed -i.bak '/# >>> managed-by: create-worktree.sh >>>/,/# <<< managed-by: create-worktree.sh <<</d' ~/.bashrc
rm -f ~/.bashrc.bak

# Single-quoted heredoc tag — body is written literally to ~/.bashrc, so
# \$WORKTREE_DIR stays a deferred reference (resolved when ~/.bashrc is
# sourced in a fresh shell, after ~/.zulip-dev-env.sh has set it).
cat >> ~/.bashrc <<'BASHRC'

# >>> managed-by: create-worktree.sh >>>
source ~/.zulip-dev-env.sh
[ -f ~/.config/terminal-dev-setup/aliases.sh ] && source ~/.config/terminal-dev-setup/aliases.sh
# Auto-activate Zulip's Python venv. Guarded so a shell opened before
# the venv exists still works.
[ -f "\$WORKTREE_DIR/.venv/bin/activate" ] && source "\$WORKTREE_DIR/.venv/bin/activate"
# <<< managed-by: create-worktree.sh <<<
BASHRC
EOF


# ---------- 10. Done ----------
step "Done"
cat <<EOF
Dev server:  http://localhost:$PORT
SSH in:      cd $DIR && vagrant ssh
Halt:        cd $DIR && vagrant halt
Destroy:     bin/create-worktree.sh --rebuild $NAME    (\`vagrant destroy -f\` + re-up)

To re-up after halt:  bin/create-worktree.sh $NAME
  (Don't \`vagrant up\` directly — \$ZULIP_VAGRANT_CONFIG may currently hold
   a different worktree's HOST_PORT. This script rewrites it first.)

Shortcuts (in a fresh shell — re-source ~/.bashrc, or just \`exec bash\`):
  zcd        cd into \$WORKTREE_DIR ($DIR)
  run        ./tools/run-dev --interface=  (binds to all interfaces in the container)
  v / vi     vim (default Ubuntu vim; git core.editor is also vim)
EOF
