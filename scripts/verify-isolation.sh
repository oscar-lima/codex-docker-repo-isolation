#!/usr/bin/env bash
set -euo pipefail

launcher="${HOME}/.local/bin/codex-isolated"
notification_relay="${HOME}/.local/bin/codex-wezterm-notify"
verification_uid="$(id -u)"
verification_gid="$(id -g)"

[[ -x "$launcher" ]] || {
    echo "Missing executable launcher: $launcher" >&2
    exit 1
}

[[ -x "$notification_relay" ]] || {
    echo "Missing executable notification relay: $notification_relay" >&2
    exit 1
}

resolved_notification_relay="$(command -v codex-wezterm-notify || true)"
[[ -n "$resolved_notification_relay" ]] || {
    echo "codex-wezterm-notify is not on the host PATH" >&2
    exit 1
}
[[ "$(realpath -e -- "$resolved_notification_relay")" == "$(realpath -e -- "$notification_relay")" ]] || {
    echo "codex-wezterm-notify resolves to an unexpected host command: $resolved_notification_relay" >&2
    exit 1
}

command -v xdg-dbus-proxy >/dev/null || {
    echo "xdg-dbus-proxy is required on the host" >&2
    exit 1
}

xdg-dbus-proxy --version >/dev/null

docker image inspect codex-isolated >/dev/null
docker volume inspect codex-isolated-uv-cache codex-isolated-uv-data >/dev/null

docker run --rm \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --tmpfs "/tmp:rw,nosuid,nodev,uid=${verification_uid},gid=${verification_gid}" \
    --mount "type=bind,source=/usr/lib/chatgpt/resources/codex,target=/usr/lib/chatgpt/resources/codex,readonly" \
    --mount "type=bind,source=/usr/lib/chatgpt/resources/cua_node/bin/node_repl,target=/usr/lib/chatgpt/resources/cua_node/bin/node_repl,readonly" \
    --mount "type=bind,source=/usr/lib/chatgpt/resources/cua_node/lib/node_modules,target=/usr/lib/chatgpt/resources/cua_node/lib/node_modules,readonly" \
    --entrypoint /bin/sh \
    codex-isolated -c '
    set -eu
    ! command -v docker >/dev/null
    ! command -v wezterm >/dev/null
    test ! -S /var/run/docker.sock
    test -z "$(find /run/user -type s -iname "*wezterm*" -print -quit)"
    /usr/lib/chatgpt/resources/cua_node/bin/node --version >/dev/null
    /usr/lib/chatgpt/resources/cua_node/bin/node_repl --help >/dev/null
    command -v bash >/dev/null
    curl --version >/dev/null
    find --version >/dev/null
    command -v git >/dev/null
    command -v identify >/dev/null
    command -v jq >/dev/null
    xmllint --version >/dev/null 2>&1
    grep -Eq "^[0-9a-f]{32}$" /etc/machine-id
    command -v notify-send >/dev/null
    command -v python3 >/dev/null
    python3 -m pip --version >/dev/null
    python3 -c "import build, setuptools, wheel" >/dev/null
    python3 -c "import numpy" >/dev/null
    python3 -c "import yaml" >/dev/null
    python3 -m pytest --version >/dev/null
    qt_runtime_dir="$(mktemp -d)"
    chmod 700 "$qt_runtime_dir"
    QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$qt_runtime_dir" \
        python3 -c "from PyQt5.QtWidgets import QApplication, QWidget; app = QApplication([]); widget = QWidget(); widget.show(); app.processEvents()"
    command -v rg >/dev/null
    ruby -e "require \"yaml\"" >/dev/null
    shellcheck --version >/dev/null
    sqlite3 --version >/dev/null
    pdftotext -v >/dev/null 2>&1
    command -v unzip >/dev/null
    command -v uv >/dev/null
    yq --version >/dev/null
    zip -v >/dev/null
    command -v code-review-graph >/dev/null
    command -v codex-wezterm-notify >/dev/null
    grep -F "SetUserVar=" "$(command -v codex-wezterm-notify)" >/dev/null
    codex-wezterm-notify "{\"type\":\"smoke-test\"}"
    command -v wezterm-agent-state >/dev/null
'

docker run --rm \
    --env COLORTERM=truecolor \
    --env TERM=xterm-256color \
    --env TERM_PROGRAM=WezTerm \
    --env TERM_PROGRAM_VERSION=verification \
    --env WEZTERM_PANE=verification \
    --env TMUX=verification \
    --entrypoint /bin/sh \
    codex-isolated -c '
        test "$COLORTERM" = truecolor
        test "$TERM" = xterm-256color
        test "$TERM_PROGRAM" = WezTerm
        test "$TERM_PROGRAM_VERSION" = verification
        test "$WEZTERM_PANE" = verification
        test "$TMUX" = verification
    '

