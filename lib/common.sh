#!/bin/bash
# shellcheck shell=bash

EG25_VERSION="3.3.2"
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
: "${EG25_DATA_DIR:=$HOME/.eg25}"
: "${EG25_LOCK_DIR:=$EG25_DATA_DIR/operation.lock}"
: "${LOG_DIR:=$HOME/Library/Logs/eg25-toolkit}"

VM_TARGET="${VM_USER}@${VM_HOST}"
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" -o ServerAliveInterval=5 -o ServerAliveCountMax=2)

EG25_COMMAND="${EG25_COMMAND:-unknown}"
EG25_LOG_FILE=""
EG25_LOCK_HELD=0
EG25_LOCK_TOKEN=""

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

command_requires_operation_lock() {
  case "${1:-}" in
    mac|vohive|repair|reset|at) return 0 ;;
    *) return 1 ;;
  esac
}

operation_lock_process_start() {
  [ -n "${1:-}" ] || return 1
  ps -p "$1" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

operation_lock_is_active() {
  local pid recorded_start current_start
  pid="$(cat "$EG25_LOCK_DIR/pid" 2>/dev/null || true)"
  recorded_start="$(cat "$EG25_LOCK_DIR/process_started" 2>/dev/null || true)"
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" 2>/dev/null || return 1

  # 防止异常退出后 PID 被其他进程复用。旧锁没有启动签名时，保守地视为有效。
  [ -n "$recorded_start" ] || return 0
  current_start="$(operation_lock_process_start "$pid" || true)"
  [ -n "$current_start" ] && [ "$current_start" = "$recorded_start" ]
}

show_operation_lock_owner() {
  local pid command_name started
  pid="$(cat "$EG25_LOCK_DIR/pid" 2>/dev/null || printf '未知')"
  command_name="$(cat "$EG25_LOCK_DIR/command" 2>/dev/null || printf '未知')"
  started="$(cat "$EG25_LOCK_DIR/started_at" 2>/dev/null || printf '未知')"
  error '已有 EG25 独占操作正在运行'
  printf '    PID：%s\n' "$pid" >&2
  printf '    命令：%s\n' "$command_name" >&2
  printf '    开始时间：%s\n' "$started" >&2
}

wait_for_operation_lock_metadata() {
  local attempt=1
  while [ "$attempt" -le 5 ]; do
    [ -r "$EG25_LOCK_DIR/pid" ] && return 0
    sleep 0.1
    attempt=$((attempt + 1))
  done
  return 1
}

reclaim_stale_operation_lock() {
  local stale_dir
  stale_dir="${EG25_LOCK_DIR}.stale.$$"

  # 原子改名确保多个竞争进程不会误删刚刚建立的新锁。
  mv "$EG25_LOCK_DIR" "$stale_dir" 2>/dev/null || return 1
  rm -f "$stale_dir/pid" "$stale_dir/command" "$stale_dir/started_at" \
    "$stale_dir/process_started" "$stale_dir/token" 2>/dev/null || true
  if ! rmdir "$stale_dir" 2>/dev/null; then
    error "失效锁目录包含未知文件，未自动删除：$stale_dir"
    return 1
  fi
  warn '检测到失效的 EG25 操作锁，已安全清理'
}

acquire_operation_lock() {
  local command_name="${1:-unknown}" attempt=1 process_started
  [ -n "$EG25_LOCK_DIR" ] && [ "$EG25_LOCK_DIR" != '/' ] || {
    error 'EG25_LOCK_DIR 配置无效'
    return 78
  }
  mkdir -p "$(dirname "$EG25_LOCK_DIR")" 2>/dev/null || {
    error "无法创建操作锁父目录：$(dirname "$EG25_LOCK_DIR")"
    return 73
  }

  while [ "$attempt" -le 3 ]; do
    if mkdir "$EG25_LOCK_DIR" 2>/dev/null; then
      EG25_LOCK_TOKEN="$$-$(date +%s)-${RANDOM:-0}"
      process_started="$(operation_lock_process_start "$$" || true)"
      printf '%s\n' "$$" >"$EG25_LOCK_DIR/pid"
      printf '%s\n' "$command_name" >"$EG25_LOCK_DIR/command"
      printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >"$EG25_LOCK_DIR/started_at"
      printf '%s\n' "$process_started" >"$EG25_LOCK_DIR/process_started"
      printf '%s\n' "$EG25_LOCK_TOKEN" >"$EG25_LOCK_DIR/token"
      EG25_LOCK_HELD=1
      export EG25_LOCK_HELD EG25_LOCK_TOKEN
      log_line "LOCK acquired path=$EG25_LOCK_DIR"
      return 0
    fi

    # mkdir 与元数据写入之间存在极短窗口；先等待持锁进程写入 PID，避免误判为失效锁。
    wait_for_operation_lock_metadata || true
    if operation_lock_is_active; then
      show_operation_lock_owner
      return 75
    fi
    reclaim_stale_operation_lock || {
      error "无法回收失效操作锁：$EG25_LOCK_DIR"
      return 75
    }
    attempt=$((attempt + 1))
  done

  error "无法取得 EG25 操作锁：$EG25_LOCK_DIR"
  return 75
}

release_operation_lock() {
  local recorded_token
  [ "$EG25_LOCK_HELD" -eq 1 ] || return 0
  recorded_token="$(cat "$EG25_LOCK_DIR/token" 2>/dev/null || true)"
  if [ -z "$EG25_LOCK_TOKEN" ] || [ "$recorded_token" != "$EG25_LOCK_TOKEN" ]; then
    warn '操作锁所有权已变化，拒绝删除其他进程的锁'
    EG25_LOCK_HELD=0
    return 1
  fi

  log_line "LOCK released path=$EG25_LOCK_DIR"
  rm -f "$EG25_LOCK_DIR/pid" "$EG25_LOCK_DIR/command" \
    "$EG25_LOCK_DIR/started_at" "$EG25_LOCK_DIR/process_started" \
    "$EG25_LOCK_DIR/token" 2>/dev/null || true
  if ! rmdir "$EG25_LOCK_DIR" 2>/dev/null; then
    warn "操作锁目录未能完全清理：$EG25_LOCK_DIR"
    EG25_LOCK_HELD=0
    EG25_LOCK_TOKEN=""
    return 1
  fi
  EG25_LOCK_HELD=0
  EG25_LOCK_TOKEN=""
}

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
