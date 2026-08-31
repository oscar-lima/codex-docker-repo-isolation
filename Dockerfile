FROM node:22-alpine

ARG USER_ID=1001
ARG GROUP_ID=1001
ARG CODEX_VERSION=0.151.0

RUN addgroup -g "${GROUP_ID}" codex \
    && adduser -D -u "${USER_ID}" -G codex codex \
    && apk add --no-cache bubblewrap coreutils git py3-pytest python3 uv \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && install -d -o "${USER_ID}" -g "${GROUP_ID}" \
       /home/codex/.codex /home/codex/.cache

COPY --chmod=0755 scripts/wezterm-agent-state /usr/local/bin/wezterm-agent-state
COPY --chmod=0755 scripts/code-review-graph /usr/local/bin/code-review-graph

USER codex
ENV HOME=/home/codex
WORKDIR /workspace
ENTRYPOINT ["codex"]