# Make Codex validate the shared external notification configuration against
# the installed CLI version. The command does not need authentication or a session.
docker run --rm \
    --entrypoint codex \
    codex-isolated \
    -c 'notify=["codex-wezterm-notify"]' \
    -c 'tui.notifications=[]' \
    features list >/dev/null

python3 -c '
import pathlib
import tomllib
config = tomllib.loads(pathlib.Path.home().joinpath(".codex/config.toml").read_text())
if config.get("notify") != ["codex-wezterm-notify"]:
    raise SystemExit("~/.codex/config.toml must set notify = [\"codex-wezterm-notify\"]")
if config.get("tui", {}).get("notifications") != []:
    raise SystemExit("~/.codex/config.toml must set tui.notifications = []")
'

rg -F -- '--env TERM_PROGRAM' "$launcher" >/dev/null
rg -F -- 'xdg-dbus-proxy' "$launcher" >/dev/null
rg -F -- '--filter' "$launcher" >/dev/null
rg -F -- '--call=org.freedesktop.Notifications=org.freedesktop.Notifications@/org/freedesktop/Notifications' "$launcher" >/dev/null
rg -F -- '--broadcast=org.freedesktop.Notifications=org.freedesktop.Notifications@/org/freedesktop/Notifications' "$launcher" >/dev/null
rg -F -- 'DBUS_SESSION_BUS_ADDRESS=unix:path=' "$launcher" >/dev/null
if rg -F -- 'source=${notification_bus}' "$launcher" >/dev/null; then
    echo "Launcher exposes the unfiltered host D-Bus session socket." >&2
    exit 1
fi
if rg -F -- '/var/run/docker.sock' "$launcher" >/dev/null; then
    echo "Launcher exposes the host Docker socket." >&2
    exit 1
fi
if rg -i -- '--mount.*wezterm|--volume.*wezterm|wezterm.*\.sock' "$launcher" >/dev/null; then
    echo "Launcher exposes a host WezTerm control path." >&2
    exit 1
fi
if rg -F -- 'WEZTERM_UNIX_SOCKET' "$launcher" >/dev/null; then
    echo "Launcher forwards the host WezTerm control socket." >&2
    exit 1
fi
if rg -F -- 'source=/etc/machine-id' "$launcher" >/dev/null; then
    echo "Launcher exposes the host machine ID." >&2
    exit 1
fi
rg -F -- 'source=/usr/lib/chatgpt/resources/codex,target=/usr/lib/chatgpt/resources/codex,readonly' "$launcher" >/dev/null
rg -F -- 'source=/usr/lib/chatgpt/resources/cua_node/bin/node_repl,target=/usr/lib/chatgpt/resources/cua_node/bin/node_repl,readonly' "$launcher" >/dev/null
rg -F -- 'source=/usr/lib/chatgpt/resources/cua_node/lib/node_modules,target=/usr/lib/chatgpt/resources/cua_node/lib/node_modules,readonly' "$launcher" >/dev/null
if rg -F -- 'source=/usr/lib/chatgpt/resources,target=/usr/lib/chatgpt/resources,readonly' "$launcher" >/dev/null; then
    echo "Launcher exposes the full host resources directory." >&2
    exit 1
fi
if rg -F -- '--security-opt apparmor=unconfined' "$launcher" >/dev/null; then
    echo "Launcher disables the default Docker AppArmor profile." >&2
    exit 1
fi
rg -F -- 'codex-wezterm-notify relay' "$launcher" >/dev/null
rg -F -- 'NOTIFICATION_VARIABLE = "codex_notification_request"' "$notification_relay" >/dev/null
rg -F -- 'SetUserVar=' "$notification_relay" >/dev/null
if rg -F -- 'tui.notification_method="osc9"' "$launcher" >/dev/null; then
    echo "Launcher still overrides the external completion notification relay." >&2
    exit 1
fi
rg -F -- 'CODEX_READ_ONLY_PATHS' "$launcher" >/dev/null
rg -F -- '--volume "${normalized_read_only_path}:${normalized_read_only_path}:ro"' "$launcher" >/dev/null
rg -F -- 'Refusing to expose the broad directory' "$launcher" >/dev/null
rg -F -- 'Refusing to expose the broad read-only path' "$launcher" >/dev/null

cmp -s "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/bin/codex-isolated" "$launcher" || {
    echo "Installed launcher differs from the repository source; run ./install.sh" >&2
    exit 1
}

cmp -s "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/scripts/codex-wezterm-notify" "$notification_relay" || {
    echo "Installed notification relay differs from the repository source; run ./install.sh" >&2
    exit 1
}

echo "Launcher, notification relay, image, runtime commands, and volumes are present."
echo "Run 'codex-isolated' from a non-sensitive test repository for interactive verification."
