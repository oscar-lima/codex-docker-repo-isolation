# Isolated Codex Setup Summary

Date: 5 September 2026

## Goal

Provide an OS-enforced boundary that prevents Codex from reading host files
outside the repository where it was launched, while keeping isolated Codex as
close as practical to the normal Codex CLI experience.

## Source and installed locations

The reproducible source files are stored in:

```text
/home/oscar/repos_cloned/codex-docker-repo-isolation
```

The launcher users execute is installed at:

```text
/home/oscar/.local/bin/codex-isolated
```

The host notification relay is installed at
`/home/oscar/.local/bin/codex-wezterm-notify`. Their maintained repository
sources are `bin/codex-isolated` and `scripts/codex-wezterm-notify`. The built
Docker image is named `codex-isolated`.

## Global Codex instruction

The global Codex instruction file is `~/.codex/AGENTS.md`. It is a symlink to:

```text
~/.config/agent-skill-manager/GLOBAL.md
```

A global filesystem-scope instruction was added there. It tells future Codex
sessions to treat their launch directory as the complete task scope and to stop
when a task requires another directory. This is behavioral protection; the
container described below supplies the enforceable host-filesystem boundary.

## Installed isolated CLI

- Docker image: `codex-isolated`
- Codex CLI version: detected from the host and verified after every image build
- Installed launcher: `/home/oscar/.local/bin/codex-isolated`
- Launcher source: `bin/codex-isolated` in this repository
- Dockerfile source: `Dockerfile` in this repository
- Base image: Alpine Linux with Node.js 22
- Added runtime packages: Bash, Bubblewrap, GNU coreutils and findutils, `curl`,
  Git, ImageMagick, `jq`, `notify-send`, `xmllint`, Poppler PDF utilities,
  Python 3, NumPy,
  PyYAML, pip, setuptools, build, wheel, pytest, PyQt 5, ripgrep, Ruby,
  ShellCheck, SQLite, `unzip`, `uv`/`uvx`, `yq`, and ZIP
- Installed Python tool: Black 26.5.1, in an isolated `uv` tool environment
- Included helper: `wezterm-agent-state`, for the shared Codex status hooks
- Included notification relay: `codex-wezterm-notify`, for the shared Codex
  external notification command
- Included wrapper: `code-review-graph`, dispatched through `uvx`

Image rebuilds and full verification are host-side operations:

```bash
./install.sh
./scripts/verify-isolation.sh
```

An existing `codex-isolated` session intentionally cannot run either Docker
workflow because it has no Docker client or Docker socket.

Launch it from the repository that should be exposed:

```bash
cd /path/to/repository
codex-isolated
```

The launcher refuses to expose `/` or the entire home directory.

Additional reference files or directories can be exposed read-only by setting
`CODEX_READ_ONLY_PATHS` to a colon-separated list of existing absolute paths:

```bash
CODEX_READ_ONLY_PATHS=/path/to/docs:/path/to/reference-data codex-isolated
```

Empty and duplicate entries are harmless. Relative paths, nonexistent paths,
`/`, and the entire home directory are rejected before Docker starts.

## Enforced container boundary

The launcher starts Docker with:

- A read-only container root filesystem.
- All Linux capabilities dropped.
- `no-new-privileges` enabled.
- Ephemeral writable `tmpfs` storage for `/tmp` and general cache files.
- Only the current repository mounted as project data.
- The repository mounted at its original absolute host path, preserving Codex
  project trust and project-specific configuration.
- No Docker socket, WezTerm control socket, parent workspace, sibling
  repository, SSH directory, or general home-directory mount.
- No Docker client in the image. Image installation and rebuilding remain
  host-side operations because container access to the host Docker socket would
  defeat the isolation boundary.
- `COLORTERM`, `TERM`, `TERM_PROGRAM`, and `TERM_PROGRAM_VERSION` are forwarded
  so terminal-aware behavior sees the same WezTerm environment as native Codex.
- The shared `notify = ["codex-wezterm-notify"]` configuration resolves the
  image-installed command from any mounted project. It relays completion data
  through an OSC 1337 user variable on the existing terminal connection.
- `tui.notifications = []` disables earlier built-in alerts, so desktop
  notifications are emitted only by the completion relay.
- No WezTerm control socket or configuration path is mounted. The host WezTerm
  process receives the OSC request and owns desktop notification and pane-focus
  operations.
- When the desktop session bus exists, a host-side `xdg-dbus-proxy` exposes a
  separate socket that permits only the standard desktop notification
  interface and object path. Only the proxy directory is mounted read-only;
  the real session bus and host machine ID remain hidden.
