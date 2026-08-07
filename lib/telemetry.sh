#!/bin/bash
# shellcheck shell=bash

: "${EG25_DATA_DIR:=$HOME/.eg25}"
: "${EG25_HISTORY_FILE:=$EG25_DATA_DIR/history.tsv}"
: "${EG25_STATS_FILE:=$EG25_DATA_DIR/stats.json}"
: "${EG25_META_FILE:=$EG25_DATA_DIR/stats.env}"
: "${EG25_HISTORY_LIMIT:=100}"

EG25_RUN_STARTED_AT="${EG25_RUN_STARTED_AT:-0}"
EG25_RECORD_ACTION="${EG25_RECORD_ACTION:-}"
EG25_RECOVERY_ATTEMPTED="${EG25_RECOVERY_ATTEMPTED:-0}"
EG25_RECOVERY_SUCCEEDED="${EG25_RECOVERY_SUCCEEDED:-0}"
EG25_RECORD_DONE="${EG25_RECORD_DONE:-0}"

telemetry_init() {
  mkdir -p "$EG25_DATA_DIR" "${LOG_DIR:-$EG25_DATA_DIR/log}" 2>/dev/null || true
  [ -f "$EG25_HISTORY_FILE" ] || printf 'timestamp\taction\tresult\tduration_seconds\trecovery\trecovery_result\n' >"$EG25_HISTORY_FILE" 2>/dev/null || true
  [ -f "$EG25_META_FILE" ] || cat >"$EG25_META_FILE" <<META
TOTAL_RUNS=0
SUCCESS_RUNS=0
FAILED_RUNS=0
RECOVERY_ATTEMPTS=0
RECOVERY_SUCCESSES=0
RECOVERY_FAILURES=0
LAST_ACTION=
LAST_RESULT=
LAST_DURATION=0
LAST_TIMESTAMP=
LAST_RECOVERY_RESULT=NONE
META
  telemetry_write_json
}

telemetry_begin() {
  EG25_RUN_STARTED_AT="$(date +%s)"
  EG25_RECORD_ACTION="$1"
  EG25_RECOVERY_ATTEMPTED=0
  EG25_RECOVERY_SUCCEEDED=0
  EG25_RECORD_DONE=0
  export EG25_RUN_STARTED_AT EG25_RECORD_ACTION EG25_RECOVERY_ATTEMPTED EG25_RECOVERY_SUCCEEDED EG25_RECORD_DONE
}

telemetry_recovery_begin() {
  EG25_RECOVERY_ATTEMPTED=1
  EG25_RECOVERY_SUCCEEDED=0
  export EG25_RECOVERY_ATTEMPTED EG25_RECOVERY_SUCCEEDED
}

telemetry_recovery_success() {
  EG25_RECOVERY_ATTEMPTED=1
  EG25_RECOVERY_SUCCEEDED=1
  export EG25_RECOVERY_ATTEMPTED EG25_RECOVERY_SUCCEEDED
}

telemetry_get() {
  local key="$1" default="${2:-}"
  local value
  value="$(grep -E "^${key}=" "$EG25_META_FILE" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
  printf '%s' "${value:-$default}"
}

telemetry_write_meta() {
  cat >"$EG25_META_FILE.tmp" <<META
TOTAL_RUNS=$1
SUCCESS_RUNS=$2
FAILED_RUNS=$3
RECOVERY_ATTEMPTS=$4
RECOVERY_SUCCESSES=$5
RECOVERY_FAILURES=$6
LAST_ACTION=$7
LAST_RESULT=$8
LAST_DURATION=$9
LAST_TIMESTAMP=${10}
LAST_RECOVERY_RESULT=${11}
META
  mv "$EG25_META_FILE.tmp" "$EG25_META_FILE"
}

