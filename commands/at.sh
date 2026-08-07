#!/bin/bash
cmd_at() {
  [ "$#" -gt 0 ] || die "用法：eg25 at 'AT+CSQ'" 64
  vm_reachable || die "无法通过 SSH 连接 VM：$VM_TARGET"
  vm_python_ready || die 'VM 中未安装 python3'
  vm_sudo_ready || die 'VM 的 sudo 免密未配置，无法访问串口'
  vm_usb_present || die '模组当前不在 VM，AT 命令只能在模组接入 VM 时使用'
  vm_send_at "$*"
}
