#!/usr/bin/env bash
set -euo pipefail

launcher="${HOME}/.local/bin/codex-isolated"

[[ -x "$launcher" ]] || {
    echo "Missing executable launcher: $launcher" >&2
    exit 1
}

docker image inspect codex-isolated >/dev/null
docker volume inspect codex-isolated-uv-cache codex-isolated-uv-data >/dev/null

echo "Launcher, image, and runtime volumes are present."
echo "Run 'codex-isolated' from a non-sensitive test repository for interactive verification."
