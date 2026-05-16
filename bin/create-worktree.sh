#!/usr/bin/env bash
# Provision a Zulip dev worktree in a Vagrant/Docker VM with Claude
# pre-configured. Re-runnable: every step probes state first and only does
# what's missing, so a failed run resumes from where it died.
#
# Usage:
#   create-worktree.sh [--dry-run] [--rebuild] [--ubuntu=NN.NN] <name>
#
#   --dry-run    Print each step's action without executing it.
#   --rebuild    `vagrant destroy -f` and clear .host-port before resuming.
#   --ubuntu     Override the in-container Ubuntu base (default 26.04).
#
# Host port for each worktree is monotonic across `create-worktree` runs
# (`~/.config/create-worktree/last-port`, +10 per worktree). The chosen
# port is persisted at `<worktree>/.host-port` so resumes don't burn ports.
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/work}"
# All script-private state lives under ~/.config/create-worktree/ so the Zulip
# clone stays clean: `last-port` is the global monotonic counter, and the
# per-worktree port assignment goes in `worktrees/<name>.port`.
STATE_DIR="${STATE_DIR:-$HOME/.config/create-worktree}"
PORT_STATE_FILE="${PORT_STATE_FILE:-$STATE_DIR/last-port}"
WORKTREE_STATE_DIR="${WORKTREE_STATE_DIR:-$STATE_DIR/worktrees}"
PORT_START=9991
PORT_STEP=10

ORIGIN_URL="git@github.com:amanagr/zulip.git"
UPSTREAM_URL="https://github.com/zulip/zulip.git"

UBUNTU_VERSION="26.04"
DRY=0
REBUILD=0
NAME=""
for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY=1 ;;
        --rebuild)  REBUILD=1 ;;
        --ubuntu=*) UBUNTU_VERSION="${arg#--ubuntu=}" ;;
        -h|--help)  sed -n '2,15p' "$0"; exit 0 ;;
        -*)         echo "Unknown flag: $arg" >&2; exit 2 ;;
        *)          [ -z "$NAME" ] || { echo "Multiple names: '$NAME' '$arg'" >&2; exit 2; }
                    NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || { echo "Usage: $(basename "$0") [--dry-run] [--rebuild] [--ubuntu=NN.NN] <name>" >&2; exit 2; }

DIR="$WORKTREE_ROOT/$NAME"

say()  { printf '\n== %s ==\n' "$*"; }
skip() { echo "  · $* (already done)"; }
do_()  { echo "  + $*"; [ "$DRY" = 1 ] || "$@"; }

# ---------------------------------------------------------------------------
# Step 1: prereqs.
# ---------------------------------------------------------------------------
ensure_prereqs() {
    say "Check prerequisites"
    local missing=()
    for cmd in git vagrant docker; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        echo "ok"
        return
    fi
    echo "Missing: ${missing[*]}" >&2
    cat >&2 <<'EOF'

git + docker.io come from apt directly:
  sudo apt-get install -y git docker.io
  sudo usermod -aG docker "$USER"   # log out / back in after this

Vagrant was dropped from Ubuntu 24.04 universe — install from
HashiCorp's apt repo. (curl -fsSL fails loudly on HTTP errors so we
don't end up with a silent zero-byte keyring; gpg --dearmor --yes
overwrites any leftover file from a prior failed attempt.)
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install -y vagrant
EOF
    [ "$DRY" = 1 ] || exit 1
}

# ---------------------------------------------------------------------------
# Step 2: rebuild guard. If --rebuild is on, nuke the VM + port marker so
# the rest of the script treats this worktree as fresh.
# ---------------------------------------------------------------------------
maybe_rebuild() {
    [ "$REBUILD" = 1 ] || return 0
    say "Rebuild requested — wiping VM + port marker"
    if [ -d "$DIR/.vagrant" ]; then
        do_ env -C "$DIR" vagrant destroy -f
    else
        skip "no .vagrant/ in $DIR"
    fi
    [ -f "$WORKTREE_STATE_DIR/$NAME.port" ] && do_ rm -f "$WORKTREE_STATE_DIR/$NAME.port"
}

