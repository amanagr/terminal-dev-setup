#!/usr/bin/env bash
# create-worktree.sh — provision a Zulip dev VM.
#
# First time you run this with the name "zulip" it sets up the canonical
# clone at ~/work/zulip. Every other name becomes a `git worktree` of that
# main clone — they share the same .git/, so branches and commits are
# visible from every worktree.
#
# Usage:
#   create-worktree.sh [--rebuild] <name>
#
#     --rebuild   destroy this worktree's VM and re-provision it
#                 (keeps the working tree, branch, and host port intact)
#
# The Ubuntu base inside the VM is whatever Zulip's upstream Dockerfile
# specifies (currently 22.04). Don't override it — Zulip's provisioner
# pins postgresql@14, which only ships on 22.04.
#
# Re-running the script with the same name resumes from wherever a
# previous attempt died: every step checks for existing state first,
# and concurrent invocations are serialised via flock.

set -euo pipefail

# ---------- Config ----------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/work}"
STATE_DIR="${STATE_DIR:-$HOME/.config/create-worktree}"
LOCK_FILE="$STATE_DIR/.lock"
MAIN_NAME="zulip"
MAIN_WORKTREE="$WORKTREE_ROOT/$MAIN_NAME"

ORIGIN_URL="git@github.com:amanagr/zulip.git"
UPSTREAM_URL="https://github.com/zulip/zulip.git"

PORT_START=9991            # Zulip's default dev-server port
PORT_STEP=10               # each worktree reserves a 10-port block

# ---------- Args ----------
REBUILD=0
NAME=""
for arg in "$@"; do
    case "$arg" in
        --rebuild)  REBUILD=1 ;;
        -h|--help)  sed -n '2,21p' "$SCRIPT_PATH"; exit 0 ;;
        -*) echo "Unknown flag: $arg" >&2; exit 2 ;;
        *)  [ -z "$NAME" ] || { echo "Multiple names: '$NAME' '$arg'" >&2; exit 2; }
            NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || {
    echo "Usage: $(basename "$SCRIPT_PATH") [--rebuild] <name>" >&2
    exit 2
}

# Reject names that collide with git's special refs or with our main
# branch. NAME="zulip" is the canonical clone (handled below); HEAD and
# main would later break `git worktree add`.
case "$NAME" in
    HEAD|main) echo "'$NAME' is reserved — pick a different name" >&2; exit 2 ;;
esac

# Canonicalise the paths so symlinked $HOME / $WORKTREE_ROOT (rare, but
# possible) don't trip up the `grep -Fxq "worktree $DIR"` match against
# git's canonical view later. readlink -m is safe on non-existent paths.
MAIN_WORKTREE="$(readlink -f -m -- "$MAIN_WORKTREE")"
DIR="$(readlink -f -m -- "$WORKTREE_ROOT/$NAME")"

IS_MAIN=0
if [ "$NAME" = "$MAIN_NAME" ]; then
    IS_MAIN=1
fi

