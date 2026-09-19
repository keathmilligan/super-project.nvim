#!/usr/bin/env bash
# Run the isolated Neovim test environment.
# Usage: tests/env/run.sh [build|test|health|shell|nvim] [args...]
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
image=${SUPER_PROJECT_IMAGE:-super-project-test}

if command -v docker >/dev/null 2>&1; then
  engine=docker
elif command -v podman >/dev/null 2>&1; then
  engine=podman
else
  echo 'docker or podman is required' >&2
  exit 1
fi

build() {
  "$engine" build -t "$image" -f "$root/tests/env/Dockerfile" "$root"
}

cmd=${1:-nvim}
if [[ $cmd == build ]]; then
  build
  exit 0
fi
if [[ $cmd == -h || $cmd == --help || $cmd == help ]]; then
  cat <<EOF
Usage: tests/env/run.sh [command] [args...]

  (default)   Interactive Neovim in /workspace
  nvim [file] Open a file (path relative to /workspace)
  test        Headless unit tests
  health      :checkhealth super-project
  shell       Bash in the container
  build       Build the image
EOF
  exit 0
fi

if ! "$engine" image inspect "$image" >/dev/null 2>&1; then
  build
fi

if [[ $# -gt 0 ]]; then
  shift
fi

opts=(
  --rm
  -i
  -u "$(id -u):$(id -g)"
  -e TERM
  -e COLORTERM
  -v "$root:/plugin"
  -w /workspace
)

if [[ -t 0 && -t 1 ]]; then
  opts+=(-t)
fi

case $cmd in
  test)
    exec "$engine" run "${opts[@]}" "$image" test "$@"
    ;;
  health)
    exec "$engine" run "${opts[@]}" "$image" health
    ;;
  shell)
    exec "$engine" run "${opts[@]}" "$image" shell "$@"
    ;;
  nvim)
    exec "$engine" run "${opts[@]}" "$image" nvim "$@"
    ;;
  *)
    exec "$engine" run "${opts[@]}" "$image" nvim "$cmd" "$@"
    ;;
esac
