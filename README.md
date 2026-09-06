# Codex Docker Repository Isolation

This project packages a Docker-enforced filesystem boundary for Codex CLI. It
exposes the repository from which the launcher is run while keeping the rest of
the host filesystem unavailable, apart from explicit Codex state and runtime
mounts needed to preserve the normal CLI experience.

## Installed locations

- Launcher script (the executable users run):
  `/home/oscar/.local/bin/codex-isolated`
- Host notification relay: `/home/oscar/.local/bin/codex-wezterm-notify`
- Docker image: `codex-isolated`
- Shared Codex state: `/home/oscar/.codex`
- Source repository: `/home/oscar/repos_cloned/codex-docker-repo-isolation`

The launcher is a Bash script, despite being installed in a binary directory.
Its maintained source is [`bin/codex-isolated`](bin/codex-isolated).

## Install

Requirements:

- Docker Engine with permission to run containers.
- Codex CLI installed on the host.
- Python 3 on the host for the installed notification relay.
- `xdg-dbus-proxy` installed on the host (the Ubuntu package has the same name).
- The expected host paths described under "Explicit host mounts" below.

Run:

```bash
./install.sh
```

Run this command on the host, not from an existing `codex-isolated` session.
The isolated image intentionally has no Docker client or host Docker socket;
exposing the socket would let processes in the container control the host and
would defeat the isolation boundary.

This reads the installed host Codex version and builds `codex-isolated` with
that exact version, installs the launcher and notification relay under
`~/.local/bin`, and creates the persistent `uv` volumes. Running `./install.sh`
again after updating Codex on the host therefore rebuilds isolated Codex at the
same version. The installation verifies that the host and isolated versions
match and that the baseline shell utilities, `curl`, Git, ImageMagick, XML and
PDF utilities, Python test and package-build tooling, PyQt 5 (using Qt's
offscreen platform), Ruby, ShellCheck, SQLite, `yq`, ZIP utilities, `uv`, and
the configured hook commands are available in the new image before installing
the host commands. It also executes the image-native Node at
the path used by ChatGPT's MCP configuration and verifies that the mounted Node
REPL is executable, catching compatibility failures that would prevent MCP
servers such as `cua_repl` from starting.

After source changes, rebuild and run the complete verification on the Docker
host:

```bash
./install.sh
./scripts/verify-isolation.sh
```

Do not run these commands from an existing isolated session; the absence of the
Docker client there is intentional.

## Use

```bash
cd /path/to/repository
codex-isolated
```

Arguments are forwarded to Codex. The launcher refuses `/` and the user's home
directory because either would expose an excessively broad host tree.

Set `CODEX_READ_ONLY_PATHS` to a colon-separated list of additional absolute
host paths that Codex should be able to read but not modify. Each existing file
or directory is mounted at the same absolute path inside the container:

```bash
CODEX_READ_ONLY_PATHS=/path/to/docs:/path/to/reference-data codex-isolated
```

Empty list entries are ignored, duplicate paths are mounted once, and relative
or nonexistent paths cause the launcher to stop. The launcher also refuses `/`
and the user's entire home directory in this list. As with `PATH`, a colon is
the separator and therefore cannot be part of an entry.

The shared Codex configuration invokes `codex-wezterm-notify` by command name:

```toml
notify = ["codex-wezterm-notify"]

[tui]
notifications = []
```

The image installs that command in `/usr/local/bin`, so it resolves from every
mounted project without exposing the separate WezTerm configuration repository.
The installer also puts a host copy in `~/.local/bin` for non-isolated Codex.
Its maintained source is copied from the implementation in the separate,
read-only `wezterm_config` repository.
On turn completion, the relay writes an OSC 1337 user-variable request to the
originating terminal. The host WezTerm configuration converts that request into
a timed, clickable desktop notification named from the submitted task rather
than the checkout directory. The stable Codex turn identity lets WezTerm ignore
a replayed completion event, and the relay clears the request from the pane so
the next task's state update cannot replay it. Built-in TUI alerts are
disabled so approval or other lifecycle events do not produce an earlier
desktop notification. `WEZTERM_PANE` and `TMUX` are forwarded as terminal
identity markers; neither the WezTerm control socket nor a WezTerm host path is
mounted.

