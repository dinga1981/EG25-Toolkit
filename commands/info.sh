#!/bin/bash
# shellcheck shell=bash

cmd_info() {
  header 'EG25 Toolkit 信息'
  local install_path mode
  install_path="$(command -v eg25 2>/dev/null || printf '%s' "$EG25_ROOT/bin/eg25")"
  mode="$(state_label "$(get_state)")"
  printf 'Toolkit 版本：   %s\n' "$EG25_VERSION"
  printf '命令位置：       %s\n' "$install_path"
  printf '程序目录：       %s\n' "$EG25_ROOT"
  printf '配置文件：       %s\n' "$EG25_CONFIG"
  printf '数据目录：       %s\n' "$EG25_DATA_DIR"
  printf '日志目录：       %s\n' "$LOG_DIR"
  printf '历史记录：       %s\n' "$EG25_HISTORY_FILE"
  printf '统计文件：       %s\n' "$EG25_STATS_FILE"
  printf 'VM：             %s\n' "$VM_TARGET"
  printf 'VoHive：         http://%s:%s\n' "$VM_HOST" "$VOHIVE_PORT"
  printf '当前模式：       %s\n' "$mode"
  say '========================================'
}

cmd_history() {
  header 'EG25 最近运行历史'
  local limit="${1:-20}"
  case "$limit" in *[!0-9]*|'') die '用法：eg25 history [条数]' 64 ;; esac
  [ "$limit" -gt 0 ] || die '历史条数必须大于 0' 64
  if [ ! -s "$EG25_HISTORY_FILE" ] || [ "$(wc -l <"$EG25_HISTORY_FILE" | tr -d ' ')" -le 1 ]; then
    say '暂无历史记录。执行 eg25 mac、vohive、repair 或 reset 后会自动记录。'
    return 0
  fi
  printf '%-19s  %-12s  %-7s  %-6s  %-8s  %s\n' '时间' '操作' '结果' '耗时' '自动恢复' '恢复结果'
  printf '%s\n' '----------------------------------------------------------------------------'
  tail -n "$limit" "$EG25_HISTORY_FILE" | grep -v '^timestamp' | while IFS=$'\t' read -r ts action result duration recovery recovery_result; do
    printf '%-19s  %-12s  %-7s  %4ss  %-8s  %s\n' "$ts" "$action" "$result" "$duration" "$recovery" "$recovery_result"
  done
  say '----------------------------------------------------------------------------'
  printf '总运行：%s；成功：%s；失败：%s；恢复尝试：%s；恢复成功：%s；恢复失败：%s\n' \
    "$(telemetry_get TOTAL_RUNS 0)" "$(telemetry_get SUCCESS_RUNS 0)" "$(telemetry_get FAILED_RUNS 0)" \
    "$(telemetry_get RECOVERY_ATTEMPTS 0)" "$(telemetry_get RECOVERY_SUCCESSES 0)" "$(telemetry_get RECOVERY_FAILURES 0)"
}
