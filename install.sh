#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
launcher_target="${HOME}/.local/bin/codex-isolated"

command -v docker >/dev/null || {
    echo "docker is required" >&2
    exit 1
}

docker build \
    --build-arg "USER_ID=$(id -u)" \
    --build-arg "GROUP_ID=$(id -g)" \
    --tag codex-isolated \
    "${project_dir}"

install -D -m 0755 "${project_dir}/bin/codex-isolated" "${launcher_target}"
docker volume create codex-isolated-uv-cache >/dev/null
docker volume create codex-isolated-uv-data >/dev/null

echo "Installed launcher: ${launcher_target}"
echo "Installed Docker image: codex-isolated"
