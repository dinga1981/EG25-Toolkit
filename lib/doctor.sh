#!/bin/bash
# shellcheck shell=bash

check_line() {
  local name="$1"; shift
  if "$@"; then printf '  %-24s ✓\n' "$name"; return 0
  else printf '  %-24s ✗\n' "$name"; return 1; fi
}

check_na_line() {
  local name="$1" detail="${2:-当前模式不适用}"
  printf '  %-24s -  %s\n' "$name" "$detail"
}

check_value_line() {
  local name="$1" symbol="$2" value="$3"
  printf '  %-24s %s  %s\n' "$name" "$symbol" "$value"
}
