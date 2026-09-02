# Repository Agent Guide

## Purpose and scope

This repository builds and installs `codex-isolated`, a Docker-enforced
filesystem boundary for Codex. Preserve that boundary when making changes.
Treat the checked-out repository as the complete writable task scope unless the
user explicitly authorizes another path.

The isolated container is intentionally different from the host:

- The host has Docker and runs `./install.sh` and
  `scripts/verify-isolation.sh`.
- The isolated container has no Docker client and does not mount the host
  Docker socket.
- Never add or mount `/var/run/docker.sock`. Access to it would allow container
  processes to control the host and defeat the purpose of this repository.
- Do not propose privileged Docker-in-Docker as a routine solution. A nested
  daemon conflicts with the read-only root, dropped capabilities, and
  `no-new-privileges` design, and it would not rebuild the host's image.

## Change workflow

When adding a runtime dependency:

1. Add the Alpine package to `Dockerfile`.
2. Add a direct command or import smoke test to `install.sh`.
3. Add the corresponding non-interactive check to
   `scripts/verify-isolation.sh`.
4. Update `README.md` and `docs/setup-summary.md` so the documented image
   contents remain accurate.
5. Prefer Alpine packages over ad hoc global installs so the image remains
   reproducible.

Keep security assertions in the verification script, including the absence of
the Docker client and `/var/run/docker.sock`. Preserve the read-only root,
dropped capabilities, `no-new-privileges`, explicit mounts, and refusal to
expose `/` or the entire home directory.

## Verification

Inside an existing `codex-isolated` session, run the checks that do not require
Docker:

```bash
bash -n install.sh bin/codex-isolated scripts/*.sh
git diff --check
```

Do not attempt `docker build`, `docker run`, or `docker image inspect` from an
isolated session. `docker: not found` is expected there, not a missing image
dependency. State clearly that final image verification remains for the host:

```bash
./install.sh
./scripts/verify-isolation.sh
```

Do not claim the image build or container checks passed unless they were
actually run on a host with Docker.

## Lessons learned

- When the user asks to add or fix repository support, implement the scoped
  change instead of stopping after diagnosis.
- Determine whether commands are executing on the host or inside
  `codex-isolated` before selecting verification commands.
- A missing Docker executable inside this image is intentional. Adding only a
  Docker CLI is useless without a daemon; exposing the host daemon is a serious
  isolation regression.
- Python test availability does not imply Python packaging availability. Wheel
  checks using `python -m pip` or `python -m build --no-isolation` require pip,
  setuptools, build, and wheel to be installed explicitly.
- The `identify` executable comes from ImageMagick. Artifact-inspection tools
  such as ImageMagick and `unzip` should be declared and smoke-tested when
  agent workflows rely on them.
- If a command chain stops at an earlier `&&` operand, do not infer whether
  later commands are present. Test each relevant executable independently.
- A successful minimal PyQt offscreen smoke test does not prove an entire GUI
  test suite is stable. Treat a later `Fatal Python error: Aborted` as a
  separate failure and request or inspect the complete traceback and failing
  test rather than attributing it to unrelated packaging tools.
- Truncated pytest collection output is insufficient to decide whether the
  cause is a missing dependency, an import error, or a missing repository file.
  Expand the transcript or rerun the focused test with full output.

After completing a task, provide a one-line commit message suggestion that
describes the changes made.
