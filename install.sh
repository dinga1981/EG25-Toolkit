#!/bin/bash
set -e
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DEST="/usr/local/lib/eg25-toolkit"
BIN="/usr/local/bin/eg25"
OLD_CONFIG="/usr/local/lib/eg25-toolkit/config/eg25.conf"
TMP_CONFIG=""

if [ -r "$OLD_CONFIG" ]; then
  TMP_CONFIG="$(mktemp)"
  cp "$OLD_CONFIG" "$TMP_CONFIG"
fi

echo '安装 EG25 Toolkit v3.3.2...'
sudo rm -rf "$DEST"
sudo mkdir -p "$DEST"
sudo cp -R "$ROOT/bin" "$ROOT/lib" "$ROOT/commands" "$ROOT/config" "$DEST/"
if [ -n "$TMP_CONFIG" ]; then
  # 仅迁移 V2 中仍适用的关键参数，V3 新参数保留默认值。
  for key in VM_USER VM_HOST VM_NAME VIDPID MAC_SERVICE_NAME VOHIVE_PORT UTMCTL SSH_CONNECT_TIMEOUT USB_CONNECT_RETRIES ECM_WAIT_SECONDS QMI_WAIT_SECONDS INTERNET_TEST_IP MANUAL_USB_WAIT_SECONDS VOHIVE_DATA_WAIT_SECONDS VOHIVE_RECOVERY_WAIT_SECONDS CFUN_USB_LEAVE_WAIT_SECONDS; do
    value="$(grep -E "^${key}=" "$TMP_CONFIG" | tail -n 1 || true)"
    if [ -n "$value" ]; then
      sudo sed -i '' -E "s|^${key}=.*$|${value}|" "$DEST/config/eg25.conf"
    fi
  done
  rm -f "$TMP_CONFIG"
fi
sudo rm -f "$BIN"
sudo ln -s "$DEST/bin/eg25" "$BIN"
sudo chmod 755 "$DEST/bin/eg25"
sudo find "$DEST" -type f -name '*.sh' -exec chmod 644 {} \;

# 删除 V2 兼容命令，避免误运行旧代码；保留用户自行创建的其他文件。
for old in eg25-status eg25-to-mac eg25-to-vohive eg25-at eg25-diagnose eg25-status.sh eg25-to-mac.sh eg25-to-vohive.sh; do
  [ -L "/usr/local/bin/$old" ] && sudo rm -f "/usr/local/bin/$old"
done

echo ''
mkdir -p "$HOME/.eg25/log"
echo '✅ 安装完成'
echo '版本：      EG25 Toolkit 3.3.2'
echo '命令位置：  /usr/local/bin/eg25'
echo '程序目录：  /usr/local/lib/eg25-toolkit'
echo '数据目录：  ~/.eg25'
echo ''
/usr/local/bin/eg25 version
echo '建议先运行：eg25 doctor'
echo '然后运行：  eg25 status'
