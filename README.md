# Codex Docker Repository Isolation

This project packages a Docker-enforced filesystem boundary for Codex CLI. It
exposes the repository from which the launcher is run while keeping the rest of
the host filesystem unavailable, apart from explicit Codex state and runtime
mounts needed to preserve the normal CLI experience.

## Installed locations

- Launcher script (the executable users run):
  `/home/oscar/.local/bin/codex-isolated`
- Docker image: `codex-isolated`
- Shared Codex state: `/home/oscar/.codex`
- Source repository: `/home/oscar/repos_cloned/codex-docker-repo-isolation`

The launcher is a Bash script, despite being installed in a binary directory.
Its maintained source is [`bin/codex-isolated`](bin/codex-isolated).

## Install

Requirements:

- Docker Engine with permission to run containers.
- The expected host paths described under "Explicit host mounts" below.

Run:

```bash
./install.sh
```

This builds `codex-isolated`, installs the launcher under `~/.local/bin`, and
creates the persistent `uv` volumes. The installation verifies that Codex,
the baseline shell utilities, Git, Python tooling, PyQt 5 (using Qt's offscreen
platform), Ruby, `uv`, and both configured hook commands are available in the
new image before installing the launcher.

## Use

```bash
cd /path/to/repository
codex-isolated
```

Arguments are forwarded to Codex. The launcher refuses `/` and the user's home
directory because either would expose an excessively broad host tree.

When launched from WezTerm, the launcher forces Codex's native OSC 9
notifications on for every completed turn. WezTerm converts those terminal
sequences into Ubuntu desktop notifications. Terminal identity variables are
forwarded as well. User-provided `-c` arguments come after these defaults and
can override them.

For explicit notification commands, the image also includes the real
`notify-send` client. When the standard per-user D-Bus socket and host machine
ID are available, the launcher mounts those two endpoints and sets
`DBUS_SESSION_BUS_ADDRESS` and `XDG_RUNTIME_DIR`. Thus `notify-send hi` behaves
as it does in the native Codex CLI. The mounts are omitted automatically in
SSH, CI, or other sessions where the desktop notification bus is unavailable.
Ubuntu's default Docker AppArmor profile blocks all session-bus clients, so the
launcher also disables that profile when the bus is attached. The read-only
root, dropped capabilities, `no-new-privileges`, and explicit filesystem mounts
remain in force.

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

## Explicit host mounts

- Current repository: read/write.
- `~/.codex`: read/write for authentication, configuration, sessions, plugins,
  skills, hooks, history, and status-line settings.
- `~/.config/agent-skill-manager`: read/write so the global `AGENTS.md` symlink
  resolves.
- `~/.cache/codex-runtimes`: read/write for Codex runtime/plugin artifacts.
- `/usr/lib/chatgpt/resources`: read-only for configured runtime executables.
- `/run/user/<uid>/bus`: the current user's D-Bus session socket, when present,
  so commands such as `notify-send` can reach the desktop notification service.
- `/etc/machine-id`: read-only when the session bus is mounted, because D-Bus
  clients require the host machine identity.

Access to the session bus is broader than access to the notification service
alone: processes in the container can address other services registered on the
same user bus. Supporting the native `notify-send` command therefore makes this
an intentional exception to the otherwise repository-focused isolation model.

The `codex-isolated-uv-cache` and `codex-isolated-uv-data` Docker volumes retain
container-compatible Python MCP runtime data without sharing incompatible host
artifacts.

The image includes Bash, GNU coreutils and findutils, Git, `jq`, `notify-send`,
Python 3, PyYAML, pytest, PyQt 5, ripgrep, Ruby with YAML support, and a
container-local copy of the `wezterm-agent-state` helper. PyQt 5 makes headless
GUI checks possible with `QT_QPA_PLATFORM=offscreen`. Git is required by
repository-aware hooks, while the helper lets the shared hook configuration
update WezTerm status without mounting the host's full WezTerm configuration
directory.

A container-local `code-review-graph` wrapper dispatches that hook command via
`uvx`, using the persistent container-compatible `uv` volumes.

See [`docs/setup-summary.md`](docs/setup-summary.md) for the complete setup and
verification record.
