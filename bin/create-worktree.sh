#!/usr/bin/env bash
# create-worktree.sh — provision a Zulip dev VM.
#
# First time with the name "zulip" sets up the canonical clone at
# ~/work/zulip. Every other name becomes a linked `git worktree` of that
# main clone — they share the same .git/, so branches and commits are
# visible from every worktree.
#
# Usage: create-worktree.sh [--rebuild] <name>
#   --rebuild   destroy this worktree's VM and re-provision it
#               (keeps the working tree, branch, and host port intact)
#
# Re-running with the same name resumes from wherever a previous run died.

set -euo pipefail

# ---------- Config ----------
REPO_DIR="$(readlink -f -- "$(dirname -- "$0")/..")"

WORKTREE_ROOT="$HOME/work"
STATE_DIR="$HOME/.config/create-worktree"
MAIN_NAME="zulip"
MAIN_WORKTREE="$WORKTREE_ROOT/$MAIN_NAME"

ORIGIN_URL="git@github.com:amanagr/zulip.git"
UPSTREAM_URL="https://github.com/zulip/zulip.git"

PORT_START=9991
PORT_STEP=10

usage() { cat <<'EOF'
Usage: create-worktree.sh [--rebuild] <name>
  --rebuild   destroy this worktree's VM and re-provision it
              (keeps the working tree, branch, and host port intact)

First time with name "zulip" sets up the canonical clone at ~/work/zulip;
other names become linked git worktrees of it. Re-runs resume from wherever
a previous run died.
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

# Reserved names + shell-safe alphabet; git-check-ref-format (below, once
# git is known to exist) catches the rest (foo.lock, foo..bar, trailing-dot, …).
case "$NAME" in
    HEAD|head|main|.|..) echo "'$NAME' is reserved — pick a different name" >&2; exit 2 ;;
    .*|-*|*[!A-Za-z0-9._-]*)
        echo "'$NAME': use [A-Za-z0-9._-], must start with an alphanumeric" >&2
        exit 2 ;;
esac

# Canonicalise $DIR so the porcelain match against `git worktree list` works.
DIR="$(readlink -m -- "$WORKTREE_ROOT/$NAME")"

# Per-worktree fake HOME. Zulip's Vagrantfile reads HOST_PORT from
# $HOME/.zulip-vagrant-config; per-worktree ports need per-worktree HOMEs.
# VAGRANT_HOME/DOCKER_CONFIG stay on the real $HOME so plugin cache and
# docker auth survive the override. REAL_HOME captures $HOME before the
# vagrant_run prefix overrides it — env-prefix assignments evaluate
# left-to-right, so $HOME on the right side already sees the new value.
REAL_HOME="$HOME"
FAKE_HOME="$STATE_DIR/worktrees/$NAME/home"
mkdir -p "$FAKE_HOME"

vagrant_run() {
    HOME="$FAKE_HOME" VAGRANT_HOME="$REAL_HOME/.vagrant.d" \
        DOCKER_CONFIG="$REAL_HOME/.docker" vagrant "$@"
}

step() { printf '\n== %s ==\n' "$*"; }