# ---------------------------------------------------------------------------
# Step 3: clone the fork if not already cloned.
# ---------------------------------------------------------------------------
ensure_clone() {
    say "Clone fork as origin"
    if [ -d "$DIR/.git" ]; then
        local got
        got="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
        if [ "$got" = "$ORIGIN_URL" ]; then
            skip "$DIR already cloned with matching origin"
            return
        fi
        echo "$DIR exists with a different origin ('$got'); refusing to touch" >&2
        exit 1
    fi
    if [ -e "$DIR" ]; then
        echo "$DIR exists but is not a git checkout; refusing to touch" >&2
        exit 1
    fi
    do_ git clone --config pull.rebase=true "$ORIGIN_URL" "$DIR"
}

# ---------------------------------------------------------------------------
# Step 4: upstream remote (add if missing, otherwise just verify URL).
# ---------------------------------------------------------------------------
ensure_upstream() {
    say "Configure upstream remote"
    [ "$DRY" = 0 ] || { echo "  + git -C $DIR remote add/set-url upstream $UPSTREAM_URL"; return; }
    if git -C "$DIR" remote get-url upstream >/dev/null 2>&1; then
        do_ git -C "$DIR" remote set-url upstream "$UPSTREAM_URL"
    else
        do_ git -C "$DIR" remote add upstream "$UPSTREAM_URL"
    fi
    do_ git -C "$DIR" fetch upstream
}

# ---------------------------------------------------------------------------
# Step 5: reset local main to upstream/main only if it's not already there.
# Skip the reset when local main already matches the upstream tip.
# ---------------------------------------------------------------------------
ensure_main_at_upstream() {
    say "Sync main to upstream/main"
    [ "$DRY" = 0 ] || { echo "  + git -C $DIR checkout -B main upstream/main (if needed)"; return; }
    local upstream_sha local_sha
    upstream_sha=$(git -C "$DIR" rev-parse upstream/main)
    local_sha=$(git -C "$DIR" rev-parse main 2>/dev/null || true)
    if [ -n "$local_sha" ] && [ "$upstream_sha" = "$local_sha" ] && [ "$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null)" = "main" ]; then
        skip "main already at upstream/main ($upstream_sha)"
        return
    fi
    do_ git -C "$DIR" checkout -B main upstream/main
}

# ---------------------------------------------------------------------------
# Step 6: port allocation. Prefer the per-worktree marker if it exists, so
# resumes re-use the same port. Only advance last-port on first allocation.
# ---------------------------------------------------------------------------
PORT=""
ensure_port() {
    say "Allocate host port"
    local marker="$WORKTREE_STATE_DIR/$NAME.port"
    # Migration: earlier versions wrote .host-port inside the worktree.
    # If we find one, adopt its value and clean it up so `git status` is
    # clean for the user.
    if [ -r "$DIR/.host-port" ] && [ ! -r "$marker" ] && [ "$DRY" = 0 ]; then
        mkdir -p "$WORKTREE_STATE_DIR"
        mv "$DIR/.host-port" "$marker"
        echo "  · migrated $DIR/.host-port → $marker"
    fi
    if [ -r "$marker" ]; then
        PORT=$(cat "$marker")
        skip "worktree already has port $PORT (from $marker)"
        return
    fi
    local prev=""
    if [ -r "$PORT_STATE_FILE" ]; then
        prev=$(cat "$PORT_STATE_FILE")
        PORT=$((prev + PORT_STEP))
    else
        PORT=$PORT_START
    fi
    echo "  + port: $PORT (prev: ${prev:-<none>})"
    if [ "$DRY" = 0 ]; then
        mkdir -p "$WORKTREE_STATE_DIR"
        echo "$PORT" > "$PORT_STATE_FILE"
        echo "$PORT" > "$marker"
    fi
}

# ---------------------------------------------------------------------------
# Step 7: Vagrantfile host_port. Idempotent: matches any current value and
# only writes if the file is out of sync with $PORT.
# ---------------------------------------------------------------------------
ensure_vagrantfile_port() {
    say "Patch Vagrantfile host_port = $PORT"
    local vf="$DIR/Vagrantfile"
    if [ "$DRY" = 1 ] && [ ! -f "$vf" ]; then
        echo "  + sed -i -E 's/^  host_port = [0-9]+$/  host_port = $PORT/' $vf"
        echo "  + git update-index --skip-worktree Vagrantfile  # hide local edit from git status"
        return
    fi
    [ -f "$vf" ] || { echo "  ! $vf missing — vagrant clone broken?" >&2; exit 1; }
    if ! grep -qE "^  host_port = ${PORT}$" "$vf"; then
        do_ sed -i -E "s/^  host_port = [0-9]+$/  host_port = $PORT/" "$vf"
    else
        skip "Vagrantfile already at port $PORT"
    fi
    # skip-worktree is idempotent and survives across runs.
    do_ git -C "$DIR" update-index --skip-worktree Vagrantfile
}

