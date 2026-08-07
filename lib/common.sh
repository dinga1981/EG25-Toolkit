#!/bin/bash
# shellcheck shell=bash

EG25_VERSION="3.3.1"
EG25_ROOT="${EG25_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
EG25_CONFIG="${EG25_CONFIG:-$EG25_ROOT/config/eg25.conf}"

if [ ! -r "$EG25_CONFIG" ]; then
  printf 'ERROR: 配置文件不可读：%s\n' "$EG25_CONFIG" >&2
  exit 78
fi
# shellcheck disable=SC1090
. "$EG25_CONFIG"

: "${VM_USER:=liu}"
: "${VM_HOST:=192.168.64.2}"
: "${VM_NAME:=Linux}"
: "${VIDPID:=2c7c:0125}"
: "${USB_MATCH_NAME:=Baiwang}"
: "${MAC_SERVICE_NAME:=Baiwang}"
: "${VOHIVE_SERVICE:=vohive}"
: "${VOHIVE_PORT:=7575}"
: "${UTMCTL:=/Applications/UTM.app/Contents/MacOS/utmctl}"
: "${SSH_CONNECT_TIMEOUT:=8}"
: "${USB_CONNECT_RETRIES:=5}"
: "${USB_CONNECT_WAIT:=10}"
: "${AT_PORT_WAIT:=35}"
: "${QMI_WAIT_SECONDS:=50}"
: "${ECM_WAIT_SECONDS:=75}"
: "${INTERNET_TEST_URL:=https://1.1.1.1/cdn-cgi/trace}"
: "${PUBLIC_IP_FALLBACK_URLS:=https://api.ipify.org https://icanhazip.com}"
: "${MANUAL_USB_WAIT_SECONDS:=90}"
: "${VOHIVE_DATA_WAIT_SECONDS:=30}"
: "${VOHIVE_RECOVERY_WAIT_SECONDS:=40}"
: "${CFUN_USB_LEAVE_WAIT_SECONDS:=30}"
: "${LOG_DIR:=$HOME/Library/Logs/eg25-toolkit}"

VM_TARGET="${VM_USER}@${VM_HOST}"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=2)

EG25_COMMAND="${EG25_COMMAND:-unknown}"
EG25_LOG_FILE=""

init_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  EG25_LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d').log"
}

log_line() {
  [ -n "$EG25_LOG_FILE" ] || init_log
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$EG25_COMMAND" "$*" >>"$EG25_LOG_FILE" 2>/dev/null || true
}

say()  { printf '%s\n' "$*"; log_line "$*"; }
step() { printf '[%s/%s] %s\n' "$1" "$2" "$3"; log_line "STEP $1/$2 $3"; }
info() { printf '    %s\n' "$*"; log_line "INFO $*"; }
ok()   { printf '    ✓ %s\n' "$*"; log_line "PASS $*"; }
warn() { printf '    ⚠ %s\n' "$*" >&2; log_line "WARN $*"; }
error(){ printf '    ✗ %s\n' "$*" >&2; log_line "FAIL $*"; }
die()  { printf '\n❌ %s\n' "$*" >&2; log_line "FATAL $*"; exit "${2:-1}"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

run_with_timeout() {
  local timeout_seconds="$1"
  shift
  "$@" &
  local pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

# 用法：wait_until 秒数 描述 函数 [参数...]
wait_until() {
  if [ "$#" -lt 3 ]; then
    error "内部错误：wait_until 至少需要 3 个参数"
    return 64
  fi
  local timeout_seconds="$1"
  local description="$2"
  shift 2
  local elapsed=0
  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if "$@"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  warn "等待超时：${description}（${timeout_seconds}s）"
  return 1
}

header() {
  say '========================================'
  say "$1"
  say '========================================'
}
