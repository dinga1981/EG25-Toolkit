#!/bin/bash
# shellcheck shell=bash

vohive_show_diagnostics() {
  local logs ip
  logs="$(vm_vohive_recent_logs 60 2>/dev/null || true)"
  [ -n "$logs" ] && printf '%s\n' "$logs" | tail -n 25 | sed 's/^/    /'
  ip="$(vm_wwan_ipv4 2>/dev/null || true)"
  if [ -n "$ip" ]; then
    info "wwan0 IPv4：$ip"
  else
    warn 'wwan0 尚未获得 IPv4'
  fi
}

vohive_wait_data_verbose() {
  local seconds="${1:-$VOHIVE_DATA_WAIT_SECONDS}" elapsed=0 ip
  while [ "$elapsed" -lt "$seconds" ]; do
    ip="$(vm_wwan_ipv4 2>/dev/null || true)"
    if [ -n "$ip" ]; then
      return 0
    fi
    if [ "$elapsed" -eq 0 ] || [ $((elapsed % 5)) -eq 0 ]; then
      info "等待 wwan0 IPv4... ${elapsed}/${seconds}s"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

# v3.3：不再依赖 code 241 日志触发。只要 wwan0 在首轮等待内没有 IPv4，
# 就执行一次受控 CFUN 重启，清理模组内部残留的数据接口状态。
vohive_controlled_recovery() {
  local output
  telemetry_recovery_begin
  warn '首轮数据连接未建立，开始一次受控恢复'

  info '停止 VoHive，释放 QMI 控制通道...'
  vm_stop_vohive >/dev/null 2>&1 || true

  info '通过 VM AT 端口重启模组（AT+CFUN=1,1）...'
  output="$(vm_send_at 'AT+CFUN=1,1' 2>&1)" || {
    printf '%s\n' "$output" | sed 's/^/    /'
    error '模组重启指令失败'
    return 1
  }
  printf '%s\n' "$output" | sed 's/^/    /'

  wait_for_usb_leave_vm "$CFUN_USB_LEAVE_WAIT_SECONDS" || \
    warn '未观察到 USB 从 VM 消失，仍继续等待重新枚举'

  if ! wait_for_vm_usb_reattach "$MANUAL_USB_WAIT_SECONDS"; then
    error "模组重启后未在 ${MANUAL_USB_WAIT_SECONDS}s 内重新接入 VM"
    return 1
  fi

  if ! wait_until "$QMI_WAIT_SECONDS" '/dev/cdc-wdm0 重新出现' vm_qmi_present; then
    error 'CFUN 重启后 QMI 控制设备未恢复'
    return 1
  fi
  ok 'QMI 控制设备已恢复'

  vm_start_vohive || {
    vm_vohive_status_tail | sed 's/^/    /' || true
    error 'VoHive 重新启动失败'
    return 1
  }
  ok 'VoHive 已重新启动'

  if vohive_wait_data_verbose "$VOHIVE_RECOVERY_WAIT_SECONDS"; then
    telemetry_recovery_success
    return 0
  fi
  return 1
}

vohive_verify_transaction() {
  local ip public_ip

  if vohive_wait_data_verbose "$VOHIVE_DATA_WAIT_SECONDS"; then
    ip="$(vm_wwan_ipv4)"
    public_ip="$(vm_vohive_public_ipv4 2>/dev/null || true)"
    ok "QMI 数据连接已建立：$ip"
    [ -n "$public_ip" ] && ok "公网出口：$public_ip"
    return 0
  fi

  warn 'VoHive 服务已运行，但 wwan0 未获得 IPv4'
  if vm_vohive_has_code241; then
    warn '日志同时检测到 QMI call end code 241'
  fi

  if vohive_controlled_recovery; then
    ip="$(vm_wwan_ipv4)"
    public_ip="$(vm_vohive_public_ipv4 2>/dev/null || true)"
    ok "QMI 数据连接恢复成功：$ip"
    [ -n "$public_ip" ] && ok "公网出口：$public_ip"
    return 0
  fi

  vohive_show_diagnostics
  return 1
}

cmd_vohive() {
  telemetry_begin 'ECM_TO_QMI'
  header 'EG25 → VM QMI / VoHive（事务模式）'
  local state output ip public_ip
  state="$(get_state)"

  vm_reachable || die "无法通过 SSH 连接 VM：$VM_TARGET"
  vm_sudo_ready || die 'VM 的 sudo 免密未配置'
  vm_python_ready || die 'VM 中未安装 python3'

  if [ "$state" = 'VM_QMI' ]; then
    if ! vm_vohive_active; then
      info '当前已是 QMI 模式，正在启动 VoHive...'
      vm_start_vohive || die 'VoHive 启动失败'
    fi
    if vm_wwan_ready; then
      ok '当前已经是 VM QMI / VoHive 模式，数据连接正常'
      cmd_status
      return 0
    fi
    warn '当前已是 QMI 模式，但数据连接未建立；进入事务恢复流程'
    vohive_verify_transaction || die '自动恢复后 QMI 数据连接仍未建立，请运行 eg25 health'
    cmd_status
    return 0
  fi

  step 1 8 '将模组接入 VM...'
  if ! vm_usb_present; then
    if ! connect_usb_to_vm; then
      info '自动接入未成功；请在 UTM 虚拟机窗口选择 USB → Baiwang，工具将继续等待。'
      wait_for_vm_usb_reattach "$MANUAL_USB_WAIT_SECONDS" || \
        die "等待 USB 接入超时（${MANUAL_USB_WAIT_SECONDS}s）"
    fi
  else
    ok '模组已经在 VM 中'
  fi

  step 2 8 '等待可用 AT 端口...'
  if ! wait_for_vm_at_port "$AT_PORT_WAIT"; then
    info "检测到的串口：$(vm_ttyusb_list | tr '\n' ' ')"
    die '未找到可响应 AT 的 ttyUSB 端口'
  fi
  ok 'AT 端口可用'

  step 3 8 '停止可能残留的 VoHive 服务...'
  vm_stop_vohive >/dev/null 2>&1 || true
  ok 'VoHive 已停止'

  step 4 8 '切换为 QMI 模式...'
  output="$(vm_send_at 'AT+QCFG="usbnet",0' 2>&1)" || {
    printf '%s\n' "$output" | sed 's/^/    /'
    die 'AT 指令未返回 OK'
  }
  printf '%s\n' "$output" | sed 's/^/    /'
  ok '模组已接受 USB 模式配置；最终以 /dev/cdc-wdm0 验证'

  step 5 8 '等待 USB 重新枚举...'
  wait_for_usb_leave_vm 25 || warn '未观察到 VM USB 消失，继续尝试重新接入'

  step 6 8 '重新将模组接入 VM并等待 QMI...'
  wait_for_vm_usb_reattach "$MANUAL_USB_WAIT_SECONDS" || \
    die "等待 USB 重连超时（${MANUAL_USB_WAIT_SECONDS}s）。请确认 UTM 中已选择 USB → Baiwang"
  if ! wait_until "$QMI_WAIT_SECONDS" '/dev/cdc-wdm0 出现' vm_qmi_present; then
    connect_usb_to_vm >/dev/null 2>&1 || true
    wait_until 20 '/dev/cdc-wdm0 出现' vm_qmi_present || die 'QMI 控制设备未出现，请运行 eg25 doctor'
  fi
  ok '/dev/cdc-wdm0 已出现'

  step 7 8 '启动 VoHive...'
  vm_start_vohive || {
    vm_vohive_status_tail | sed 's/^/    /' || true
    die 'VoHive 启动失败'
  }
  ok 'VoHive 服务已启动'

  step 8 8 '阻塞验证 QMI 数据连接，失败时自动恢复一次...'
  vohive_verify_transaction || die 'VoHive 已启动，但自动恢复后数据连接仍未建立'

  ip="$(vm_wwan_ipv4)"
  public_ip="$(vm_vohive_public_ipv4 2>/dev/null || true)"
  say ''
  say '✅ 已切换到 VM QMI / VoHive 模式'
  say '   QMI：/dev/cdc-wdm0'
  say "   wwan0：$ip"
  [ -n "$public_ip" ] && say "   公网出口：$public_ip"
  say "   VoHive：http://${VM_HOST}:${VOHIVE_PORT}"
}

cmd_repair() {
  telemetry_begin 'QMI_REPAIR'
  header 'EG25 QMI / VoHive 自动修复'
  vm_reachable || die "无法通过 SSH 连接 VM：$VM_TARGET"
  vm_sudo_ready || die 'VM 的 sudo 免密未配置'
  vm_qmi_present || die '当前未发现 /dev/cdc-wdm0；请先运行 eg25 vohive'

  if ! vm_vohive_active; then
    info 'VoHive 未运行，正在启动...'
    vm_start_vohive || die 'VoHive 启动失败'
  fi
  if vm_wwan_ready; then
    ok "数据连接正常：$(vm_wwan_ipv4)"
    cmd_status
    return 0
  fi

  warn '检测到 wwan0 无 IPv4；无论日志是否出现 code 241，都执行一次受控恢复'
  vohive_controlled_recovery || die '受控恢复失败'
  ok "修复完成：$(vm_wwan_ipv4)"
  cmd_status
}

cmd_reset() {
  telemetry_begin 'QMI_RESET'
  header 'EG25 QMI 强制重置'
  vm_reachable || die "无法通过 SSH 连接 VM：$VM_TARGET"
  vm_sudo_ready || die 'VM 的 sudo 免密未配置'
  vm_usb_present || die '模组当前不在 VM 中，无法执行 QMI 重置'
  wait_for_vm_at_port "$AT_PORT_WAIT" || die '未找到可用 AT 端口'
  vohive_controlled_recovery || die '强制重置后数据连接仍未恢复'
  ok "重置完成：$(vm_wwan_ipv4)"
  cmd_status
}

cmd_health() {
  header 'EG25 健康检查'
  local failures=0 ip public_ip

  if vm_reachable; then ok 'VM SSH 可达'; else error 'VM SSH 不可达'; failures=$((failures+1)); fi
  if vm_usb_present; then ok 'USB 当前归属 VM'; else warn 'USB 当前不在 VM'; fi
  if vm_qmi_present; then ok '/dev/cdc-wdm0 存在'; else error '/dev/cdc-wdm0 不存在'; failures=$((failures+1)); fi
  if vm_vohive_active; then ok 'VoHive 服务 active'; else error 'VoHive 服务 inactive'; failures=$((failures+1)); fi
  ip="$(vm_wwan_ipv4 2>/dev/null || true)"
  if [ -n "$ip" ]; then ok "wwan0 IPv4：$ip"; else error 'wwan0 没有 IPv4'; failures=$((failures+1)); fi
  public_ip="$(vm_vohive_public_ipv4 2>/dev/null || true)"
  if [ -n "$public_ip" ]; then ok "最近记录的公网出口：$public_ip"; else warn '暂未从 VoHive 日志读取到公网出口'; fi
  local recovery_summary recovery_attempts recovery_successes recovery_failures last_recovery
  recovery_summary="$(telemetry_last_recovery_summary)"
  IFS='|' read -r recovery_attempts recovery_successes recovery_failures last_recovery <<EOF
$recovery_summary
EOF
  if [ "$failures" -eq 0 ]; then
    if [ "$last_recovery" = 'SUCCESS' ]; then
      ok "最近一次自动恢复：成功（累计 ${recovery_successes}/${recovery_attempts}）"
    elif [ "$recovery_attempts" -gt 0 ]; then
      info "自动恢复累计：成功 ${recovery_successes}，失败 ${recovery_failures}"
    fi
    # 当前链路 READY 时，历史 code 241 不再作为警告。
    if vm_vohive_has_code241 && [ "$last_recovery" = 'SUCCESS' ]; then
      info '历史日志曾出现 code 241，当前已恢复，不影响 READY 判定'
    fi
  elif vm_vohive_has_code241; then
    warn '当前异常且最近日志存在 code 241'
  fi

  say '----------------------------------------'
  if [ "$failures" -eq 0 ]; then
    say '状态：READY'
    return 0
  fi
  say "状态：DEGRADED（${failures} 项关键检查失败）"
  return 1
}
