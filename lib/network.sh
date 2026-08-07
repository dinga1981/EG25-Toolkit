#!/bin/bash
# shellcheck shell=bash

mac_baiwang_interface() {
  networksetup -listallhardwareports 2>/dev/null | awk -v target="$MAC_SERVICE_NAME" '
    $0 == "Hardware Port: " target {
      if (getline > 0 && $1 == "Device:") { print $2; exit }
    }'
}

mac_interface_ipv4() {
  [ -n "${1:-}" ] || return 1
  ipconfig getifaddr "$1" 2>/dev/null
}

mac_interface_gateway() {
  [ -n "${1:-}" ] || return 1
  route -n get default -ifscope "$1" 2>/dev/null | awk '/gateway:/{print $2; exit}'
}

mac_default_interface() {
  route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'
}

mac_default_service() {
  local iface
  iface="$(mac_default_interface)"
  [ -n "$iface" ] || return 1
  networksetup -listallhardwareports 2>/dev/null | awk -v dev="$iface" '
    /^Hardware Port:/ { port=substr($0,16) }
    /^Device:/ && $2==dev { print port; exit }'
}

mac_ecm_ready() {
  local iface ip
  iface="$(mac_baiwang_interface)"
  [ -n "$iface" ] || return 1
  ip="$(mac_interface_ipv4 "$iface")"
  [ -n "$ip" ]
}

wait_for_ecm() {
  wait_until "${1:-$ECM_WAIT_SECONDS}" 'macOS ECM 接口获得 IPv4 地址' mac_ecm_ready
}

# macOS 的 curl --interface 接口名在多默认路由场景下并不总是可靠。
# V3.1.1 的主要连通性判断使用指定源地址的 ICMP；HTTPS 仅作附加验证。
mac_ping_from_ip() {
  local source_ip="$1" target="$2" count="${3:-2}"
  [ -n "$source_ip" ] && [ -n "$target" ] || return 1
  ping -S "$source_ip" -c "$count" -W 2000 "$target" >/dev/null 2>&1
}

mac_gateway_reachable() {
  local iface="$1" source_ip gateway
  source_ip="$(mac_interface_ipv4 "$iface")" || return 1
  gateway="$(mac_interface_gateway "$iface")" || return 1
  [ -n "$source_ip" ] && [ -n "$gateway" ] || return 1
  mac_ping_from_ip "$source_ip" "$gateway" 2
}

mac_cellular_internet_reachable() {
  local iface="$1" source_ip
  source_ip="$(mac_interface_ipv4 "$iface")" || return 1
  [ -n "$source_ip" ] || return 1
  mac_ping_from_ip "$source_ip" "${INTERNET_TEST_IP:-1.1.1.1}" 2
}

# 输出格式：IP|国家/地区|Cloudflare 节点。后两项可能为空。
public_exit_via_interface() {
  local iface="$1" source_ip trace ip loc colo url body
  source_ip="$(mac_interface_ipv4 "$iface")" || return 1
  [ -n "$source_ip" ] || return 1

  trace="$(curl --interface "$source_ip" -4 --silent --show-error \
    --connect-timeout 5 --max-time 12 \
    "${INTERNET_TEST_URL:-https://1.1.1.1/cdn-cgi/trace}" 2>/dev/null || true)"
  ip="$(printf '%s
' "$trace" | awk -F= '$1=="ip"{print $2; exit}')"
  if [ -n "$ip" ]; then
    loc="$(printf '%s
' "$trace" | awk -F= '$1=="loc"{print $2; exit}')"
    colo="$(printf '%s
' "$trace" | awk -F= '$1=="colo"{print $2; exit}')"
    printf '%s|%s|%s
' "$ip" "$loc" "$colo"
    return 0
  fi

  for url in ${PUBLIC_IP_FALLBACK_URLS:-https://api.ipify.org https://icanhazip.com}; do
    body="$(curl --interface "$source_ip" -4 --silent --show-error \
      --connect-timeout 4 --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if printf '%s' "$body" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      printf '%s||
' "$body"
      return 0
    fi
  done
  return 1
}

public_ip_via_interface() {
  local result
  result="$(public_exit_via_interface "$1")" || return 1
  printf '%s
' "${result%%|*}"
}

mac_data_link_status() {
  local iface="$1"
  if mac_cellular_internet_reachable "$iface"; then
    printf '%s\n' 'CONNECTED'
  elif mac_gateway_reachable "$iface"; then
    printf '%s\n' 'GATEWAY_ONLY'
  else
    printf '%s\n' 'DISCONNECTED'
  fi
}