# Reject worktree paths that would land inside the main clone (e.g. NAME
# = "zulip/sub" → DIR = ~/work/zulip/sub). Nested worktrees compile but
# are a footgun: the inner working tree shows up as untracked in the
# outer one.
case "$DIR/" in
    "$MAIN_WORKTREE"/*/) [ "$IS_MAIN" = 1 ] || {
        echo "$DIR is inside $MAIN_WORKTREE — refusing nested worktree" >&2
        exit 2
    } ;;
esac

step() { printf '\n== %s ==\n' "$*"; }


# ---------- 1. Prereqs ----------
# git, vagrant, docker on the host. If any are missing, print the install
# hint and bail.
step "Prerequisites"
missing=()
for cmd in git vagrant docker; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing: ${missing[*]}" >&2
    cat >&2 <<'EOF'

Install git + docker.io via apt:
  sudo apt-get install -y git docker.io
  sudo usermod -aG docker "$USER"   # log out / back in afterwards

Vagrant was dropped from Ubuntu 24.04 universe — get it from HashiCorp:
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install -y vagrant
EOF
    exit 1
fi

# Validate NAME as a legal git branch name now that we know git is here.
git check-ref-format "refs/heads/$NAME" 2>/dev/null || {
    echo "'$NAME' is not a legal git branch name (see git-check-ref-format)" >&2
    exit 2
}

# Refuse if the user has a HOST_PORT line in ~/.zulip-vagrant-config —
# that file is parsed by Zulip's Vagrantfile AFTER our patched in-tree
# value, so it would silently override every worktree's port and make
# them all collide on the same number.
if [ -f "$HOME/.zulip-vagrant-config" ] \
   && grep -qE '^HOST_PORT[[:space:]]' "$HOME/.zulip-vagrant-config"; then
    echo "Found a HOST_PORT line in ~/.zulip-vagrant-config." >&2
    echo "It would override our per-worktree patched port. Remove the line" >&2
    echo "(or the whole file) and re-run." >&2
    exit 1
fi

echo "ok"


# ---------- 2. Main clone ----------
# ~/work/zulip is the canonical clone. Validate completeness on every
# entry so a half-finished `git clone` from an earlier crashed run
# doesn't get treated as done.
step "Main clone at $MAIN_WORKTREE"
if [ -d "$MAIN_WORKTREE/.git" ]; then
    if git -C "$MAIN_WORKTREE" rev-parse HEAD >/dev/null 2>&1; then
        echo "already present"
    else
        echo "$MAIN_WORKTREE/.git exists but has no HEAD (broken half-clone)" >&2
        echo "Cleanup: rm -rf $MAIN_WORKTREE && re-run." >&2
        exit 1
    fi
elif [ -e "$MAIN_WORKTREE" ]; then
    echo "$MAIN_WORKTREE exists but isn't a git checkout — refusing" >&2
    exit 1
else
    # --config pull.rebase=true: matches Zulip's recommended workflow.
    git clone --config pull.rebase=true "$ORIGIN_URL" "$MAIN_WORKTREE"
    git -C "$MAIN_WORKTREE" rev-parse HEAD >/dev/null   # sanity-check
fi


# ---------- 3. Upstream remote ----------
step "Configure upstream remote"
if git -C "$MAIN_WORKTREE" remote get-url upstream >/dev/null 2>&1; then
    git -C "$MAIN_WORKTREE" remote set-url upstream "$UPSTREAM_URL"
else
    git -C "$MAIN_WORKTREE" remote add upstream "$UPSTREAM_URL"
fi
git -C "$MAIN_WORKTREE" fetch upstream


# ---------- 4. Worktree ----------
# IS_MAIN: this is ~/work/zulip — fast-forward main to upstream/main.
# Refuse the reset if local main has commits ahead of upstream/main, so
# the user doesn't silently lose unpushed work.
#
# Else: create a linked worktree at ~/work/<name> on a new branch <name>
# branching off upstream/main. Linked worktrees see the main clone's
# branch list, so a branch made here shows up in every other worktree.
if [ "$IS_MAIN" = 1 ]; then
    step "Reset main to upstream/main in $MAIN_WORKTREE"
    # Refuse if local main has commits not in upstream/main (would be
    # silently discarded by checkout -B). Refs are fully qualified so a
    # tag accidentally named "main" doesn't shadow the branch.
    if git -C "$MAIN_WORKTREE" rev-parse --verify refs/heads/main >/dev/null 2>&1 \
       && ! git -C "$MAIN_WORKTREE" merge-base --is-ancestor refs/heads/main upstream/main; then
        echo "Local main has commits not in upstream/main — refusing to reset." >&2
        echo "Push or rebase those commits, then re-run." >&2
        exit 1
    fi
    # Refuse if the working tree is dirty. checkout -B without -f errors
    # ugly when there are uncommitted conflicting changes; bail cleanly.
    if [ -n "$(git -C "$MAIN_WORKTREE" status --porcelain)" ]; then
        echo "Working tree in $MAIN_WORKTREE has uncommitted changes — refusing to reset." >&2
        echo "Stash or commit them, then re-run." >&2
        exit 1
    fi
    git -C "$MAIN_WORKTREE" checkout -B main upstream/main
else
    step "Add linked worktree $DIR on branch $NAME"
    # Drop stale registrations from earlier failed runs.
    git -C "$MAIN_WORKTREE" worktree prune
    if git -C "$MAIN_WORKTREE" worktree list --porcelain | grep -Fxq "worktree $DIR"; then
        echo "already a worktree"
    elif [ -e "$DIR" ]; then
        echo "$DIR exists but isn't registered as a worktree — refusing" >&2
        echo "Verify the dir is safe to drop, then: rm -rf $DIR && re-run." >&2
        exit 1
    elif git -C "$MAIN_WORKTREE" show-ref --verify --quiet "refs/heads/$NAME"; then
        # Branch already exists (e.g. user removed an old worktree of it).
        git -C "$MAIN_WORKTREE" worktree add "$DIR" "$NAME"
    else
        # Fresh branch off upstream/main, checked out at $DIR.
        git -C "$MAIN_WORKTREE" worktree add "$DIR" -b "$NAME" upstream/main
    fi
fi


# ---------- 5. Optional rebuild ----------
# --rebuild = destroy this worktree's VM and clear Vagrant state, so the
# next `vagrant up` rebuilds from scratch. Working tree, branch, and the
# allocated host port are kept (re-using the port is fine after destroy).
if [ "$REBUILD" = 1 ]; then
    step "Rebuild requested — destroying VM"
    if [ -d "$DIR/.vagrant" ]; then
        (cd "$DIR" && vagrant destroy -f)
        rm -rf "$DIR/.vagrant"
    else
        echo "no .vagrant/ to destroy"
    fi
fi


# ---------- 6. Host port (locked allocator) ----------
# flock on $LOCK_FILE serialises every concurrent invocation. The lock
# is released automatically when the script exits (fd 9 closes). -w 60
# bounds the wait so a stuck prior invocation gives up cleanly instead
# of blocking forever.
#
# Allocation strategy:
#   - if this worktree already has a marker, use it (resume case).
#     Also reseed last-port if marker > last-port, so a future cross-
#     name allocation doesn't collide with this one.
#   - else allocate max(every-existing-marker, last-port) + STEP. The
#     scan over markers means a prior partial-write (marker written,
#     last-port not yet) doesn't cause a cross-name collision.
step "Allocate host port"
mkdir -p "$STATE_DIR/worktrees"
exec 9>"$LOCK_FILE"
if ! flock -w 60 9; then
    echo "Couldn't acquire $LOCK_FILE after 60s — another invocation stuck?" >&2
    exit 1
fi
PORT_MARKER="$STATE_DIR/worktrees/$NAME.port"
LAST_PORT_FILE="$STATE_DIR/last-port"

read_numeric() {  # echo $1's file content if numeric, else echo nothing
    local f="$1" v
    [ -s "$f" ] || return 0
    v=$(<"$f")
    case "$v" in
        ''|*[!0-9]*) return 0 ;;
        *) printf '%s' "$v" ;;
    esac
}

if [ -s "$PORT_MARKER" ]; then
    PORT=$(read_numeric "$PORT_MARKER")
    [ -n "$PORT" ] || { echo "$PORT_MARKER has non-numeric content" >&2; exit 1; }
    # Reseed last-port so future cross-name allocations don't collide.
    PREV_LAST=$(read_numeric "$LAST_PORT_FILE")
    PREV_LAST="${PREV_LAST:-0}"
    if [ "$PORT" -gt "$PREV_LAST" ]; then
        echo "$PORT" > "$LAST_PORT_FILE"
    fi
    echo "already $PORT"
else
    # Refuse to silently re-allocate if a VM still exists for this DIR;
    # it would be running on the old (now-lost) port while we patch the
    # Vagrantfile to a new one — silent divergence.
    if [ -d "$DIR/.vagrant" ]; then
        state="$(env -C "$DIR" vagrant status --machine-readable 2>/dev/null \
            | awk -F, '$3=="state"{print $4; exit}')"
        case "$state" in
            running|poweroff|saved|aborted)
                echo "VM exists at $DIR (state: $state) but its port marker is missing." >&2
                echo "Restore $PORT_MARKER, or re-run with --rebuild." >&2
                exit 1 ;;
        esac
    fi
    # Take the max over every existing marker and last-port. A nullglob
    # avoids the literal "*.port" string when no markers exist yet.
    shopt -s nullglob
    MAX=0
    for f in "$STATE_DIR/worktrees"/*.port; do
        v=$(read_numeric "$f")
        [ -n "$v" ] && [ "$v" -gt "$MAX" ] && MAX=$v
    done
    shopt -u nullglob
    v=$(read_numeric "$LAST_PORT_FILE")
    [ -n "$v" ] && [ "$v" -gt "$MAX" ] && MAX=$v
    if [ "$MAX" -lt "$PORT_START" ]; then
        PORT=$PORT_START
    else
        PORT=$((MAX + PORT_STEP))
    fi
    echo "$PORT" > "$PORT_MARKER"
    echo "$PORT" > "$LAST_PORT_FILE"
    echo "$PORT (max was $MAX)"
fi


# ---------- 7. Patch Vagrantfile ----------
# Replace whatever host_port value Zulip's Vagrantfile ships with our
# allocated port. The grep gate makes the script fail loudly if Zulip
# ever changes the line shape, instead of sed-no-op'ing silently.
#
# `git update-index --skip-worktree <file>` makes git ignore our local
# edit: won't show in `git status`, and most commands avoid writing
# through to it. Per the git docs the flag is best-effort — merges,
# rebases, and resets can still write through if the operation
# requires it. Per-worktree; reversible with `--no-skip-worktree`.
step "Patch Vagrantfile host_port = $PORT"
VF="$DIR/Vagrantfile"
[ -f "$VF" ] || { echo "$VF missing — vagrant clone broken?" >&2; exit 1; }
grep -qE '^  host_port = [0-9]+$' "$VF" || {
    echo "$VF has no 'host_port = N' line — Vagrantfile shape changed?" >&2
    exit 1
}
sed -i -E "s/^  host_port = [0-9]+\$/  host_port = $PORT/" "$VF"
git -C "$DIR" update-index --skip-worktree Vagrantfile


# ---------- 8. Bring up the VM ----------
# `vagrant up` is idempotent: builds and starts a missing container,
# starts a halted one, no-ops if already running.
step "vagrant up --provider=docker"
(cd "$DIR" && vagrant up --provider=docker)


# ---------- 9. Install Claude in the VM ----------
# `vagrant upload` (documented) ships the settings file into the VM,
# then `vagrant ssh -c '<script>'` runs a tiny installer in the guest.
# The installer downloads claude.ai/install.sh to a file *first* (so a
# truncated download can't be silently fed to bash via a broken pipe)
# and runs it from disk.
step "Provision Claude inside the VM"
(cd "$DIR" && vagrant upload "$REPO_DIR/vm/claude-settings.json" /tmp/claude-settings.json)
(cd "$DIR" && vagrant ssh -c '
    set -euo pipefail
    mkdir -p ~/.claude
    install -m 0644 /tmp/claude-settings.json ~/.claude/settings.json
    rm -f /tmp/claude-settings.json
    if ! command -v claude >/dev/null; then
        curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
        bash /tmp/claude-install.sh
        rm -f /tmp/claude-install.sh
    fi
')


# ---------- 10. Hints ----------
step "Done"
cat <<EOF
Worktree:    $DIR
Branch:      $NAME
Host port:   $PORT   (dev server: http://localhost:$PORT)
SSH in:      cd $DIR && vagrant ssh
Run dev:     ./tools/run-dev          # inside the VM
Auth claude: claude                   # inside the VM, first time only

Re-running with the same name resumes from wherever the previous run died.
Re-run with --rebuild to destroy the VM and re-provision (keeps the worktree).
EOF
