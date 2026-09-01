#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
launcher_target="${HOME}/.local/bin/codex-isolated"

command -v docker >/dev/null || {
    echo "docker is required" >&2
    exit 1
}

command -v codex >/dev/null || {
    echo "the host Codex CLI is required" >&2
    exit 1
}

host_codex_version_output="$(codex --version)"
if [[ "$host_codex_version_output" =~ ^codex-cli[[:space:]]+([^[:space:]]+)$ ]]; then
    host_codex_version="${BASH_REMATCH[1]}"
else
    echo "Unable to determine the host Codex version from: $host_codex_version_output" >&2
    exit 1
fi

echo "Building isolated Codex ${host_codex_version} to match the host CLI."

docker build \
    --build-arg "USER_ID=$(id -u)" \
    --build-arg "GROUP_ID=$(id -g)" \
    --build-arg "CODEX_VERSION=${host_codex_version}" \
    --tag codex-isolated \
    "${project_dir}"

docker run --rm --entrypoint /bin/sh codex-isolated -c '
    set -eu
    bash --version | head -n 1
    find --version | head -n 1
    git --version
    jq --version
    notify-send --version
    python3 --version
    python3 -c "import yaml; print(\"PyYAML \" + yaml.__version__)"
    python3 -m pytest --version
    qt_runtime_dir="$(mktemp -d)"
    chmod 700 "$qt_runtime_dir"
    QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$qt_runtime_dir" \
        python3 -c "from PyQt5.QtWidgets import QApplication, QWidget; app = QApplication([]); widget = QWidget(); widget.show(); app.processEvents(); print(\"PyQt5 offscreen smoke test passed\")"
    rg --version | head -n 1
    ruby --version
    ruby -e "require \"yaml\""
    uv --version
    command -v code-review-graph
    wezterm-agent-state running
    codex --version
'

isolated_codex_version_output="$(
    docker run --rm codex-isolated --version
)"
if [[ "$isolated_codex_version_output" != "$host_codex_version_output" ]]; then
    echo "Codex version mismatch after build:" >&2
    echo "  host:     $host_codex_version_output" >&2
    echo "  isolated: $isolated_codex_version_output" >&2
    exit 1
fi

install -D -m 0755 "${project_dir}/bin/codex-isolated" "${launcher_target}"
docker volume create codex-isolated-uv-cache >/dev/null
docker volume create codex-isolated-uv-data >/dev/null

echo "Installed launcher: ${launcher_target}"
echo "Installed Docker image: codex-isolated"
echo "Codex version: ${host_codex_version} (matches host)"
