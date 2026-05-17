#!/usr/bin/env bash
# create-worktree.sh — provision a Zulip dev OrbStack machine.
#
# First time with the name "zulip" sets up the canonical clone at
# ~/work/zulip. Every other name becomes a linked `git worktree` of that
# main clone — they share the same .git/, so branches and commits are
# visible from every worktree.
#
# Each worktree gets its own OrbStack Linux machine named "<name>".
# OrbStack auto-shares your Mac home into the VM, so ~/work/<name> is
# visible inside the machine at the same path — no synced-folder config
# needed. Each machine has its own DNS name "<name>.orb.local"; the dev
# server is reachable at http://<name>.orb.local:9991 with no host-port
# allocation.
#
# Usage: create-worktree.sh [--rebuild] <name>
#   --rebuild   destroy this worktree's OrbStack machine and re-provision
#               (keeps the working tree and branch intact)
#
# Re-running with the same name resumes from wherever a previous run died.

set -euo pipefail

# ---------- Config ----------
# cd-pwd over readlink -f for portability — macOS readlink predates -f.
REPO_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"

WORKTREE_ROOT="$HOME/work"
MAIN_NAME="zulip"
MAIN_WORKTREE="$WORKTREE_ROOT/$MAIN_NAME"

ORIGIN_URL="git@github.com:amanagr/zulip.git"
UPSTREAM_URL="git@github.com:zulip/zulip.git"

# amd64 under Rosetta is within ~10% of native on Apple Silicon and
# avoids any arm64 surprises in Zulip's provision (downloaded binaries,
# pinned wheels). Override with ORB_ARCH=arm64 if you want native.
ORB_IMAGE="${ORB_IMAGE:-ubuntu:22.04}"
ORB_ARCH="${ORB_ARCH:-amd64}"

usage() { cat <<'EOF'
Usage: create-worktree.sh [--rebuild] <name>
  --rebuild   destroy this worktree's OrbStack machine and re-provision
              (keeps the working tree and branch intact)

First time with name "zulip" sets up the canonical clone at ~/work/zulip;
other names become linked git worktrees of it. Re-runs resume from
wherever a previous run died.
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

DIR="$WORKTREE_ROOT/$NAME"

step() { printf '\n== %s ==\n' "$*"; }


# ---------- 1. Prereqs ----------
step "Prerequisites"
missing=()
for cmd in git orb; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
[ ${#missing[@]} -eq 0 ] || {
    echo "Missing: ${missing[*]} — see ../CLAUDE.md for install hints" >&2; exit 1
}
git check-ref-format "refs/heads/$NAME" 2>/dev/null || {
    echo "'$NAME' is not a legal git branch name" >&2; exit 2
}
# OrbStack daemon reachable? Trust the exit code rather than grepping the
# output line — future sub-states like "Running (degraded)" would still
# be usable but would fail an exact "Running" string match.
orb status >/dev/null 2>&1 || {
    echo "OrbStack isn't running — launch OrbStack.app and retry" >&2; exit 1
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
    # Prune first so a worktree dir that was `rm -rf`d (without a proper
    # `git worktree remove`) doesn't keep its stale porcelain entry,
    # which would fool the next `grep -Fxq` into thinking the worktree
    # still exists.
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


# ---------- 5. Optional rebuild ----------
if [ "$REBUILD" = 1 ]; then
    step "Rebuild requested — destroying OrbStack machine '$NAME'"
    if orb info "$NAME" >/dev/null 2>&1; then
        orb delete -f "$NAME"
    fi
fi


# ---------- 6. Create OrbStack machine ----------
step "Create OrbStack machine '$NAME' ($ORB_IMAGE, $ORB_ARCH)"
if orb info "$NAME" >/dev/null 2>&1; then
    echo "already exists"
else
    orb create -a "$ORB_ARCH" "$ORB_IMAGE" "$NAME"
fi


# ---------- 7. Provision the VM ----------
# Ship claude settings + an env file pinning EXTERNAL_HOST. Without
# EXTERNAL_HOST, Zulip's dev_settings.py routes non-localhost hosts to the
# marketing landing page. OrbStack's per-machine DNS name is the stable
# address; using that means parallel worktrees don't fight over the
# localhost:9991 port forward.
step "Provision the VM"
ZULIP_EXTERNAL_HOST="$NAME.orb.local:9991"

# orb -m runs as your Mac user inside the VM (passwordless sudo, configured
# automatically by OrbStack). Mac files mount at the same paths inside the
# machine, so $REPO_DIR resolves directly.
orb -m "$NAME" bash <<EOF
    set -euo pipefail

    mkdir -p \$HOME/.claude
    install -m 0644 "$REPO_DIR/vm/claude-settings.json" \$HOME/.claude/settings.json

    if ! command -v claude >/dev/null; then
        # Pipe rather than \`curl -o file; bash file\` — \`curl -f\` only catches
        # HTTP ≥400, not mid-transfer truncation. Piping + pipefail does.
        curl -fsSL https://claude.ai/install.sh | bash
    fi

    cat > \$HOME/.zulip-dev-env.sh <<ENV
export EXTERNAL_HOST=$ZULIP_EXTERNAL_HOST
ENV

    # Source from ~/.bashrc once. Distinguish grep-not-found (1) from grep-error
    # (2); a bare \`|| append\` would re-append on every run if ~/.bashrc became
    # unreadable. Marker also makes re-runs idempotent.
    mark="# managed-by: create-worktree.sh"
    if [ -e ~/.bashrc ] && grep -Fq "\$mark" ~/.bashrc; then
        :
    else
        printf "\n%s\nsource ~/.zulip-dev-env.sh\n" "\$mark" >> ~/.bashrc
    fi
EOF


# ---------- 8. Done ----------
step "Done"
cat <<EOF
Dev server:  http://$ZULIP_EXTERNAL_HOST
SSH in:      orb -m $NAME
First time:  cd $DIR && ./tools/provision     # ~10–20 min
Each run:    cd $DIR && ./tools/run-dev
EOF
