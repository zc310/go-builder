# syntax=docker/dockerfile:1

# Ubuntu 24.04 自带 Node.js 18；从官方镜像复制 Node.js 22 以满足 Playwright 要求。
FROM node:22.23.5-bookworm-slim AS node

FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

ENV LANG=C.UTF-8 \
    TZ=Etc/UTC \
    GOROOT=/usr/local/go \
    GOPATH=/go \
    GOTOOLCHAIN=local \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers \
    CHROME_BIN=/usr/local/bin/chrome

# 不持久化 DEBIAN_FRONTEND，避免影响使用该镜像的交互式容器。
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    wget \
    build-essential \
    pkg-config \
    unzip \
    zip \
    xz-utils \
    file \
    gnupg \
    ripgrep \
    # Fyne / Gio：X11、OpenGL、Wayland、Vulkan
    libgl1-mesa-dev \
    libgles2-mesa-dev \
    libegl1-mesa-dev \
    xorg-dev \
    libx11-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxi-dev \
    libxfixes-dev \
    libxkbcommon-dev \
    libwayland-dev \
    libxkbcommon-x11-dev \
    libxxf86vm-dev \
    libx11-xcb-dev \
    libvulkan-dev \
    mesa-vulkan-drivers \
    vulkan-tools \
    # Wails / GTK
    libgtk-4-dev \
    libwebkitgtk-6.0-dev \
    libwebkit2gtk-4.1-dev \
    libffi-dev \
    # 系统中英文字体；额外的文档字体包在下一层安装
    fontconfig \
    fonts-dejavu-core \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-core \
    fonts-wqy-microhei \
    fonts-wqy-zenhei \
    # Office、OCR、PDF、XPS
    libreoffice-calc \
    libreoffice-core \
    libreoffice-impress \
    libreoffice-writer \
    tzdata \
    tesseract-ocr \
    tesseract-ocr-chi-sim \
    tesseract-ocr-chi-sim-vert \
    tesseract-ocr-chi-tra \
    tesseract-ocr-chi-tra-vert \
    libgxps-utils \
    poppler-utils \
    poppler-data \
    mupdf \
    mupdf-tools \
    # Python、Java；Node.js 和 npm 从官方镜像单独复制
    python3 \
    python3-numpy \
    python3-pil \
    python3-cairosvg \
    cairosvg \
    python3-fitz \
    openjdk-21-jdk-headless \
    # Windows CGO 与 Linux / Windows 打包
    gcc-mingw-w64-x86-64 \
    g++-mingw-w64-x86-64 \
    nsis \
    rpm \
    && fc-cache -f \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm/ /usr/local/lib/node_modules/npm/
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ln -s node /usr/local/bin/nodejs \
    && node --version \
    && npm --version

# 常用中文及西文文档字体。
# 字体版权属于原作者（字体厂商），使用时（特别是商用）请注意版权和相关限制。
ARG HANZI_FONTS_VERSION=1.0
ARG HANZI_FONTS_SHA256_FOUNDER=36910a520b889bd774f2c1e7afaa27cb463a67cd583e8946ba97ee48e02c5701
ARG HANZI_FONTS_SHA256_ZHONGYI=188134807e878cd9934440c2f75969ddd6ee8fdd9b53cad90c8a4e797c657988
ARG HANZI_FONTS_SHA256_LATIN=0aa2f73c4c3ef28ceaf1639c2f564848a9e584b09b3d092d670f26edbd4e0c74
RUN set -eu; \
    fonts_dir=/usr/local/share/fonts/hanzi-fonts; \
    download_dir="$(mktemp -d)"; \
    base_url="https://github.com/zispace/hanzi-fonts/releases/download/v${HANZI_FONTS_VERSION}"; \
    for archive in doc-foundertype.zip doc-zhongyi-etc.zip latin-fonts.zip; do \
        case "$archive" in \
            doc-foundertype.zip) checksum="$HANZI_FONTS_SHA256_FOUNDER" ;; \
            doc-zhongyi-etc.zip) checksum="$HANZI_FONTS_SHA256_ZHONGYI" ;; \
            latin-fonts.zip) checksum="$HANZI_FONTS_SHA256_LATIN" ;; \
        esac; \
        curl -fLsS --retry 3 --retry-all-errors --connect-timeout 20 --max-time 600 \
            "$base_url/$archive" -o "$download_dir/$archive"; \
        echo "$checksum  $download_dir/$archive" | sha256sum -c -; \
        mkdir -p "$fonts_dir/${archive%.zip}"; \
        unzip -q "$download_dir/$archive" -d "$fonts_dir/${archive%.zip}"; \
    done; \
    rm -rf "$download_dir"; \
    # 上游压缩包可能含 0700 目录，确保非 root 用户也能扫描、读取字体。 \
    chmod -R a+rX "$fonts_dir"; \
    fc-cache -f "$fonts_dir"

