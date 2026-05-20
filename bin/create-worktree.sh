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
ORB_IMAGE="${ORB_IMAGE:-ubuntu:24.04}"
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
# Ship claude settings, bash aliases, and an env file pinning EXTERNAL_HOST.
# Without EXTERNAL_HOST, Zulip's dev_settings.py routes non-localhost hosts
# to the marketing landing page. OrbStack's per-machine DNS name is the
# stable address; using that means parallel worktrees don't fight over the
# localhost:9991 port forward.
step "Provision the VM"
ZULIP_EXTERNAL_HOST="$NAME.orb.local:9991"

# orb -m runs as your Mac user inside the VM (passwordless sudo, configured
# automatically by OrbStack). Mac files mount at the same paths inside the
# machine, so $REPO_DIR resolves directly. $DIR is the Mac-side path
# (e.g. /Users/aman/work/<name>); inside the VM it resolves to the same
# location via OrbStack's home mount — VM-native $HOME is /home/<user>,
# which is a *different* path and does not contain the worktree.
orb -m "$NAME" bash <<EOF
    set -euo pipefail

    mkdir -p \$HOME/.claude \$HOME/.config/terminal-dev-setup \$HOME/.local/bin
    install -m 0644 "$REPO_DIR/vm/bash-aliases.sh"      \$HOME/.config/terminal-dev-setup/aliases.sh

    # OrbStack's Ubuntu 24.04 base image is minimal — no git, no curl, no jq.
    # git/curl are used immediately below (git config, curl for the claude
    # installer and the gh keyring). jq strips the host-only \`hooks\` block
    # out of host/claude-settings.json before installing it as the VM's
    # ~/.claude/settings.json — the hook commands point at host scripts
    # (\$HOME/.local/bin/claude-tmux-state.sh, claude-notify.sh) that don't
    # exist on the VM and don't make sense headless. Zulip's own
    # ./tools/provision installs git later but that runs *after* this script,
    # so install the essentials up front.
    if ! command -v git >/dev/null || ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \\
            git curl ca-certificates jq
    fi

    # Single source of truth for claude settings is host/claude-settings.json;
    # the VM gets the same file with \`hooks\` removed.
    jq 'del(.hooks)' "$REPO_DIR/host/claude-settings.json" \\
        > \$HOME/.claude/settings.json

    # Default editor for git commit messages, rebases, etc.
    git config --global core.editor vim

    if ! command -v claude >/dev/null; then
        # \`curl -f\` catches HTTP ≥400; the heredoc's set -o pipefail
        # propagates a curl exit-on-disconnect into bash so a partial
        # script doesn't run to completion. (Pipefail doesn't *prevent*
        # bash from executing the bytes it already received before
        # curl errors — for a hard transactional guarantee, download
        # to a temp file and \`bash file\` it; that's overkill here.)
        curl -fsSL https://claude.ai/install.sh | bash
    fi

    # gh: GitHub CLI via the official apt repo. Idempotent — apt-add is a
    # write-the-same-file pattern, and apt-get install on an up-to-date
    # package is a no-op. Keyring under /etc/apt/keyrings per current
    # Debian guidance (apt-key is deprecated since Ubuntu 22.04).
    if ! command -v gh >/dev/null 2>&1; then
        (
            sudo mkdir -p -m 755 /etc/apt/keyrings /etc/apt/sources.list.d
            # Download to a tempfile first, then sudo install — same
            # pattern upstream gh docs use (they call wget -O \$out then
            # cat | sudo tee). A streamed \`curl … | sudo tee\` would
            # write a partial keyring file before pipefail caught a
            # mid-transfer curl failure, leaving apt-get update to
            # complain about a bad signature on the next run.
            gh_tmp=\$(mktemp -d) && trap 'rm -rf "\$gh_tmp"' EXIT
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

    # Quote the RHS so a future $DIR or $ZULIP_EXTERNAL_HOST containing
    # spaces survives the source. The script already rejects whitespace
    # in $NAME (line 70 regex), so this is purely defensive — but cheap.
    cat > \$HOME/.zulip-dev-env.sh <<ENV
export EXTERNAL_HOST="$ZULIP_EXTERNAL_HOST"
export WORKTREE_DIR="$DIR"
ENV

    # Rewrite the managed block between begin/end markers on every run so
    # existing VMs pick up newly-added source lines without manual edits.
    begin="# >>> managed-by: create-worktree.sh >>>"
    end="# <<< managed-by: create-worktree.sh <<<"
    touch ~/.bashrc
    # Strip the legacy single-line marker + its source line from earlier
    # script versions (pre-begin/end block). Safe no-op if absent.
    sed -i.bak '/^# managed-by: create-worktree\.sh\$/,+1d' ~/.bashrc \\
        && rm -f ~/.bashrc.bak
    if grep -Fq "\$begin" ~/.bashrc; then
        # sed -i with a backup suffix works on both GNU and BSD sed; we're
        # in GNU-sed land here but the form is harmlessly portable.
        sed -i.bak "/\$begin/,/\$end/d" ~/.bashrc && rm -f ~/.bashrc.bak
    fi
    cat >> ~/.bashrc <<BASHRC

\$begin
source ~/.zulip-dev-env.sh
[ -f ~/.config/terminal-dev-setup/aliases.sh ] && source ~/.config/terminal-dev-setup/aliases.sh
# Auto-activate Zulip's Python venv. Guarded so a shell opened before
# ./tools/provision has created the venv still works.
[ -f "\$WORKTREE_DIR/.venv/bin/activate" ] && source "\$WORKTREE_DIR/.venv/bin/activate"
\$end
BASHRC
EOF


# ---------- 8. Done ----------
step "Done"
cat <<EOF
Dev server:  http://$ZULIP_EXTERNAL_HOST
SSH in:      orb -m $NAME
First time:  cd $DIR && ./tools/provision     # ~10–20 min
Each run:    cd $DIR && ./tools/run-dev --interface=''
             (--interface='' makes run-dev bind to all VM interfaces;
              without it, $NAME.orb.local is unreachable from the host)

Shortcuts (in a fresh shell — re-source ~/.bashrc, or just \`exec bash\`):
  zcd        cd into \$WORKTREE_DIR ($DIR)
  run        ./tools/run-dev --interface=  (the empty-interface form above)
  v / vi     vim (default Ubuntu vim; git core.editor is also vim)
EOF