telemetry_write_json() {
  local total success failed ra rs rf action result duration timestamp rr
  total="$(telemetry_get TOTAL_RUNS 0)"; success="$(telemetry_get SUCCESS_RUNS 0)"; failed="$(telemetry_get FAILED_RUNS 0)"
  ra="$(telemetry_get RECOVERY_ATTEMPTS 0)"; rs="$(telemetry_get RECOVERY_SUCCESSES 0)"; rf="$(telemetry_get RECOVERY_FAILURES 0)"
  action="$(telemetry_get LAST_ACTION '')"; result="$(telemetry_get LAST_RESULT '')"; duration="$(telemetry_get LAST_DURATION 0)"
  timestamp="$(telemetry_get LAST_TIMESTAMP '')"; rr="$(telemetry_get LAST_RECOVERY_RESULT NONE)"
  cat >"$EG25_STATS_FILE.tmp" <<JSON
{
  "version": "${EG25_VERSION}",
  "total_runs": ${total},
  "successful_runs": ${success},
  "failed_runs": ${failed},
  "recovery_attempts": ${ra},
  "recovery_successes": ${rs},
  "recovery_failures": ${rf},
  "last_action": "${action}",
  "last_result": "${result}",
  "last_duration_seconds": ${duration},
  "last_timestamp": "${timestamp}",
  "last_recovery_result": "${rr}"
}
JSON
  mv "$EG25_STATS_FILE.tmp" "$EG25_STATS_FILE" 2>/dev/null || true
}

telemetry_finish() {
  local rc="${1:-0}" end duration result recovery recovery_result timestamp
  [ "$EG25_RECORD_DONE" = 0 ] || return 0
  [ -n "$EG25_RECORD_ACTION" ] || return 0
  EG25_RECORD_DONE=1
  export EG25_RECORD_DONE
  end="$(date +%s)"
  duration=$((end - EG25_RUN_STARTED_AT))
  [ "$duration" -ge 0 ] || duration=0
  if [ "$rc" -eq 0 ]; then result=SUCCESS; else result=FAILED; fi
  recovery=NO; recovery_result=NONE
  if [ "$EG25_RECOVERY_ATTEMPTED" -eq 1 ]; then
    recovery=YES
    if [ "$EG25_RECOVERY_SUCCEEDED" -eq 1 ]; then recovery_result=SUCCESS; else recovery_result=FAILED; fi
  fi
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$timestamp" "$EG25_RECORD_ACTION" "$result" "$duration" "$recovery" "$recovery_result" >>"$EG25_HISTORY_FILE" 2>/dev/null || true

  local total success failed ra rs rf
  total=$(( $(telemetry_get TOTAL_RUNS 0) + 1 ))
  success="$(telemetry_get SUCCESS_RUNS 0)"; failed="$(telemetry_get FAILED_RUNS 0)"
  ra="$(telemetry_get RECOVERY_ATTEMPTS 0)"; rs="$(telemetry_get RECOVERY_SUCCESSES 0)"; rf="$(telemetry_get RECOVERY_FAILURES 0)"
  if [ "$result" = SUCCESS ]; then success=$((success+1)); else failed=$((failed+1)); fi
  if [ "$recovery" = YES ]; then
    ra=$((ra+1))
    if [ "$recovery_result" = SUCCESS ]; then rs=$((rs+1)); else rf=$((rf+1)); fi
  fi
  telemetry_write_meta "$total" "$success" "$failed" "$ra" "$rs" "$rf" "$EG25_RECORD_ACTION" "$result" "$duration" "$timestamp" "$recovery_result"
  telemetry_write_json
  # 保留表头和最近 N 条记录。
  if [ -f "$EG25_HISTORY_FILE" ]; then
    { head -n 1 "$EG25_HISTORY_FILE"; tail -n "$EG25_HISTORY_LIMIT" "$EG25_HISTORY_FILE" | grep -v '^timestamp' || true; } >"$EG25_HISTORY_FILE.tmp"
    mv "$EG25_HISTORY_FILE.tmp" "$EG25_HISTORY_FILE"
  fi
}

telemetry_last_recovery_summary() {
  local attempts successes failures last
  attempts="$(telemetry_get RECOVERY_ATTEMPTS 0)"
  successes="$(telemetry_get RECOVERY_SUCCESSES 0)"
  failures="$(telemetry_get RECOVERY_FAILURES 0)"
  last="$(telemetry_get LAST_RECOVERY_RESULT NONE)"
  printf '%s|%s|%s|%s' "$attempts" "$successes" "$failures" "$last"
}
