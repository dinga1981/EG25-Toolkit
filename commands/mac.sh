#!/bin/bash
cmd_mac() {
  telemetry_begin 'QMI_TO_ECM'
  header 'EG25 → macOS ECM'
  local state output iface ip gateway exit_info pubip exit_loc exit_colo default_iface
  state="$(get_state)"
  if [ "$state" = 'MAC_ECM' ]; then
    if vm_reachable && vm_vohive_active; then
      info '检测到 VoHive 服务仍在后台运行，正在停止空转服务...'
      if vm_stop_vohive >/dev/null 2>&1; then ok 'VoHive 已停止'; else warn 'VoHive 停止失败，但不影响当前 ECM 网络'; fi
    fi
    ok '当前已经是 macOS ECM 模式，无需切换'
    cmd_status
    return 0
  fi
  vm_reachable || die "无法通过 SSH 连接 VM：$VM_TARGET"
  vm_sudo_ready || die 'VM 的 sudo 免密未配置'
  vm_python_ready || die 'VM 中未安装 python3'
  vm_usb_present || die '模组不在 VM；请先执行 eg25 vohive 或在 UTM 中把 Baiwang 接入 VM'

  step 1 5 '停止 VoHive...'
  if vm_stop_vohive; then ok 'VoHive 已停止'; else warn 'VoHive 停止失败或原本未运行，继续尝试'; fi

  step 2 5 '扫描 AT 端口并切换为 ECM...'
  output="$(vm_send_at 'AT+QCFG="usbnet",1' 2>&1)" || {
    printf '%s\n' "$output" | sed 's/^/    /'
    warn 'ECM 指令失败，尝试恢复 VoHive'
    vm_start_vohive >/dev/null 2>&1 || true
    die 'AT 指令未返回 OK'
  }
  printf '%s\n' "$output" | sed 's/^/    /'
  ok '模组已接受 USB 模式配置；将以最终 ECM 接口验证结果为准'

  step 3 5 '等待 USB 重新枚举并返回 macOS...'
  wait_for_usb_leave_vm 25 || warn '未观察到 VM USB 消失，继续检查 macOS ECM'

  step 4 5 '等待 Baiwang 获得 IPv4 地址...'
  if ! wait_for_ecm "$ECM_WAIT_SECONDS"; then
    warn 'macOS 未获得 ECM 地址；模组可能仍停留在 VM 或 USB 重枚举失败'
    die "切换未完成，请运行 eg25 doctor 查看诊断"
  fi
  iface="$(mac_baiwang_interface)"; ip="$(mac_interface_ipv4 "$iface")"; gateway="$(mac_interface_gateway "$iface")"
  ok "接口：$iface"
  ok "IPv4：$ip"
  [ -n "$gateway" ] && ok "网关：$gateway"

  step 5 5 '验证 4G 数据链路...'
  if mac_cellular_internet_reachable "$iface"; then
    ok "4G 数据已连通：${INTERNET_TEST_IP:-1.1.1.1} 可达"
    exit_info="$(public_exit_via_interface "$iface" || true)"
    if [ -n "$exit_info" ]; then
      IFS='|' read -r pubip exit_loc exit_colo <<EOF
$exit_info
EOF
      ok "HTTPS 已通过；公网出口：$pubip"
      [ -n "$exit_loc" ] && info "出口地区：$exit_loc"
      [ -n "$exit_colo" ] && info "Cloudflare 节点：$exit_colo"
    else
      info 'HTTPS 附加验证未通过；不影响 4G 已连通判定'
    fi
  elif mac_gateway_reachable "$iface"; then
    warn 'ECM 网关可达，但公网 IP 测试失败'
  else
    warn 'ECM 已获得地址，但网关和公网均不可达'
  fi
  default_iface="$(mac_default_interface)"
  say ''
  say '✅ 已切换到 macOS ECM 模式'
  say "   Baiwang：$iface / $ip"
  if [ "$default_iface" = "$iface" ]; then say '   当前默认出口：4G'; else say "   当前默认出口：${default_iface:-未知}，4G 保持备用"; fi
}