For explicit notification commands, the image also includes the real
`notify-send` client. When the standard per-user D-Bus socket is available, the
launcher starts `xdg-dbus-proxy` on the host and mounts only its private socket.
The proxy permits calls and broadcasts only on the
`org.freedesktop.Notifications` interface at its standard object path. The
original session bus is never mounted, and the container's default AppArmor
profile remains enabled. Native notifications are omitted automatically when
the desktop bus or proxy is unavailable, such as in SSH or CI sessions.

The launcher also forwards `WEZTERM_PANE` so the shared Codex lifecycle hooks
can update the pane's running, attention, and completed indicators. It forwards
`TMUX` as a marker so the helper uses tmux's OSC passthrough form when Codex is
launched from a tmux session.

## Security boundary

The container uses a read-only root filesystem, drops all capabilities, enables
`no-new-privileges`, and gives Codex writable temporary filesystems. Only the
current repository is mounted as project data.

Codex runs with `--sandbox danger-full-access` *inside* the container because a
second Bubblewrap user namespace cannot be created reliably inside this
hardened Docker sandbox. Docker is therefore the enforcement boundary.

This setup restricts host filesystem visibility; it is not a network sandbox.
Anything explicitly mounted into the container remains visible to Codex.
The Docker and WezTerm control sockets are deliberately not mounted, so an
isolated session cannot control host containers or issue unrestricted WezTerm
CLI commands.

## Explicit host mounts

- Current repository: read/write.
- `~/.codex`: read/write for authentication, configuration, sessions, plugins,
  skills, hooks, history, and status-line settings.
- `~/.config/agent-skill-manager`: read/write so the global `AGENTS.md` symlink
  resolves.
- `~/.cache/codex-runtimes`: read/write for Codex runtime/plugin artifacts.
- `/usr/lib/chatgpt/resources/codex`: read-only for integrations that locate
  Codex-relative resources.
- `/usr/lib/chatgpt/resources/cua_node/bin/node_repl`: read-only for the
  configured Node REPL MCP servers.
- `/usr/lib/chatgpt/resources/cua_node/lib/node_modules`: read-only for the Node
  REPL's packaged modules.
- Paths listed in `CODEX_READ_ONLY_PATHS`: read-only, at their original absolute
  locations.
- A per-launch `xdg-dbus-proxy` directory under `/run/user/<uid>`: read-only and
  containing only the filtered notification socket. The host session-bus socket
  and host machine ID are not exposed.

The `codex-isolated-uv-cache` and `codex-isolated-uv-data` Docker volumes retain
container-compatible Python MCP runtime data without sharing incompatible host
artifacts.

The image includes Bash, GNU coreutils and findutils, `curl`, Git, ImageMagick,
`jq`, `notify-send`, `xmllint`, Python 3, Black, NumPy, PyYAML, pip, setuptools, build,
wheel, pytest, PyQt 5, ripgrep, Ruby with YAML support, ShellCheck, SQLite, `unzip`,
`uv`, `yq`, ZIP, and Poppler PDF utilities, plus container-local copies of the
`wezterm-agent-state` and `codex-wezterm-notify` helpers. The notification relay
uses the existing terminal device for OSC transport, not a host socket or an
additional filesystem mount. PyQt 5 makes headless GUI checks possible with
`QT_QPA_PLATFORM=offscreen`. ShellCheck provides static analysis for shell
scripts, `yq` provides structured YAML queries and edits, `xmllint` supports
XML validation and queries, and Poppler supports PDF text and metadata inspection.
Black is installed as a pinned, isolated `uv` tool because it is not available
as an Alpine package in the base image's repositories.
The SQLite CLI supports direct, read-only
inspection of repository and Codex state databases. The Python packaging tools
support inspecting and building project wheels without modifying the read-only
image. Git is required by repository-aware hooks, while the helpers let the
shared hook and notification configuration update WezTerm without mounting the
host's full WezTerm configuration directory or control socket.

The image supplies Alpine's native Node executable at the path used by the
ChatGPT-provided MCP configuration. Only the compatible Node REPL executable,
its packaged modules, and the Codex resource executable are mounted from the
host. This fixes `cua_repl` startup after Codex upgrades while narrowing the
previous whole-resources mount and preserving the container's security options.

A container-local `code-review-graph` wrapper dispatches that hook command via
`uvx`, using the persistent container-compatible `uv` volumes.

See [`docs/setup-summary.md`](docs/setup-summary.md) for the complete setup and
verification record.
