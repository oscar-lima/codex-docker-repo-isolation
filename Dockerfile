FROM node:22-alpine

ARG USER_ID=1001
ARG GROUP_ID=1001
ARG CODEX_VERSION=0.151.0

RUN addgroup -g "${GROUP_ID}" codex \
    && adduser -D -u "${USER_ID}" -G codex codex \
    && apk add --no-cache bubblewrap uv python3 \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && install -d -o "${USER_ID}" -g "${GROUP_ID}" \
       /home/codex/.codex /home/codex/.cache

USER codex
ENV HOME=/home/codex
WORKDIR /workspace
ENTRYPOINT ["codex"]
