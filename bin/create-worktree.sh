#!/usr/bin/env bash
# create-worktree.sh — provision a Zulip dev VM.
#
# First time you run this with the name "zulip" it sets up the canonical
# clone at ~/work/zulip. Every other name becomes a `git worktree` of that
# main clone — they share the same .git/, so branches and commits are
# visible from every worktree.
#
# Usage:
#   create-worktree.sh [--rebuild] [--ubuntu=NN.NN] <name>
#
#     --rebuild        destroy this worktree's VM and re-provision it
#                      (keeps the working tree and git branch intact)
#     --ubuntu=NN.NN   override the Ubuntu base in the Dockerfile (default 22.04)
#
# Re-running the script with the same name resumes from wherever the
# previous attempt died: every step checks for existing state first.

set -euo pipefail

# ---------- Config ----------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/work}"
STATE_DIR="${STATE_DIR:-$HOME/.config/create-worktree}"
MAIN_NAME="zulip"
MAIN_WORKTREE="$WORKTREE_ROOT/$MAIN_NAME"

ORIGIN_URL="git@github.com:amanagr/zulip.git"
UPSTREAM_URL="https://github.com/zulip/zulip.git"

UBUNTU_VERSION="22.04"     # Zulip's tested base — override via --ubuntu=…
PORT_START=9991            # Zulip's default dev-server port
PORT_STEP=10               # each worktree reserves a block of 10 ports

# ---------- Args ----------
REBUILD=0
NAME=""
for arg in "$@"; do
    case "$arg" in
        --rebuild)  REBUILD=1 ;;
        --ubuntu=*) UBUNTU_VERSION="${arg#--ubuntu=}" ;;
        -h|--help)  sed -n '2,18p' "$0"; exit 0 ;;
        -*) echo "Unknown flag: $arg" >&2; exit 2 ;;
        *)  [ -z "$NAME" ] || { echo "Multiple names: '$NAME' '$arg'" >&2; exit 2; }
            NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || {
    echo "Usage: $(basename "$0") [--rebuild] [--ubuntu=NN.NN] <name>" >&2
    exit 2
}

# Where this run's working tree lives. NAME == "zulip" → the main clone.
# Any other name → a linked worktree under ~/work/<name>.
DIR="$WORKTREE_ROOT/$NAME"
IS_MAIN=0
[ "$NAME" = "$MAIN_NAME" ] && IS_MAIN=1

step() { printf '\n== %s ==\n' "$*"; }


# ---------- 1. Prereqs ----------
# We need git, vagrant, and docker on the host. If any are missing we
# print the install hint and bail.
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
echo "ok"


# ---------- 2. Main clone ----------
# ~/work/zulip is the one and only repository checkout. All other
# worktrees share its .git/, so we always make sure it exists first.
step "Main clone at $MAIN_WORKTREE"
if [ -d "$MAIN_WORKTREE/.git" ]; then
    echo "already present"
elif [ -e "$MAIN_WORKTREE" ]; then
    echo "$MAIN_WORKTREE exists but isn't a git checkout — refusing to touch" >&2
    exit 1
else
    # --config pull.rebase=true matches Zulip's recommended workflow:
    # `git pull` will rebase instead of creating merge commits.
    git clone --config pull.rebase=true "$ORIGIN_URL" "$MAIN_WORKTREE"
fi


# ---------- 3. Upstream remote ----------
# We always branch new worktrees off `upstream/main` (the canonical
# zulip/zulip tip), not the fork's stale `origin/main`.
step "Configure upstream remote"
if git -C "$MAIN_WORKTREE" remote get-url upstream >/dev/null 2>&1; then
    git -C "$MAIN_WORKTREE" remote set-url upstream "$UPSTREAM_URL"
else
    git -C "$MAIN_WORKTREE" remote add upstream "$UPSTREAM_URL"
fi
git -C "$MAIN_WORKTREE" fetch upstream


# ---------- 4. Worktree ----------
# IS_MAIN: this *is* ~/work/zulip — just make sure its main branch is at
# upstream/main.
# Else: create a linked worktree at ~/work/<name> on a new branch <name>
# branching off upstream/main. Linked worktrees see the main clone's full
# branch list, so a branch created here shows up in every other worktree.
if [ "$IS_MAIN" = 1 ]; then
    step "Reset main to upstream/main in $MAIN_WORKTREE"
    git -C "$MAIN_WORKTREE" checkout -B main upstream/main
