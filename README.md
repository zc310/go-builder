# go-builder

供多个项目复用的 Go 构建、测试与交叉编译工具镜像，不包含 OFD 源码或测试样本。

## 基础与工具

- **基础系统：`ubuntu:24.04`**，固定 Ubuntu 24.04 LTS 编译、测试基线，不跟随 `latest` 切换发行版。
- **Go：[`thongtech/go-legacy-win7`](https://github.com/thongtech/go-legacy-win7/releases) `1.27.4-1`**，基于官方 Go 1.27.4，增加旧 Windows 兼容补丁。amd64 / arm64 下载均校验固定 SHA256。
- **`GOTOOLCHAIN=local`**：不允许自动下载并切换到官方 Go，防止丢失兼容补丁。
- 原生 GCC / G++、pkg-config；Fyne / Gio 所需 X11、OpenGL、Wayland、Vulkan；GTK4、WebKitGTK 6.0 / 4.1、libffi。
- GCC MinGW-w64：Windows amd64 CGO；LLVM-MinGW [`20261117`](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261117)（LLVM 23.1.6）：Windows ARM64 CGO。
- Binaryen `133`，支持 OFD Makefile 使用的 `wasm-opt` 参数；nFPM `2.48.0`、RPM、NSIS、zip / unzip。
- LibreOffice、Tesseract 中英文 OCR、Poppler（包含 CJK CMap 数据）、MuPDF（包含 `mutool`）、XPS 工具。
- Noto CJK、文泉驿微米黑 / 正黑等系统字体，以及与 OFD CI 一致的 `hanzi-fonts` 文档字体包。
- Python 3、NumPy、Pillow、CairoSVG、PyMuPDF；Node.js `22.23.5` / npm、OpenJDK 21。Node.js 与 npm 从官方 `node:22.23.5-bookworm-slim` 镜像复制，不使用 Ubuntu 24.04 默认的 Node.js 18，以满足 Playwright 的 Node.js ≥20 要求；最终系统仍为 Ubuntu 24.04。
- amd64 安装官方 Google Chrome；arm64 安装 Playwright `1.65.1` 对应的 Chromium。统一入口为 `$CHROME_BIN`（`/usr/local/bin/chrome`）。

兼容 Go 与官方 Go 的常规构建用法一致，但并非完全相同，也不保证所有第三方库或 GUI 程序支持 Windows 7。CGO 动态库、WebView2、驱动和应用自身仍有独立的最低系统要求。

Ubuntu 的 `chromium-browser` 是 Snap 过渡包，不能直接照搬 Debian 的 Chromium 安装方式。这里不混用 Debian 软件源，也不在容器内运行 Snap。

这是功能完整、体积较大的**编译、测试镜像**，不作为生产运行镜像。默认以 root 启动，可通过 `--user` 使用宿主机 UID/GID。

### 中文与文档字体

除 APT 安装的 Noto、文泉驿字体外，还固定下载 [`zispace/hanzi-fonts` v1.0](https://github.com/zispace/hanzi-fonts/releases/tag/v1.0) 的三个字体包，并逐一校验 SHA256：

- `doc-foundertype.zip`：方正 GBK / 简体文档字体；
- `doc-zhongyi-etc.zip`：中易、长城、华文等文档字体；
- `latin-fonts.zip`：Arial、Helvetica、Times New Roman 等西文字体。

安装目录为 `/usr/local/share/fonts/hanzi-fonts`，保留字体包内的说明文件，统一修正非 root 读取权限并刷新 fontconfig 缓存。后续无需在 OFD CI 再下载这些包。

> **字体版权声明**：字体版权属于原作者（字体厂商），使用时（特别是商用）请注意版权和相关限制。
>
> 下载或打包字体不代表获得使用或再分发授权；公开分发镜像或用于生产前，应确认各字体的许可条款。

## 使用

镜像发布后，其他项目可以直接引用固定标签：

```dockerfile
FROM ghcr.io/zc310/go-builder:1.27.4-1 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/app ./cmd/app
```

本地构建、验证：

```sh
docker build --pull -t go-builder:local .
docker run --rm --user 10001:10001 -e HOME=/tmp go-builder:local go-builder-smoke
```

在工作目录中使用，避免生成 root 所有的产物：

```sh
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e GOPATH=/tmp/go -e GOCACHE=/tmp/go-build \
  -v "$PWD:/workspace" \
  ghcr.io/zc310/go-builder:1.27.4-1 \
  go build ./...
```

跨 Windows 平台编译含 CGO 的项目时显式选择编译器：

```sh
CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
  CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ go build ./...

CGO_ENABLED=1 GOOS=windows GOARCH=arm64 \
  CC=aarch64-w64-mingw32-clang CXX=aarch64-w64-mingw32-clang++ go build ./...
```

以上命令应在容器内执行。没有全局设置 `GOOS`、`GOARCH`、`CC`、`CGO_ENABLED`，原生 Linux 构建不会被强制切到 Windows。LLVM-MinGW 的 PATH 位于系统 PATH 之后，避免其 GCC 别名覆盖系统 GCC MinGW。

无头图形测试可设置 `EGL_PLATFORM=surfaceless`。浏览器不默认附加 `--no-sandbox`；冒烟测试仅对受控页面关闭沙箱，不应据此处理不可信内容。

## 发布到 GHCR

`.github/workflows/publish.yml` 在 amd64 / arm64 原生 runner 上分别构建，并以非 root 身份验证：

- 原生 Linux CGO、Windows amd64 / ARM64 CGO 编译；
- WASM 编译及完整优化参数；
- 图形库 pkg-config、Poppler CJK CMap、中文字体、三个额外字体包的注册与非 root 可读性、Python 模块、打包工具；
- 浏览器无头启动并读取页面。

两个架构均通过后才合并正式的多架构标签：

| 触发方式 | 镜像标签 |
| --- | --- |
| 推送 main / 在 main 手动运行 | `main`、`sha-<完整提交 SHA>` |
| 推送 `v1.27.4-1` | `1.27.4-1`、`latest`、`sha-<完整提交 SHA>` |
| 推送 `v1.27.4-1-r2` 等修订标签 | 对应修订版本、`latest`、`sha-<完整提交 SHA>` |
| Pull request | 只构建和测试，不登录或推送 GHCR |

使用 GitHub 自带的 `GITHUB_TOKEN`，无需另建推送密钥。首次发布后在 GitHub Packages 中确认包的可见性和其他仓库的读取权限。`build-<run>-<attempt>-<arch>` 是合并清单所需的临时标签，可按保留策略清理，勿在清单合并前删除。

Go 升级时，更新 Dockerfile 中的版本和两个架构的 SHA256，再使用对应版本标签发布。工具或依赖变化但 Go 不变时，使用 `-rN` 镜像修订号，不覆盖已有发布标签。

**固定标签不等于可重复构建**：Ubuntu 24.04 的基础镜像修订、APT 包和 amd64 Chrome 下载仍会更新；同一提交重建也可能不同。正式 CI / 发布需要严格锁定时，引用 `ghcr.io/zc310/go-builder@sha256:<清单摘要>`。有旧 glibc 兼容要求的 CGO 产物，应使用更旧的固定构建系统；不要直接把本镜像的动态链接产物放到旧 Ubuntu / Debian 上。