# 与 OFD Windows 发布使用同一兼容工具链；哈希来自上游 v1.27.4-1。
# 升级版本时必须同时更新两个架构的 SHA256。
ARG GO_LEGACY_VERSION=1.27.4-1
ARG GO_LEGACY_SHA256_AMD64=ac19ede77803f1b7e1de6bd43fa01882c6b16e8efd06a78416392a08bca99bc2
ARG GO_LEGACY_SHA256_ARM64=92ec3691d854b73b2a0e6d70821c9c7de0303571ef4591fee3cfcd321db25a4c
# 按发布包中的固定目录复制工具链，不依赖前导 ./ 的层数。
RUN set -eu; \
    case "$TARGETARCH" in \
        amd64) checksum="$GO_LEGACY_SHA256_AMD64" ;; \
        arm64) checksum="$GO_LEGACY_SHA256_ARM64" ;; \
        *) echo "不支持的架构：$TARGETARCH" >&2; exit 1 ;; \
    esac; \
    archive="go-legacy-win7-${GO_LEGACY_VERSION}.linux_${TARGETARCH}.tar.gz"; \
    download_dir="$(mktemp -d)"; \
    curl -fLsS --retry 3 --connect-timeout 20 --max-time 600 \
        "https://github.com/thongtech/go-legacy-win7/releases/download/v${GO_LEGACY_VERSION}/${archive}" \
        -o "$download_dir/$archive"; \
    echo "$checksum  $download_dir/$archive" | sha256sum -c -; \
    tar -xzf "$download_dir/$archive" -C "$download_dir"; \
    mkdir -p "$GOROOT"; \
    cp -a "$download_dir/go-legacy-win7/." "$GOROOT/"; \
    rm -rf "$download_dir"; \
    "$GOROOT/bin/go" version

# LLVM-MinGW 用于 Windows ARM64；Windows amd64 优先使用系统 GCC MinGW。
ARG LLVM_MINGW_VERSION=20261117
ARG LLVM_MINGW_SHA256_AMD64=e7a15a49a2ea95e9f3d8a9d0cfabe5052a4b10fb4777cc54de5a8c27b64bb701
ARG LLVM_MINGW_SHA256_ARM64=6d9442ead9ace3b3e4c3389bfef69f93f873305e0705e6cc60978ac895320872
RUN set -eu; \
    case "$TARGETARCH" in \
        amd64) host=x86_64; checksum="$LLVM_MINGW_SHA256_AMD64" ;; \
        arm64) host=aarch64; checksum="$LLVM_MINGW_SHA256_ARM64" ;; \
        *) exit 1 ;; \
    esac; \
    archive="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-${host}.tar.xz"; \
    download_dir="$(mktemp -d)"; \
    curl -fLsS --retry 3 --connect-timeout 20 --max-time 600 \
        "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${archive}" \
        -o "$download_dir/$archive"; \
    echo "$checksum  $download_dir/$archive" | sha256sum -c -; \
    mkdir -p /opt/llvm-mingw; \
    tar -xJf "$download_dir/$archive" -C /opt/llvm-mingw --strip-components=1; \
    rm -rf "$download_dir"

ENV PATH="/usr/local/go/bin:/go/bin:${PATH}:/opt/llvm-mingw/bin"

# 软件源里的 Binaryen 可能不支持下游 Makefile 使用的全部 wasm-opt 参数。
ARG BINARYEN_VERSION=133
ARG BINARYEN_SHA256_AMD64=2dc9c7813f5375db93d96ead4b78222fcc3e2677bbb832297af4797782a37489
ARG BINARYEN_SHA256_ARM64=89c07ea56faf38d0fbecf36ca8ec0721756716185f265b568e133d427f299bf8
RUN set -eu; \
    case "$TARGETARCH" in \
        amd64) host=x86_64; checksum="$BINARYEN_SHA256_AMD64" ;; \
        arm64) host=aarch64; checksum="$BINARYEN_SHA256_ARM64" ;; \
        *) exit 1 ;; \
    esac; \
    archive="binaryen-version_${BINARYEN_VERSION}-${host}-linux.tar.gz"; \
    download_dir="$(mktemp -d)"; \
    curl -fLsS --retry 3 --connect-timeout 20 --max-time 600 \
        "https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/${archive}" \
        -o "$download_dir/$archive"; \
    echo "$checksum  $download_dir/$archive" | sha256sum -c -; \
    tar -xzf "$download_dir/$archive" -C "$download_dir"; \
    install -m755 "$download_dir/binaryen-version_${BINARYEN_VERSION}/bin/wasm-opt" /usr/local/bin/wasm-opt; \
    wasm-opt --enable-bulk-memory-opt --disable-strings --disable-compact-imports --version; \
    rm -rf "$download_dir"

ARG NFPM_VERSION=2.48.0
RUN GOBIN=/usr/local/bin go install "github.com/goreleaser/nfpm/v2/cmd/nfpm@v${NFPM_VERSION}" \
    && go clean -modcache -cache

# Ubuntu 的 chromium-browser 是 Snap 过渡包，不适合普通 Docker 容器。
# amd64 使用官方 Chrome deb；arm64 使用 Playwright 固定版本的原生 Chromium。
ARG PLAYWRIGHT_VERSION=1.65.1
RUN set -eu; \
    case "$TARGETARCH" in \
        amd64) \
            curl -fLsS --retry 3 --connect-timeout 20 --max-time 600 \
                https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
                -o /tmp/chrome.deb; \
            apt-get update; \
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/chrome.deb; \
            ln -s /usr/bin/google-chrome-stable /usr/local/bin/chrome; \
            rm -f /tmp/chrome.deb ;; \
        arm64) \
            npm install --prefix /opt/playwright --save-exact --omit=dev --ignore-scripts \
                --no-audit --no-fund "playwright@${PLAYWRIGHT_VERSION}"; \
            DEBIAN_FRONTEND=noninteractive /opt/playwright/node_modules/.bin/playwright \
                install --with-deps --no-shell chromium; \
            browser="$(node -e "process.stdout.write(require('/opt/playwright/node_modules/playwright').chromium.executablePath())")"; \
            ln -s "$browser" /usr/local/bin/chromium; \
            ln -s /usr/local/bin/chromium /usr/local/bin/chrome; \
            chmod -R a+rX /opt/playwright /opt/playwright-browsers; \
            npm cache clean --force ;; \
        *) exit 1 ;; \
    esac; \
    fc-cache -f; \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 scripts/smoke.sh /usr/local/bin/go-builder-smoke

WORKDIR /workspace
CMD ["bash"]
