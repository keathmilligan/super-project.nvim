#!/bin/sh
# Isolated HOME/XDG so host Neovim config never loads. Copies sandbox
# fixtures into /workspace and inits a git repo per project tree.
set -eu

if [ -z "${HOME:-}" ] || [ ! -w "${HOME:-/}" ]; then
  HOME=/tmp/nvim-home
fi
export HOME
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export NVIM_APPNAME="${NVIM_APPNAME:-super-project-test}"
export SUPER_PROJECT_ROOT="${SUPER_PROJECT_ROOT:-/plugin}"

mkdir -p \
  "$HOME" \
  "$XDG_CONFIG_HOME/$NVIM_APPNAME" \
  "$XDG_DATA_HOME" \
  "$XDG_STATE_HOME" \
  "$XDG_CACHE_HOME"

cp /opt/sp-nvim/init.lua "$XDG_CONFIG_HOME/$NVIM_APPNAME/init.lua"

SANDBOX_SRC="${SANDBOX_SRC:-$SUPER_PROJECT_ROOT/tests/sandbox}"
WORKSPACE="${WORKSPACE:-/workspace}"
mkdir -p "$WORKSPACE"

if [ -d "$SANDBOX_SRC" ] && [ ! -e "$WORKSPACE/README.md" ]; then
  # Copy children only. `cp -a src/. dest/` also utimes dest, which fails when
  # /workspace is root-owned and the container runs as the host user.
  find "$SANDBOX_SRC" -mindepth 1 -maxdepth 1 -exec cp -a {} "$WORKSPACE/" \;
fi

init_repo() {
  dir=$1
  name=$2
  if [ ! -d "$dir" ] || [ -d "$dir/.git" ]; then
    return 0
  fi
  git -C "$dir" init -q -b main
  git -C "$dir" add -A
  git -C "$dir" \
    -c user.email=sandbox@super-project.test \
    -c user.name='Sandbox' \
    commit -qm "$name"
}

init_repo "$WORKSPACE/alpha" "alpha fixtures"
init_repo "$WORKSPACE/beta" "beta fixtures"
init_repo "$WORKSPACE/gamma" "gamma fixtures"
init_repo "$WORKSPACE/notes" "notes fixtures"
init_repo "$WORKSPACE/archive" "excluded archive fixtures"

if [ -d "$WORKSPACE/gamma/.git" ]; then
  git -C "$WORKSPACE/gamma" checkout -qb feature/search 2>/dev/null || true
fi

cd "$WORKSPACE"

case "${1:-}" in
  test)
    shift
    cd "$SUPER_PROJECT_ROOT"
    exec make test
    ;;
  health)
    exec nvim --headless "+checkhealth super-project" "+qa"
    ;;
  shell)
    shift
    exec /bin/bash ${1+"$@"}
    ;;
  "")
    exec nvim
    ;;
  *)
    exec "$@"
    ;;
esac