# ---------- 1. Prereqs ----------
step "Prerequisites"
missing=()
for cmd in git vagrant docker; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
[ ${#missing[@]} -eq 0 ] || {
    echo "Missing: ${missing[*]} — see README.md for install hints" >&2; exit 1
}
git check-ref-format "refs/heads/$NAME" 2>/dev/null || {
    echo "'$NAME' is not a legal git branch name" >&2; exit 2
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
    # Don't use `checkout main || checkout -B main upstream/main` — a dirty-tree
    # checkout also exits 1, and the fallback's -B would force-reset local main
    # and silently discard unpushed commits.
    if git -C "$MAIN_WORKTREE" show-ref --verify --quiet refs/heads/main; then
        git -C "$MAIN_WORKTREE" checkout main
    else
        git -C "$MAIN_WORKTREE" checkout -b main upstream/main
    fi
    # pull --ff-only refuses on unpushed commits or a conflicting dirty tree.
    git -C "$MAIN_WORKTREE" pull --ff-only upstream main
else
    step "Add linked worktree $DIR on branch $NAME"
    if git -C "$MAIN_WORKTREE" worktree list --porcelain | grep -Fxq "worktree $DIR"; then
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


# ---------- 5. Optional rebuild ----------
if [ "$REBUILD" = 1 ]; then
    step "Rebuild requested — destroying VM"
    [ -d "$DIR/.vagrant" ] && (cd "$DIR" && vagrant_run destroy -f) || true
    rm -rf "$DIR/.vagrant"
fi


# ---------- 6. Host port ----------
# Per-worktree marker = source of truth. Resume hits the marker; fresh
# allocation takes max(all markers) + STEP, or PORT_START if no markers exist.
step "Allocate host port"
mkdir -p "$STATE_DIR/worktrees"
PORT_MARKER="$STATE_DIR/worktrees/$NAME.port"

if [ -s "$PORT_MARKER" ]; then
    PORT=$(cat "$PORT_MARKER")
    echo "already $PORT"
else
    MAX=$(cat "$STATE_DIR/worktrees"/*.port 2>/dev/null | sort -n | tail -1)
    PORT=$(( ${MAX:-0} + PORT_STEP > PORT_START ? ${MAX:-0} + PORT_STEP : PORT_START ))
    printf '%s\n' "$PORT" > "$PORT_MARKER"
    echo "$PORT"
fi


# ---------- 7. Per-worktree HOST_PORT ----------
step "Write HOST_PORT $PORT to $FAKE_HOME/.zulip-vagrant-config"
printf 'HOST_PORT %s\n' "$PORT" > "$FAKE_HOME/.zulip-vagrant-config"


# ---------- 8. Bring up the VM ----------
step "vagrant up --provider docker"
(cd "$DIR" && vagrant_run up --provider docker)


# ---------- 9. Provision the VM ----------
# Ship claude settings + an env file pinning EXTERNAL_HOST. Without
# EXTERNAL_HOST, Zulip's dev_settings.py routes non-9991 hosts to the
# marketing landing page.
step "Provision the VM"
printf 'export EXTERNAL_HOST=localhost:%s\n' "$PORT" > "$FAKE_HOME/zulip-dev-env.sh"

(cd "$DIR" && vagrant_run upload "$REPO_DIR/vm/claude-settings.json" /tmp/claude-settings.json)
(cd "$DIR" && vagrant_run upload "$FAKE_HOME/zulip-dev-env.sh" /tmp/zulip-dev-env.sh)
(cd "$DIR" && vagrant_run ssh -c '
    set -euo pipefail

    mkdir -p ~/.claude
    install -m 0644 /tmp/claude-settings.json ~/.claude/settings.json
    rm -f /tmp/claude-settings.json

    if ! command -v claude >/dev/null; then
        # Pipe rather than `curl -o file; bash file` — `curl -f` only catches
        # HTTP ≥400, not mid-transfer truncation. Piping + pipefail does.
        curl -fsSL https://claude.ai/install.sh | bash
    fi

    install -m 0644 /tmp/zulip-dev-env.sh ~/.zulip-dev-env.sh
    rm -f /tmp/zulip-dev-env.sh
    # Source from ~/.bashrc once. Distinguish grep-not-found (1) from grep-error
    # (2); a bare `|| append` would re-append on every run if ~/.bashrc became
    # unreadable. Marker also makes re-runs idempotent.
    mark="# managed-by: create-worktree.sh"
    if [ -e ~/.bashrc ] && grep -Fq "$mark" ~/.bashrc; then
        :
    else
        printf "\n%s\nsource ~/.zulip-dev-env.sh\n" "$mark" >> ~/.bashrc
    fi
')


# ---------- 10. Done ----------
step "Done"
cat <<EOF
Dev server:  http://localhost:$PORT
SSH in:      cd $DIR && vagrant ssh   # then: ./tools/run-dev
EOF
