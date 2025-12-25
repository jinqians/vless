#!/usr/bin/env bash
set -e

# =========================================================
# VLESS Reality 一键菜单脚本
# Author: jinqians
# =========================================================

SCRIPT_REMOTE_URL="https://raw.githubusercontent.com/jinqians/vless/refs/heads/main/vless.sh"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
VLESS_CMD="/usr/local/bin/vless"

# root 校验
if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 运行此脚本"
  exit 1
fi

# ================= 工具函数 =================

ensure_deps() {
  apt update -y
  apt install -y curl qrencode || true
}

get_ips() {
  IPV4=$(curl -4 -s https://api.ipify.org || true)
  IPV6=$(curl -6 -s https://api64.ipify.org || true)
}

parse_x25519() {
  KEY_OUTPUT=$(xray x25519 2>&1)

  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i 'private' | awk -F': *' '{print $2}' | head -n1)
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i 'public' | awk -F': *' '{print $2}' | head -n1)

  if [[ -z "$PUBLIC_KEY" ]]; then
    PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i 'password' | awk -F': *' '{print $2}' | head -n1)
  fi
  if [[ -z "$PUBLIC_KEY" ]]; then
    PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i 'hash32' | awk -F': *' '{print $2}' | head -n1)
  fi

  echo "$KEY_OUTPUT" > /tmp/x25519-raw.txt
}

write_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$DEST",
          "serverNames": $SERVER_NAMES_JSON,
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [""]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF
}

install_vless_cmd() {
  if [[ -f "$VLESS_CMD" ]]; then
    return
  fi

  cat > "$VLESS_CMD" << 'EOFSCRIPT'
#!/bin/bash

RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请以 root 权限运行 vless${RESET}"
    exit 1
fi

TMP_SCRIPT=$(mktemp)
SCRIPT_URL="https://raw.githubusercontent.com/jinqians/vless/refs/heads/main/vless.sh"

echo -e "${CYAN}正在获取最新版本的 VLESS Reality 管理脚本...${RESET}"
if curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT"; then
    bash "$TMP_SCRIPT"
    rm -f "$TMP_SCRIPT"
else
    echo -e "${RED}下载脚本失败，请检查网络连接。${RESET}"
    rm -f "$TMP_SCRIPT"
    exit 1
fi
EOFSCRIPT

  chmod +x "$VLESS_CMD"
}

output_links() {
  get_ips

  if [[ -n "$IPV4" ]]; then
    V4="vless://${UUID}@${IPV4}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME_FIRST}&fp=chrome&pbk=${PUBLIC_KEY}&type=tcp#VLESS-Reality-IPv4"
    echo "IPv4 链接："
    echo "$V4"
    qrencode -t ANSIUTF8 "$V4"
  fi

  if [[ -n "$IPV6" ]]; then
    V6="vless://${UUID}@[$IPV6]:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME_FIRST}&fp=chrome&pbk=${PUBLIC_KEY}&type=tcp#VLESS-Reality-IPv6"
    echo
    echo "IPv6 链接："
    echo "$V6"
    qrencode -t ANSIUTF8 "$V6"
  fi
}

# ================= 菜单功能 =================

install_action() {
  ensure_deps

  if ! command -v xray >/dev/null 2>&1; then
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
  fi

  read -p "监听端口 [443]: " PORT
  PORT=${PORT:-443}

  read -p "dest [www.cloudflare.com:443]: " DEST
  DEST=${DEST:-www.cloudflare.com:443}

  read -p "serverNames (逗号) [www.cloudflare.com]: " SERVER_NAMES_RAW
  SERVER_NAMES_RAW=${SERVER_NAMES_RAW:-www.cloudflare.com}

  IFS=',' read -ra SN <<< "$SERVER_NAMES_RAW"
  SERVER_NAMES_JSON=$(printf '"%s",' "${SN[@]}")
  SERVER_NAMES_JSON="[${SERVER_NAMES_JSON%,}]"
  SERVER_NAME_FIRST=${SN[0]}

  UUID=$(xray uuid)
  parse_x25519

  if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    echo "❌ Reality Key 解析失败"
    cat /tmp/x25519-raw.txt
    exit 1
  fi

  write_config

  systemctl enable xray
  systemctl restart xray

  install_vless_cmd

  echo
  echo "=========== 安装完成 ==========="
  echo "UUID       : $UUID"
  echo "PrivateKey : $PRIVATE_KEY"
  echo "PublicKey  : $PUBLIC_KEY"
  echo "端口       : $PORT"
  echo "dest       : $DEST"
  echo "serverNames: $SERVER_NAMES_RAW"
  echo
  echo "🚀 后续管理请直接执行命令： vless"
  echo

  output_links

  echo
  echo "============================================"
  echo "✅ 安装完成，脚本已退出"
  echo "👉 使用 vless 命令进入管理菜单"
  echo "============================================"
  echo

  exit 0
}

