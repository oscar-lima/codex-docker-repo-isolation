FROM node:22-alpine

ARG USER_ID=1001
ARG GROUP_ID=1001
ARG CODEX_VERSION

RUN addgroup -g "${GROUP_ID}" codex \
    && adduser -D -u "${USER_ID}" -G codex codex \
    && apk add --no-cache \
       bash \
       bubblewrap \
       coreutils \
       curl \
       findutils \
       git \
       imagemagick \
       jq \
       libnotify \
       py3-build \
       py3-numpy \
       py3-pip \
       py3-pytest \
       py3-qt5 \
       py3-setuptools \
       py3-wheel \
       py3-yaml \
       python3 \
       ripgrep \
       ruby \
       unzip \
       uv \
    && test -n "${CODEX_VERSION}" \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && install -d -o "${USER_ID}" -g "${GROUP_ID}" \
       /home/codex/.codex /home/codex/.cache \
       "/run/user/${USER_ID}" \
    && touch /etc/machine-id

COPY --chmod=0755 scripts/wezterm-agent-state /usr/local/bin/wezterm-agent-state
COPY --chmod=0755 scripts/code-review-graph /usr/local/bin/code-review-graph

USER codex
ENV HOME=/home/codex
WORKDIR /workspace
ENTRYPOINT ["codex"]
