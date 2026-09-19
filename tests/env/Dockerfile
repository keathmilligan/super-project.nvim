# Isolated Neovim for interactive and headless plugin tests.
# Build from the repository root:
#   docker build -f tests/env/Dockerfile -t super-project-test .

FROM ubuntu:24.04

ARG NVIM_VERSION=v0.12.5
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SUPER_PROJECT_ROOT=/plugin \
    NVIM_APPNAME=super-project-test

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        make \
        tar \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN nvim_arch="$TARGETARCH" \
    && case "$TARGETARCH" in \
         amd64) nvim_arch=x86_64 ;; \
         arm64) nvim_arch=arm64 ;; \
         *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${nvim_arch}.tar.gz" \
         | tar -xz -C /opt \
    && ln -s "/opt/nvim-linux-${nvim_arch}/bin/nvim" /usr/local/bin/nvim \
    && nvim --version | head -n 1

COPY tests/env/nvim /opt/sp-nvim
COPY tests/env/entrypoint.sh /usr/local/bin/sp-entrypoint
RUN chmod +x /usr/local/bin/sp-entrypoint \
    && mkdir -p /workspace /tmp/nvim-home \
    && chmod 1777 /workspace /tmp/nvim-home

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sp-entrypoint"]
CMD ["nvim"]