- The default Docker AppArmor profile remains enabled. Mount isolation, a
  read-only root, dropped capabilities, and `no-new-privileges` continue to
  enforce the filesystem boundary.
- `WEZTERM_PANE` and `TMUX` are forwarded as environment markers so lifecycle
  hook state updates reach the originating terminal pane.

Codex is invoked with its inner sandbox disabled because Bubblewrap cannot
create a second user namespace within the hardened Docker container. The
`danger-full-access` setting therefore applies only inside the already isolated
container. Docker remains the actual enforcement boundary.

## Shared Codex state and skills

To make normal and isolated Codex behave similarly, the launcher exposes these
specific host paths:

- `~/.codex` read/write: configuration, authentication, sessions, history,
  skills, plugins, hooks, and status-line settings.
- `~/.config/agent-skill-manager` read/write: target of the global
  `~/.codex/AGENTS.md` symlink.
- `~/.cache/codex-runtimes` read/write: installed Codex runtime/plugin cache.
- `/usr/lib/chatgpt/resources/codex` read-only: resource lookup for configured
  integrations.
- `/usr/lib/chatgpt/resources/cua_node/bin/node_repl` read-only: the configured
  Node REPL MCP executable.
- `/usr/lib/chatgpt/resources/cua_node/lib/node_modules` read-only: packaged
  modules used by the Node REPL.
- Any existing absolute paths named in `CODEX_READ_ONLY_PATHS`, mounted
  read-only at the same locations inside the container.
- A per-launch directory below `/run/user/<uid>` read-only when a desktop
  session bus is present: a filtered `xdg-dbus-proxy` socket for `notify-send`.

The image provides its Alpine-native Node executable at the resource path used
by MCP configuration. This keeps `cua_repl` from trying to launch the
incompatible glibc Node executable shipped for the Ubuntu host, while the
compatible Node REPL binary and modules remain narrowly mounted read-only.

`HOME` and `CODEX_HOME` inside the container point to `/home/oscar` and
`/home/oscar/.codex`, matching the host configuration and its absolute paths.
The notification configuration uses a PATH command rather than an absolute path
to the separate WezTerm repository, so it resolves to
`/usr/local/bin/codex-wezterm-notify` inside the image.

Because `~/.codex` is a writable bind mount, changes made by either normal or
isolated Codex to settings, skills, plugins, histories, or sessions are visible
to the other. This is an intentional exception to repository-only host access.

## Container-only runtime volumes

Two persistent Docker volumes keep architecture-specific `uvx` data separate
from the Ubuntu host while allowing the read-only container to run configured
Python MCP servers:

- `codex-isolated-uv-cache`
- `codex-isolated-uv-data`

The second volume contains a musl-compatible managed Python runtime. This fixed
the `code-review-graph` MCP startup failure caused by `uvx` being unable to
write under `~/.local/share/uv`.

The earlier `codex-isolated-home` volume still exists but is no longer used by
the launcher because the host `~/.codex` directory is now shared directly.

## Host verification checklist

After rebuilding, `./scripts/verify-isolation.sh` checks the following behavior:

- The selected repository is readable and writable.
- Host `/home/oscar` is not generally visible inside the container.
- The container root filesystem cannot be written.
- The shared `~/.codex` configuration is readable and writable.
- Global instructions resolve through their symlink.
- Skills and plugin directories are visible.
- The repository retains its original trusted absolute path.
- The full configured status line appears, including model/reasoning, five-hour
  allowance, weekly allowance, project, approval mode, and context information.
- The Bubblewrap warning no longer appears.
- Turn completion notifications use the image-installed
  `codex-wezterm-notify` OSC 1337 relay, allowing the host WezTerm configuration
  to identify the originating pane without a socket mount. Notification titles
  are derived from the submitted task, and stable turn IDs allow the host to
  suppress replayed completion events at the start of the next task.
- `notify-send` is installed. Host verification must confirm that it reaches
  the Ubuntu notification service through the filtered proxy without exposing
  the user's D-Bus session socket.
- All configured MCP servers initialize without startup warnings after the
  `uvx` runtime volumes were added.
- Python tests run with the image-provided pytest, and a PyQt 5 widget can be
  created and processed with Qt's offscreen platform plugin.
- The `mobipick_gpt` Git worktree remained clean throughout setup.

## Important limitation

This protection applies only to sessions started with `codex-isolated`.
Running the ordinary `codex` command or using a separately managed desktop
session does not use this Docker boundary.

The setup limits host filesystem access, but it does not disable network access.
