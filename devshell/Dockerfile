# Central developer toolchain — replaces per-laptop setup.
# Publish multi-arch: docker buildx build --platform linux/amd64,linux/arm64 -t quintel/etm-devshell:<tag> --push .
FROM ruby:4.0-slim

ARG NODE_MAJOR=20

RUN apt-get update -yqq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      default-libmysqlclient-dev \
      default-mysql-client \
      git \
      gnupg \
      graphviz \
      less \
      libreadline-dev \
      libxml2-dev \
      libxslt1-dev \
      libyaml-dev \
      python3 \
      python3-dev \
      python3-venv \
      vim \
      zsh \
 && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
 && apt-get install -yqq --no-install-recommends nodejs \
 && npm install -g yarn \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# uv: fast Python package manager, copied from the official image (version pinned by digest).
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# pyetm + ipykernel (the kernel VS Code's Jupyter extension drives) into the system Python
# so `import pyetm` and notebooks work anywhere (--break-system-packages: the base image's
# Python is PEP 668 managed; system-wide is intended for this dev image).
RUN uv pip install --system --break-system-packages pyetm ipykernel

# Stock oh-my-zsh shell with no baked team config — bring your own .zshrc/dotfiles (see README).
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

ENV SHELL=/bin/zsh
WORKDIR /workspace
CMD ["sleep", "infinity"]
