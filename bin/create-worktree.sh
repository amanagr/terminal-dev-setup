#!/usr/bin/env bash
# Provision a fresh Zulip dev worktree in a Vagrant/Docker VM with Claude
# pre-configured. Usage:
#
#   create-worktree.sh [--dry-run] <name>
#
# Each invocation gets a unique host-port block for the dev server, tracked
# in ~/.config/create-worktree/last-port (monotonic, +10 per call).
set -euo pipefail

# Resolve symlinks so `claude-settings.json` is found relative to the real
# repo even when invoked via `~/.local/bin/create-worktree`.
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/work}"
PORT_STATE_FILE="${PORT_STATE_FILE:-$HOME/.config/create-worktree/last-port}"
PORT_START=9991
PORT_STEP=10

ORIGIN_URL="git@github.com:amanagr/zulip.git"
UPSTREAM_URL="git@github.com:zulip/zulip.git"

DRY=0
NAME=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        -*) echo "Unknown flag: $arg" >&2; exit 2 ;;
        *)
            if [ -n "$NAME" ]; then echo "Multiple names given: '$NAME' '$arg'" >&2; exit 2; fi
            NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || { echo "Usage: $(basename "$0") [--dry-run] <name>" >&2; exit 2; }

DIR="$WORKTREE_ROOT/$NAME"

run()  { if [ "$DRY" = 1 ]; then echo "  + $*"; else "$@"; fi; }
say()  { printf '\n== %s ==\n' "$*"; }

# 1. Prereqs.
say "Check prerequisites"
missing=()
for cmd in git vagrant docker; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing: ${missing[*]}" >&2
    cat >&2 <<'EOF'

git + docker.io come from apt directly:
  sudo apt-get install -y git docker.io
  sudo usermod -aG docker "$USER"   # log out / back in after this

Vagrant was dropped from Ubuntu 24.04 universe — install from
HashiCorp's apt repo:
  wget -O- https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install -y vagrant
EOF
    [ "$DRY" = 1 ] || exit 1
fi
echo "ok"

# 2. Worktree directory.
say "Worktree directory"
if [ -e "$DIR" ]; then echo "$DIR already exists; refusing to overwrite" >&2; exit 1; fi
echo "$DIR"

# 3. Clone fork + add upstream.
say "Clone fork as origin, add upstream"
run git clone "$ORIGIN_URL" "$DIR"
run git -C "$DIR" remote add upstream "$UPSTREAM_URL"
run git -C "$DIR" fetch upstream

# 4. Reset main to upstream/main.
say "Reset main to upstream/main"
run git -C "$DIR" checkout -B main upstream/main

# 5. Allocate host port.
say "Allocate host port"
if [ -r "$PORT_STATE_FILE" ]; then
    prev=$(cat "$PORT_STATE_FILE")
    port=$((prev + PORT_STEP))
else
    port=$PORT_START
fi
echo "port: $port (prev: ${prev:-<none>})"
if [ "$DRY" = 0 ]; then
    mkdir -p "$(dirname "$PORT_STATE_FILE")"
    echo "$port" > "$PORT_STATE_FILE"
    echo "$port" > "$DIR/.host-port"
fi

# 6. Patch the cloned Vagrantfile so this worktree gets its own port.
say "Patch Vagrantfile host_port"
run sed -i "s/^  host_port = 9991$/  host_port = $port/" "$DIR/Vagrantfile"

# 6b. Point the docker provider at ubuntu:26.04 (Zulip ships 22.04 by default).
say "Patch dev-vagrant-docker/Dockerfile FROM line"
run sed -i "s|^FROM ubuntu:22\.04\$|FROM ubuntu:26.04|" \
    "$DIR/tools/setup/dev-vagrant-docker/Dockerfile"

# 7. vagrant up.
say "vagrant up --provider=docker"
if [ "$DRY" = 1 ]; then
    echo "  + (cd $DIR && vagrant up --provider=docker)"
else
    (cd "$DIR" && vagrant up --provider=docker)
fi

# 8. Install Claude in the VM and ship the settings file.
say "Install Claude inside the VM"
provision_script=$(cat <<'EOSH'
set -euo pipefail
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json"   # JSON is streamed in on stdin after the heredoc.
if ! command -v claude >/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
fi
EOSH
)
if [ "$DRY" = 1 ]; then
    echo "  + vagrant ssh -c '<provision-script>' < $REPO_DIR/vm/claude-settings.json"
else
    (cd "$DIR" && vagrant ssh -c "$provision_script") < "$REPO_DIR/vm/claude-settings.json"
fi

# 9. Hints.
say "Done"
cat <<EOF
Worktree:   $DIR
Host port:  $port  (dev server: http://localhost:$port)
SSH in:     cd $DIR && vagrant ssh
Run dev:    ./tools/run-dev          # inside the VM
EOF