# ---------------------------------------------------------------------------
# Step 8: Dockerfile FROM. Idempotent: matches any current ubuntu version.
# ---------------------------------------------------------------------------
ensure_dockerfile_ubuntu() {
    local df_rel="tools/setup/dev-vagrant-docker/Dockerfile"
    local df="$DIR/$df_rel"
    say "Patch $df_rel FROM ubuntu:$UBUNTU_VERSION"
    if [ "$DRY" = 1 ] && [ ! -f "$df" ]; then
        echo "  + sed -i -E 's|^FROM ubuntu:[0-9.]+\$|FROM ubuntu:$UBUNTU_VERSION|' $df"
        echo "  + git update-index --skip-worktree $df_rel  # hide local edit from git status"
        return
    fi
    [ -f "$df" ] || { echo "  ! $df missing — Zulip layout changed?" >&2; exit 1; }
    if ! grep -qE "^FROM ubuntu:${UBUNTU_VERSION//./\\.}$" "$df"; then
        do_ sed -i -E "s|^FROM ubuntu:[0-9.]+$|FROM ubuntu:$UBUNTU_VERSION|" "$df"
    else
        skip "Dockerfile already pinned to ubuntu:$UBUNTU_VERSION"
    fi
    do_ git -C "$DIR" update-index --skip-worktree "$df_rel"
}

# ---------------------------------------------------------------------------
# Step 9: ensure the VM is running. Probe `vagrant status`, only `up` if
# the container isn't already running. Vagrant itself is idempotent here,
# but explicit probing makes the script's output clearer.
# ---------------------------------------------------------------------------
ensure_vm_running() {
    say "Ensure VM is running"
    if [ "$DRY" = 1 ]; then
        echo "  + (cd $DIR && vagrant status | grep state, then vagrant up --provider=docker if not running)"
        return
    fi
    local state
    state="$(env -C "$DIR" vagrant status --machine-readable 2>/dev/null | awk -F, '$3=="state"{print $4; exit}')"
    case "$state" in
        running)
            skip "VM already running"
            return ;;
        not_created|"")
            do_ env -C "$DIR" vagrant up --provider=docker ;;
        *)
            echo "  · VM state '$state' — bringing up"
            do_ env -C "$DIR" vagrant up --provider=docker ;;
    esac
}

# ---------------------------------------------------------------------------
# Step 10: copy claude-settings.json + install claude if missing inside the
# VM. The provision script is already internally idempotent so it's safe
# to re-run on every invocation.
# ---------------------------------------------------------------------------
ensure_claude_in_vm() {
    say "Provision Claude inside the VM"
    local provision_script
    provision_script=$(cat <<'EOSH'
set -euo pipefail
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json"   # JSON streamed on stdin
if ! command -v claude >/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
fi
EOSH
)
    if [ "$DRY" = 1 ]; then
        echo "  + vagrant ssh -c '<provision-script>' < $REPO_DIR/vm/claude-settings.json"
        return
    fi
    (cd "$DIR" && vagrant ssh -c "$provision_script") < "$REPO_DIR/vm/claude-settings.json"
}

# ---------------------------------------------------------------------------
# Step 11: hints.
# ---------------------------------------------------------------------------
print_hints() {
    say "Done"
    cat <<EOF
Worktree:    $DIR
Host port:   $PORT  (dev server: http://localhost:$PORT)
SSH in:      cd $DIR && vagrant ssh
Run dev:     ./tools/run-dev          # inside the VM
Auth claude: claude                   # inside the VM, first time only — opens a browser auth flow

Re-running this script with the same name resumes from where it died.
Re-run with --rebuild to destroy the VM and start the provisioner fresh.
EOF
}

# ===========================================================================
# Run.
# ===========================================================================
ensure_prereqs
ensure_clone        # before maybe_rebuild — destroy needs a cloned tree
maybe_rebuild
ensure_upstream
ensure_main_at_upstream
ensure_port
ensure_vagrantfile_port
ensure_dockerfile_ubuntu
ensure_vm_running
ensure_claude_in_vm
print_hints
