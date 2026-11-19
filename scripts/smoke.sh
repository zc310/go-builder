#!/bin/sh
# 验证工具链、原生 / Windows CGO、WASM、Python 和无头浏览器。
set -eu

. /etc/os-release
test "$ID" = ubuntu
test "$VERSION_ID" = 24.04
test "$(go env GOTOOLCHAIN)" = local
test "$(go env GOROOT)" = /usr/local/go
go version
wasm-opt --enable-bulk-memory-opt --disable-strings --disable-compact-imports --version
nfpm --version
node --version
node -e 'if (Number(process.versions.node.split(".")[0]) < 20) process.exit(1)'
npm --version
java -version
makensis -VERSION
rpm --version
libreoffice --headless --version
tesseract --version
mutool -v
python3 -c 'import numpy, PIL, cairosvg, fitz'

pkg-config --exists gl egl glesv2 x11 xrandr xinerama xcursor xi xfixes \
    xkbcommon xkbcommon-x11 wayland-client gtk4 webkitgtk-6.0 webkit2gtk-4.1 libffi vulkan
test -n "$(fc-list :lang=zh family)"
python3 - <<'PY'
from pathlib import Path
import subprocess

registered = set(subprocess.check_output(
    ["fc-list", "--format=%{file}\n"], text=True,
).splitlines())
base = Path("/usr/local/share/fonts/hanzi-fonts")
for bundle in ("doc-foundertype", "doc-zhongyi-etc", "latin-fonts"):
    fonts = [path for path in (base / bundle).rglob("*")
             if path.suffix.lower() in (".ttf", ".ttc", ".otf")]
    assert fonts, f"字体包为空：{bundle}"
    assert any(str(path) in registered for path in fonts), f"字体未注册：{bundle}"
    for path in fonts:
        with path.open("rb") as font:
            assert font.read(4), f"字体文件为空：{path}"
PY

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
export GOCACHE="$temp_dir/go-cache"
export GOPATH="$temp_dir/go"
export GOENV=off
export GO111MODULE=off
cd "$temp_dir"

cat > cgo.go <<'GO'
package main

/*
static int answer(void) { return 42; }
*/
import "C"

func main() {
	if C.answer() != 42 {
		panic("CGO 调用失败")
	}
}
GO

CGO_ENABLED=1 go build -o native cgo.go
./native
CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
    CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ \
    go build -o windows-amd64.exe cgo.go
CGO_ENABLED=1 GOOS=windows GOARCH=arm64 \
    CC=aarch64-w64-mingw32-clang CXX=aarch64-w64-mingw32-clang++ \
    go build -o windows-arm64.exe cgo.go
file windows-amd64.exe | grep -q 'x86-64'
file windows-arm64.exe | grep -q 'Aarch64'

cat > main.go <<'GO'
package main

func main() {}
GO

CGO_ENABLED=0 GOOS=js GOARCH=wasm go build -o main.wasm main.go
wasm-opt --enable-bulk-memory --enable-bulk-memory-opt \
    --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals \
    --enable-simd --enable-reference-types --disable-gc --disable-strings \
    --disable-memory64 --disable-compact-imports -Oz --strip-producers \
    main.wasm -o optimized.wasm
test -s optimized.wasm

# 仅本次受控冒烟测试关闭沙箱，不向下游默认注入 --no-sandbox。
timeout 60 "$CHROME_BIN" --headless --no-sandbox --disable-gpu --disable-dev-shm-usage \
    --user-data-dir="$temp_dir/browser" --dump-dom \
    'data:text/html,<p>go-builder-browser-ok</p>' > browser.html
grep -q '<p>go-builder-browser-ok</p>' browser.html
echo 'go-builder 冒烟测试通过'
