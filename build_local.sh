#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# DevEco Studio Linux Local Build Script (openSUSE / Distro-Agnostic)
# ─────────────────────────────────────────────────────────────────────────────

PKGVER="26.0.0.621"
IDEAVER="2026.1.3"
IDEA_URL="https://download.jetbrains.com/idea/idea-${IDEAVER}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/dist"
PKG_DIR="${OUTPUT_DIR}/devecostudio"

echo "==> [1/6] 检查前置依赖与源文件..."
for cmd in 7z jq python3 curl tar strip unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "错误: 缺少命令 $cmd，请先使用 zypper install 安装。" >&2
    exit 1
  fi
done

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

MAC_ZIP="${SCRIPT_DIR}/devecostudio-mac.zip"
CLI_ZIP="${SCRIPT_DIR}/commandline-tools-linux-x64.zip"
IDEA_TAR="${BUILD_DIR}/idea-${IDEAVER}.tar.gz"

# 如果参数传入了 URL，则自动下载
if [[ $# -ge 2 ]]; then
  echo "==> 检测到传入了下载链接，开始并发下载..."
  curl -fL -o "${MAC_ZIP}" "$1" &
  curl -fL -o "${CLI_ZIP}" "$2" &
  wait
fi

if [[ ! -f "${MAC_ZIP}" ]]; then
  echo "错误: 未找到 ${MAC_ZIP}，请将 Mac 版 zip 重命名为此文件名并放在当前目录。" >&2
  exit 1
fi

if [[ ! -f "${CLI_ZIP}" ]]; then
  echo "错误: 未找到 ${CLI_ZIP}，请将 Commandline Tools zip 重命名为此文件名并放在当前目录。" >&2
  exit 1
fi

# 下载 JetBrains IDEA tarball (如果不存在)
if [[ ! -f "${IDEA_TAR}" ]]; then
  echo "==> 下载 IntelliJ IDEA Linux 运行时 (${IDEAVER})..."
  curl -fL -o "${IDEA_TAR}" "${IDEA_URL}"
fi

echo "==> [2/6] 解压源码与归档..."
# 1. 解压 Mac zip 中的 dmg
echo "  -> 解压 Mac ZIP..."
mkdir -p "${BUILD_DIR}/mac_zip"
unzip -qo "${MAC_ZIP}" -d "${BUILD_DIR}/mac_zip"

DMG_FILE=$(find "${BUILD_DIR}/mac_zip" -name '*.dmg' -type f | head -1)
if [[ -z "${DMG_FILE}" ]]; then
  echo "错误: 未在 devecostudio-mac.zip 中找到 .dmg 文件。" >&2
  exit 1
fi

echo "  -> 提取 Mac DMG (排除冗余目录)..."
mkdir -p "${BUILD_DIR}/mac_dmg"
7z x -y -o"${BUILD_DIR}/mac_dmg" "${DMG_FILE}" \
  "DevEco-Studio/DevEco-Studio.app/Contents" \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/sdk/default' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/jbr' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/emulator' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/dumpParser' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/llvm' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/profiler' \
  -x!'DevEco-Studio/DevEco-Studio.app/Contents/tools/node' \
  >/dev/null 2>&1 || true

MAC_CONTENTS="${BUILD_DIR}/mac_dmg/DevEco-Studio/DevEco-Studio.app/Contents"

# 2. 解压 CLI zip (使用 unzip 保留符号链接且无报错中断)
echo "  -> 解压 Linux Command Line Tools..."
mkdir -p "${BUILD_DIR}/cli"
unzip -qo "${CLI_ZIP}" -d "${BUILD_DIR}/cli"
CLI_ROOT=$(find "${BUILD_DIR}/cli" -type d -name "command-line-tools" | head -1)

# 3. 解压 IDEA Linux
echo "  -> 解压 IntelliJ IDEA Linux..."
mkdir -p "${BUILD_DIR}/idea"
tar -xzf "${IDEA_TAR}" -C "${BUILD_DIR}/idea"
IDEA_ROOT=$(find "${BUILD_DIR}/idea" -mindepth 1 -maxdepth 1 -type d -name 'idea-IU-*' | head -1)

echo "==> [3/6] 组装 Linux 原生 DevEco Studio 目录..."
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}"/{bin,jbr,lib,plugins,modules,tools,license,sdk}

# 复制平台无关文件
cp -a "${MAC_CONTENTS}/lib/"*.jar "${PKG_DIR}/lib/"
cp -a "${MAC_CONTENTS}/plugins/"* "${PKG_DIR}/plugins/"
rm -rf "${PKG_DIR}/plugins/ohos-trace"
cp -a "${MAC_CONTENTS}/modules/"* "${PKG_DIR}/modules/"

# 复制 Linux CLI 工具
cp -a "${CLI_ROOT}/hvigor/" "${PKG_DIR}/tools/hvigor"
cp -a "${CLI_ROOT}/ohpm/" "${PKG_DIR}/tools/ohpm"
cp -a "${CLI_ROOT}/hstack/" "${PKG_DIR}/tools/hstack"
cp -a "${CLI_ROOT}/codelinter/" "${PKG_DIR}/tools/codelinter"
cp -a "${CLI_ROOT}/emulator/" "${PKG_DIR}/tools/emulator"
ln -sf Emulator "${PKG_DIR}/tools/emulator/Emulator.exe"
cp -a "${CLI_ROOT}/tool/node/" "${PKG_DIR}/tools/node/"
(cd "${PKG_DIR}/tools/node" && ln -sf bin/* .)
ln -sfn lib/node_modules "${PKG_DIR}/tools/node/node_modules"
mkdir -p "${PKG_DIR}/tools/lib"
ln -sfn ../node/lib/node_modules "${PKG_DIR}/tools/lib/node_modules"

# UxTestService、license、build.txt、图标、properties
mkdir -p "${PKG_DIR}/tools/UxTestService"
cp -a "${MAC_CONTENTS}/tools/UxTestService/"* "${PKG_DIR}/tools/UxTestService/"
cp -a "${MAC_CONTENTS}/license/"* "${PKG_DIR}/license/"
cp -a "${MAC_CONTENTS}/Resources/build.txt" "${PKG_DIR}/"
cp -a "${MAC_CONTENTS}/bin/devecostudio.svg" "${PKG_DIR}/bin/"
cp -a "${MAC_CONTENTS}/bin/idea.properties" "${PKG_DIR}/bin/"

echo "==> [4/6] 替换 IDEA Linux 原生运行组件..."
# JBR
cp -a "${IDEA_ROOT}/jbr/"* "${PKG_DIR}/jbr/"
# launcher & fsnotifier
cp -a "${IDEA_ROOT}/bin/idea" "${PKG_DIR}/bin/devecostudio"
chmod +x "${PKG_DIR}/bin/devecostudio"
cp -a "${IDEA_ROOT}/bin/fsnotifier" "${PKG_DIR}/bin/"
# native libs
mkdir -p "${PKG_DIR}/lib/native/linux-x86_64" "${PKG_DIR}/lib/pty4j/linux" "${PKG_DIR}/lib/jna/amd64" "${PKG_DIR}/lib/skiko-awt-runtime-all"
cp -a "${IDEA_ROOT}/lib/native/linux-x86_64/"* "${PKG_DIR}/lib/native/linux-x86_64/"
cp -a "${IDEA_ROOT}/lib/pty4j/linux/"* "${PKG_DIR}/lib/pty4j/linux/"
cp -a "${IDEA_ROOT}/lib/jna/amd64/libjnidispatch.so" "${PKG_DIR}/lib/jna/amd64/"
cp -a "${IDEA_ROOT}/lib/skiko-awt-runtime-all/"* "${PKG_DIR}/lib/skiko-awt-runtime-all/"

# Linux SDK & CLI wrappers
cp -a "${CLI_ROOT}/sdk/"* "${PKG_DIR}/sdk/"
mkdir -p "${PKG_DIR}/tools/bin"
cp -a "${CLI_ROOT}/bin/"* "${PKG_DIR}/tools/bin/"
sed -i 's|cd "$(dirname "$0")"|cd "$(dirname "$(readlink -f "$0")")"|' "${PKG_DIR}/tools/bin/"*
sed -i 's|\$all_tool_dir/tool/node|\$all_tool_dir/node|g; s|\$all_tool_dir/sdk|\$all_tool_dir/../sdk|g' "${PKG_DIR}/tools/bin/"*
chmod +x "${PKG_DIR}/tools/bin/"*
sed -i 's|\$ROOT_PATH/tool/node|\$ROOT_PATH/node|; s|\$ROOT_PATH/sdk|\$ROOT_PATH/../sdk|' "${PKG_DIR}/tools/codelinter/bin/codelinter"

# 模拟器自动同意补丁
cat > "${BUILD_DIR}/emulator-patch.sh" << 'PATCHEOF'
mkdir -p "$HOME/Library/Huawei"
ln -sfn "$HOME/.Huawei/Sdk" "$HOME/Library/Huawei/Sdk"
_emu_config="$HOME/Library/Caches/Huawei/Emulator26.0/.emu_config"
if [[ ! -f "$_emu_config" ]]; then
    echo "Emulator software agreements not yet accepted. Displaying and accepting them now..."
    "$all_tool_dir/emulator/Emulator" -license accept
    echo ""
    echo "Re-run your command to proceed."
    echo "To opt out: truncate $_emu_config."
    exit 0
fi
PATCHEOF
sed -i '/"$all_tool_dir\/emulator\/Emulator" "\$@"/r '"${BUILD_DIR}/emulator-patch.sh" "${PKG_DIR}/tools/bin/Emulator"

# JBR sign path fix
mkdir -p "${PKG_DIR}/jbr/Contents/Home"
ln -sf ../../bin "${PKG_DIR}/jbr/Contents/Home/bin"

# 转换 vmoptions
sed \
  -e 's/-Dsun.java2d.metal=true/-Dsun.java2d.opengl=true/' \
  -e '/^-Djava.security.manager/d' \
  -e '/^-Dwsl/d' \
  "${MAC_CONTENTS}/bin/devecostudio.vmoptions" > "${PKG_DIR}/bin/devecostudio64-lin.vmoptions"
cat >> "${PKG_DIR}/bin/devecostudio64-lin.vmoptions" << 'VMEOF'
-Dawt.lock.fair=true
-Dsun.tools.attach.tmp.only=true
-Dglfw.im.module=fcitx
VMEOF

# 写入启动脚本 wrapper
cat > "${PKG_DIR}/bin/devecostudio.sh" << 'SHEOF'
#!/bin/bash
export _JAVA_AWT_WM_NONREPARENTING=1
export QT_QPA_PLATFORM=xcb

_hidpi_scale=""
case "${DEVECO_UI_SCALE:-auto}" in
  off) ;;
  auto)
    _cs=""
    command -v wlr-randr >/dev/null 2>&1 && \
      _cs=$(wlr-randr 2>/dev/null | awk '/Scale:/{print $2; exit}')
    if [[ "$_cs" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      _hidpi_scale=$(LC_ALL=C awk -v s="$_cs" 'BEGIN{ q=int(s*4+0.5)/4; if (q<1.0) q=1.0; printf "%.2f", q }')
    fi
    ;;
  *)
    if [[ "$DEVECO_UI_SCALE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      _hidpi_scale="$DEVECO_UI_SCALE"
    fi
    ;;
esac
if [[ -n "$_hidpi_scale" ]]; then
  _cfg="${XDG_CONFIG_HOME:-$HOME/.config}/Huawei/DevEcoStudio26.0"
  if mkdir -p "$_cfg"; then
    echo "-Dide.ui.scale=$_hidpi_scale" > "$_cfg/devecostudio-hidpi.vmoptions"
    export DEVECOSTUDIO_VM_OPTIONS="$_cfg/devecostudio-hidpi.vmoptions"
  fi
fi

if [[ "${DEVECO_DISABLE_X11_WORKAROUND:-0}" != "1" ]]; then
  unset WAYLAND_DISPLAY
  export GDK_BACKEND=x11
fi

_JCEF_ARGS=()
if [[ "${DEVECO_DISABLE_JCEF_HEADLESS:-0}" != "1" ]]; then
  _JCEF_ARGS=("-Dide.browser.jcef.headless.enabled=true" "-Dide.browser.jcef.out-of-process.enabled=true")
fi

mkdir -p "$HOME/Library/Huawei"
ln -sfn "$HOME/.Huawei/Sdk" "$HOME/Library/Huawei/Sdk"
exec "$(dirname "$(readlink -f "$0")")/devecostudio" "${_JCEF_ARGS[@]}" "$@"
SHEOF
chmod +x "${PKG_DIR}/bin/devecostudio.sh"

# 转换 product-info.json
jq \
  --arg os "Linux" \
  --arg arch "amd64" \
  --arg launcher "bin/devecostudio" \
  --arg java "jbr/bin/java" \
  --arg vmopts "bin/devecostudio64-lin.vmoptions" \
  --arg wmclass "deveco-studio" \
  --arg svg "bin/devecostudio.svg" \
  '.svgIconPath = $svg |
   .launch[0].os = $os |
   .launch[0].launcherPath = $launcher |
   .launch[0].javaExecutablePath = $java |
   .launch[0].arch = $arch |
   .launch[0].vmOptionsFilePath = $vmopts |
   .launch[0].startupWmClass = $wmclass |
   del(.launch[0].svgIconPath) |
   .launch[0].additionalJvmArguments |= (
     map(gsub("\\$APP_PACKAGE/Contents/"; "$IDE_HOME/")) |
     map(select(test("com\\.apple\\.eawt|com\\.apple\\.laf|sun\\.lwawt") | not)) |
     . + [
       "--enable-native-access=ALL-UNNAMED",
       "-Dawt.lock.fair=true",
       "-Dsun.tools.attach.tmp.only=true",
       "-Dglfw.im.module=fcitx",
       "--add-opens=java.desktop/com.sun.java.swing.plaf.gtk=ALL-UNNAMED",
       "--add-opens=java.desktop/javax.swing.text.html.parser=ALL-UNNAMED",
       "--add-opens=java.desktop/sun.awt.X11=ALL-UNNAMED"
     ]
   )' \
  "${MAC_CONTENTS}/Resources/product-info.json" > "${PKG_DIR}/product-info.json"

echo "==> [5/6] 清理多余平台文件与修复权限..."
find "${PKG_DIR}/jbr" -type f -executable -exec strip --strip-all {} \; 2>/dev/null || true
strip --strip-all "${PKG_DIR}/bin/devecostudio" 2>/dev/null || true
find "${PKG_DIR}/lib" -name '*.so' -exec strip --strip-unneeded {} \; 2>/dev/null || true
strip --strip-all "${PKG_DIR}/bin/fsnotifier" 2>/dev/null || true

find "${PKG_DIR}" -type d -exec chmod 755 {} \;
find "${PKG_DIR}" -type f -exec chmod 644 {} \;

python3 - "${PKG_DIR}" << 'PYEOF'
import os, sys
root = sys.argv[1]
for dirpath, dirnames, filenames in os.walk(root):
    for fn in filenames:
        p = os.path.join(dirpath, fn)
        try:
            with open(p, 'rb') as f:
                head = f.read(256)
            if head[:4] == b'\x7fELF' or b'#!' in head:
                st = os.stat(p)
                if not st.st_mode & 0o111:
                    os.chmod(p, st.st_mode | 0o111)
        except OSError:
            pass
PYEOF

find "${PKG_DIR}" -name '*.exe' -not -name 'Emulator.exe' -delete
find "${PKG_DIR}" -name '*.dll' -delete
find "${PKG_DIR}" -name '*.dylib' -delete
find "${PKG_DIR}" -name '*.jnilib' -delete
find "${PKG_DIR}" -name '*.bat' -delete
find "${PKG_DIR}" -name '*.ps1' -delete
find "${PKG_DIR}/bin" "${PKG_DIR}/tools/bin" -name '*.sh' -not -path '*/bin/devecostudio.sh' -delete 2>/dev/null || true
find "${PKG_DIR}/plugins" -name '*.sh' -delete 2>/dev/null || true

# 复制 desktop 文件到输出目录
cp "${SCRIPT_DIR}/devecostudio.desktop" "${OUTPUT_DIR}/"

echo "==> 打包生成通用 Tarball..."
tar -C "${OUTPUT_DIR}" -czf "${OUTPUT_DIR}/devecostudio-${PKGVER}-linux-x86_64.tar.gz" devecostudio devecostudio.desktop

echo "==> [6/6] 构建成功！"
echo "  -> 产物目录: ${PKG_DIR}"
echo "  -> 离线安装包: ${OUTPUT_DIR}/devecostudio-${PKGVER}-linux-x86_64.tar.gz"
echo ""
echo "如需立即安装到 openSUSE 系统，请执行："
echo "  sudo cp -r \"${PKG_DIR}\" /opt/"
echo "  sudo ln -sf /opt/devecostudio/bin/devecostudio.sh /usr/local/bin/devecostudio"
echo "  sudo desktop-file-install \"${OUTPUT_DIR}/devecostudio.desktop\""
