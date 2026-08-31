#!/usr/bin/env bash
set -euo pipefail

launcher="${HOME}/.local/bin/codex-isolated"
verification_uid="$(id -u)"
verification_gid="$(id -g)"

[[ -x "$launcher" ]] || {
    echo "Missing executable launcher: $launcher" >&2
    exit 1
}

docker image inspect codex-isolated >/dev/null
docker volume inspect codex-isolated-uv-cache codex-isolated-uv-data >/dev/null

docker run --rm \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --tmpfs "/tmp:rw,nosuid,nodev,uid=${verification_uid},gid=${verification_gid}" \
    --entrypoint /bin/sh \
    codex-isolated -c '
    set -eu
    command -v bash >/dev/null
    find --version >/dev/null
    command -v git >/dev/null
    command -v jq >/dev/null
    command -v python3 >/dev/null
    python3 -c "import yaml" >/dev/null
    python3 -m pytest --version >/dev/null
    qt_runtime_dir="$(mktemp -d)"
    chmod 700 "$qt_runtime_dir"
    QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$qt_runtime_dir" \
        python3 -c "from PyQt5.QtWidgets import QApplication, QWidget; app = QApplication([]); widget = QWidget(); widget.show(); app.processEvents()"
    command -v rg >/dev/null
    ruby -e "require \"yaml\"" >/dev/null
    command -v uv >/dev/null
    command -v code-review-graph >/dev/null
    command -v wezterm-agent-state >/dev/null
'

docker run --rm \
    --env WEZTERM_PANE=verification \
    --env TMUX=verification \
    --entrypoint /bin/sh \
    codex-isolated -c '
        test "$WEZTERM_PANE" = verification
        test "$TMUX" = verification
    '

cmp -s "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/bin/codex-isolated" "$launcher" || {
    echo "Installed launcher differs from the repository source; run ./install.sh" >&2
    exit 1
}

echo "Launcher, image, runtime commands, and volumes are present."
echo "Run 'codex-isolated' from a non-sensitive test repository for interactive verification."