else
    step "Add linked worktree $DIR on branch $NAME"
    if git -C "$MAIN_WORKTREE" worktree list --porcelain | grep -qx "worktree $DIR"; then
        echo "already a worktree"
    elif [ -e "$DIR" ]; then
        echo "$DIR exists but isn't registered as a worktree — refusing to touch" >&2
        exit 1
    elif git -C "$MAIN_WORKTREE" show-ref --verify --quiet "refs/heads/$NAME"; then
        # Branch already exists (e.g. user removed an old worktree). Re-check it out.
        git -C "$MAIN_WORKTREE" worktree add "$DIR" "$NAME"
    else
        # Fresh branch off the upstream tip.
        git -C "$MAIN_WORKTREE" worktree add "$DIR" -b "$NAME" upstream/main
    fi
fi


# ---------- 5. Optional rebuild ----------
# --rebuild destroys this worktree's VM container and forgets the port,
# then falls through to the rest of the script which rebuilds them.
# Working tree / git state is untouched.
if [ "$REBUILD" = 1 ]; then
    step "Rebuild requested — destroying VM + clearing port marker"
    [ -d "$DIR/.vagrant" ] && (cd "$DIR" && vagrant destroy -f) || true
    rm -f "$STATE_DIR/worktrees/$NAME.port"
fi


# ---------- 6. Host port ----------
# Each worktree gets its own 10-port block: 9991, 10001, 10011, ...
# The chosen port is saved at ~/.config/create-worktree/worktrees/<name>.port
# so re-running the script doesn't burn ports on resume.
step "Allocate host port"
mkdir -p "$STATE_DIR/worktrees"
PORT_MARKER="$STATE_DIR/worktrees/$NAME.port"
if [ -r "$PORT_MARKER" ]; then
    PORT=$(cat "$PORT_MARKER")
    echo "already $PORT"
else
    LAST_PORT_FILE="$STATE_DIR/last-port"
    # Start before PORT_START so first allocation lands on it.
    PREV=$(cat "$LAST_PORT_FILE" 2>/dev/null || echo $((PORT_START - PORT_STEP)))
    PORT=$((PREV + PORT_STEP))
    echo "$PORT" > "$LAST_PORT_FILE"
    echo "$PORT" > "$PORT_MARKER"
    echo "$PORT (prev was $PREV)"
fi


# ---------- 7. Patch Vagrantfile + Dockerfile ----------
# sed -i edits the file in place. The regex matches *any* current value
# so the patch keeps working even if Zulip bumps their defaults upstream.
#
# After editing, `git update-index --skip-worktree <file>` tells git to
# ignore our local change to a tracked file:
#   - the edit stays in the working tree (Vagrant reads it)
#   - `git status` won't list it as modified
#   - `git pull` won't try to merge upstream changes into it
# It's per-worktree and reversible with `--no-skip-worktree`.
step "Patch Vagrantfile host_port = $PORT"
sed -i -E "s/^  host_port = [0-9]+$/  host_port = $PORT/" "$DIR/Vagrantfile"
git -C "$DIR" update-index --skip-worktree Vagrantfile

step "Patch Dockerfile FROM ubuntu:$UBUNTU_VERSION"
DF="tools/setup/dev-vagrant-docker/Dockerfile"
sed -i -E "s|^FROM ubuntu:[0-9.]+$|FROM ubuntu:$UBUNTU_VERSION|" "$DIR/$DF"
git -C "$DIR" update-index --skip-worktree "$DF"


# ---------- 8. Bring up the VM ----------
# `vagrant up` is idempotent: it builds + starts a container if missing,
# starts a halted one, no-ops if already running.
step "vagrant up --provider=docker"
(cd "$DIR" && vagrant up --provider=docker)


# ---------- 9. Install Claude in the VM ----------
# `vagrant ssh -c '<script>'` runs the inline script inside the container.
# stdin redirected from claude-settings.json lands inside the script at
# `cat > ~/.claude/settings.json`.
step "Provision Claude inside the VM"
(cd "$DIR" && vagrant ssh -c '
    set -euo pipefail
    mkdir -p ~/.claude
    cat > ~/.claude/settings.json   # JSON streamed in on stdin
    command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
') < "$REPO_DIR/vm/claude-settings.json"


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
