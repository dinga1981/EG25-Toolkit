#!/bin/bash
# shellcheck shell=bash

ssh_vm() { ssh "${SSH_OPTS[@]}" "$VM_TARGET" "$@"; }
vm_reachable() { ssh_vm true >/dev/null 2>&1; }
vm_sudo_ready() { ssh_vm 'sudo -n true' >/dev/null 2>&1; }
vm_python_ready() { ssh_vm 'command -v python3 >/dev/null 2>&1' >/dev/null 2>&1; }
vm_lsusb_ready() { ssh_vm 'command -v lsusb >/dev/null 2>&1' >/dev/null 2>&1; }
vm_usb_present() { ssh_vm "lsusb 2>/dev/null | grep -qi '${VIDPID}'" >/dev/null 2>&1; }
vm_any_ttyusb() { ssh_vm 'set -- /dev/ttyUSB*; [ -c "$1" ]' >/dev/null 2>&1; }
vm_ttyusb_list() { ssh_vm 'for d in /dev/ttyUSB*; do [ -c "$d" ] && printf "%s\n" "$d"; done' 2>/dev/null; }
vm_qmi_present() { ssh_vm 'test -c /dev/cdc-wdm0' >/dev/null 2>&1; }
vm_vohive_exists() { ssh_vm "systemctl cat '$VOHIVE_SERVICE' >/dev/null 2>&1" >/dev/null 2>&1; }
vm_vohive_active() { ssh_vm "systemctl is-active --quiet '$VOHIVE_SERVICE'" >/dev/null 2>&1; }
vm_stop_vohive() { ssh_vm "sudo -n systemctl stop '$VOHIVE_SERVICE'"; }
vm_start_vohive() { ssh_vm "sudo -n systemctl restart '$VOHIVE_SERVICE' && systemctl is-active --quiet '$VOHIVE_SERVICE'"; }
vm_vohive_status_tail() { ssh_vm "systemctl status '$VOHIVE_SERVICE' --no-pager -l 2>/dev/null | tail -n 40"; }

# 输出：operational / idle / inactive / unknown
# operational 必须同时满足服务 active、USB 模组、ttyUSB 和 QMI 控制设备存在。
vm_vohive_runtime_state() {
  vm_reachable || { printf '%s\n' 'unknown'; return 1; }
  if ! vm_vohive_active; then
    printf '%s\n' 'inactive'
    return 0
  fi
  if vm_usb_present && vm_any_ttyusb && vm_qmi_present; then
    printf '%s\n' 'operational'
  else
    printf '%s\n' 'idle'
  fi
}

vm_vohive_operational() {
  [ "$(vm_vohive_runtime_state 2>/dev/null)" = 'operational' ]
}

# 返回 wwan0 的首个 IPv4 地址；无地址时返回失败。
vm_wwan_ipv4() {
  ssh_vm "ip -o -4 addr show dev wwan0 2>/dev/null | awk 'NR==1 {split(\$4,a,\"/\"); print a[1]}'" 2>/dev/null
}

vm_wwan_ready() {
  local ip
  ip="$(vm_wwan_ipv4)"
  [ -n "$ip" ]
}

vm_vohive_recent_logs() {
  local lines="${1:-80}"
  ssh_vm "journalctl -u '$VOHIVE_SERVICE' -n '$lines' --no-pager -o cat 2>/dev/null"
}

vm_vohive_has_code241() {
  vm_vohive_recent_logs 120 | grep -Eq 'call end type=2 code=241|code=241'
}

vm_vohive_public_ipv4() {
  vm_vohive_recent_logs 120 | sed -nE 's/.*"public_ip"[[:space:]]*:[[:space:]]*"([0-9.]+)".*/\1/p' | tail -n 1
}

wait_for_vm_data() {
  local seconds="${1:-$VOHIVE_DATA_WAIT_SECONDS}"
  wait_until "$seconds" 'wwan0 获得 IPv4' vm_wwan_ready
}
