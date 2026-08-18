#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "请以 root 身份运行此脚本: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist/devecostudio"

if [[ ! -d "${DIST_DIR}" ]]; then
  echo "错误: 未找到构建目录 ${DIST_DIR}"
  exit 1
fi

echo "==> 复制到 /opt/devecostudio..."
rm -rf /opt/devecostudio
cp -r "${DIST_DIR}" /opt/

echo "==> 创建系统级软链接 /usr/local/bin/devecostudio..."
ln -sf /opt/devecostudio/bin/devecostudio.sh /usr/local/bin/devecostudio
for tool in hvigorw ohpm hstack; do
  ln -sf "/opt/devecostudio/tools/bin/${tool}" "/usr/local/bin/${tool}"
done
ln -sf /opt/devecostudio/tools/bin/codelinter /usr/local/bin/hcodelinter
ln -sf /opt/devecostudio/tools/bin/Emulator /usr/local/bin/hemulator

echo "==> 安装系统桌面图标..."
desktop-file-install "${SCRIPT_DIR}/devecostudio.desktop"

echo "==> 系统级安装完成！"
