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
# macOS doesn't ship flock(1), so we use a mkdir-based lock (atomic per POSIX).
step "Allocate HOST_PORT for '$NAME' (lock-guarded)"
mkdir -p "$PORTS_DIR"
LOCK_DIR="$PORTS_DIR/.create-worktree.lock"
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    echo "another create-worktree.sh is running — waiting…"
    sleep 1
done
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
touch "$PORTS_FILE"
PORT=$(awk -F'\t' -v n="$NAME" '$1==n {print $2; exit}' "$PORTS_FILE")
if [ -z "$PORT" ]; then
    # Next stride above the current max (or BASE_PORT if file is empty).
    PORT=$(awk -F'\t' -v base="$BASE_PORT" -v stride="$PORT_STRIDE" '
        BEGIN { max = base - stride }
        $2+0 > max { max = $2+0 }
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
# `mktemp -t prefix` on BSD/macOS is a different command (the prefix is just
# a string, not a template) — explicit `prefix.XXXXXX` template is portable.
filtered_settings=$(mktemp "${TMPDIR:-/tmp}/claude-settings.json.XXXXXX")
trap 'rm -f "$filtered_settings"; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
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

cat > \$HOME/.zulip-dev-env.sh <<ENV
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