update_action() {
  bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
  systemctl restart xray || true
  xray -version | head -n 3
}

uninstall_action() {
  read -p "⚠️ 将彻底删除 Xray 与所有配置，是否继续？(y/N): " yn
  [[ ! "$yn" =~ ^[Yy]$ ]] && return

  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  pkill -9 xray 2>/dev/null || true

  rm -f /etc/systemd/system/xray.service
  rm -f /etc/systemd/system/xray@.service
  rm -rf /etc/systemd/system/xray*.d

  rm -rf /usr/local/etc/xray /etc/xray /usr/local/etc/xray-reality /etc/xray-reality
  rm -f /usr/local/bin/xray /usr/bin/xray /bin/xray
  rm -f /usr/local/bin/vless

  systemctl daemon-reexec
  systemctl daemon-reload

  echo "✅ 已彻底卸载 VLESS Reality"
}

status_action() {
  systemctl status xray --no-pager || true
  ss -lntp || true
  [[ -f "$CONFIG_FILE" ]] && sed -n '1,200p' "$CONFIG_FILE"
}

show_config_action() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ 未找到配置文件：$CONFIG_FILE"
    return
  fi

  echo
  echo "=========== 当前 VLESS Reality 配置 ==========="
  echo "配置文件: $CONFIG_FILE"
  echo

  # 基本字段解析
  PORT=$(grep -oP '"port"\s*:\s*\K[0-9]+' "$CONFIG_FILE" | head -n1)
  UUID=$(grep -oP '"id"\s*:\s*"\K[^"]+' "$CONFIG_FILE" | head -n1)
  DEST=$(grep -oP '"dest"\s*:\s*"\K[^"]+' "$CONFIG_FILE" | head -n1)
  PRIVATE_KEY=$(grep -oP '"privateKey"\s*:\s*"\K[^"]+' "$CONFIG_FILE" | head -n1)

  SERVER_NAMES=$(grep -oP '"serverNames"\s*:\s*\[\K[^\]]+' "$CONFIG_FILE" | tr -d '"' | tr ',' '\n' | head -n5)
  SERVER_NAME_FIRST=$(echo "$SERVER_NAMES" | head -n1)

  # Reality publicKey 无法从配置反推，提示用户
  echo "端口        : $PORT"
  echo "UUID        : $UUID"
  echo "dest        : $DEST"
  echo "serverNames :"
  echo "$SERVER_NAMES" | sed 's/^/  - /'
  echo

  # IP
  get_ips

  # PublicKey 提示
  echo "⚠️ Reality PublicKey 无法从服务端配置反推"
  echo "👉 请使用安装时输出的 PublicKey"
  echo

  # 输出链接（不含 pbk）
  if [[ -n "$IPV4" ]]; then
    echo "IPv4 示例链接（需手动补充 pbk）："
    echo "vless://${UUID}@${IPV4}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME_FIRST}&fp=chrome&type=tcp"
    echo
  fi

  if [[ -n "$IPV6" ]]; then
    echo "IPv6 示例链接（需手动补充 pbk）："
    echo "vless://${UUID}@[$IPV6]:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_NAME_FIRST}&fp=chrome&type=tcp"
    echo
  fi

  echo "=============================================="
  echo
  read -p "按 Enter 返回菜单..."
}


self_update() {
  curl -fsSL "$SCRIPT_REMOTE_URL" -o /tmp/vless-menu.sh
  chmod +x /tmp/vless-menu.sh
  cp /tmp/vless-menu.sh "$0"
  exec bash "$0"
}

# ================= 主菜单 =================

while true; do
  echo -e "\033[0;36m============================================\033[0m"
  echo -e "\033[0;36m            vless 管理脚本\033[0m"
  echo -e "\033[0;36m============================================\033[0m"
  echo -e "\033[0;32m作者: jinqians\033[0m"
  echo -e "\033[0;32m网站: https://jinqians.com\033[0m"
  echo -e "\033[0;36m============================================\033[0m"
  echo "1) 安装 VLESS Reality"
  echo "2) 更新 Xray"
  echo "3) 卸载 VLESS Reality"
  echo "4) 查看运行状态"
  echo "5) 查看当前配置"
  echo "0) 更新脚本"
  echo "q) 退出"
  read -p "请选择: " c
  case "$c" in
    1) install_action ;;
    2) update_action ;;
    3) uninstall_action ;;
    4) status_action ;;
    5) show_config_action ;;
    0) self_update ;;
    q|Q) exit 0 ;;
    *) echo "无效选项" ;;
  esac
done
