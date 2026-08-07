#!/bin/bash
cmd_doctor() {
  header "EG25 Toolkit v${EG25_VERSION} Doctor"
  local failures=0 state iface ip runtime
  check_line 'macOS: networksetup' command_exists networksetup || failures=$((failures+1))
  check_line 'macOS: route' command_exists route || failures=$((failures+1))
  check_line 'macOS: ipconfig' command_exists ipconfig || failures=$((failures+1))
  check_line 'macOS: ping' command_exists ping || failures=$((failures+1))
  check_line 'macOS: curl' command_exists curl || failures=$((failures+1))
  check_line 'UTM: utmctl' test -x "$UTMCTL" || failures=$((failures+1))
  check_line 'VM: SSH' vm_reachable || failures=$((failures+1))

  state="$(get_state)"
  if vm_reachable; then
    check_line 'VM: sudo 免密' vm_sudo_ready || failures=$((failures+1))
    check_line 'VM: python3' vm_python_ready || failures=$((failures+1))
    check_line 'VM: lsusb' vm_lsusb_ready || failures=$((failures+1))
    check_line 'VM: VoHive 服务' vm_vohive_exists || failures=$((failures+1))

    if [ "$state" = 'MAC_ECM' ] || [ "$state" = 'MAC_USB_NO_ECM' ]; then
      check_na_line 'VM: USB 模组' 'Mac 模式下应不存在'
      check_na_line 'VM: ttyUSB' 'Mac 模式下应不存在'
      check_na_line 'VM: cdc-wdm0' 'Mac 模式下应不存在'
    else
      check_line 'VM: USB 模组' vm_usb_present || true
      check_line 'VM: ttyUSB' vm_any_ttyusb || true
      check_line 'VM: cdc-wdm0' vm_qmi_present || true
    fi

    runtime="$(vm_vohive_runtime_state 2>/dev/null || printf unknown)"
    case "$runtime" in
      operational) check_value_line 'VM: VoHive 状态' '✓' 'operational' ;;
      idle)        check_value_line 'VM: VoHive 状态' '-' 'idle（服务运行但无完整模组设备）' ;;
      inactive)    check_value_line 'VM: VoHive 状态' '-' 'inactive' ;;
      *)           check_value_line 'VM: VoHive 状态' '?' 'unknown' ;;
    esac
  fi

  iface="$(mac_baiwang_interface)"; ip=''
  [ -n "$iface" ] && ip="$(mac_interface_ipv4 "$iface")"
  if [ -n "$iface" ]; then check_value_line 'Mac: Baiwang 接口' '✓' "$iface"; else check_na_line 'Mac: Baiwang 接口' '未发现'; fi
  if [ -n "$ip" ]; then
    check_value_line 'Mac: ECM IPv4' '✓' "$ip"
    if mac_cellular_internet_reachable "$iface"; then
      check_value_line 'Mac: 4G 数据链路' '✓' "已连通 (${INTERNET_TEST_IP:-1.1.1.1})"
    elif mac_gateway_reachable "$iface"; then
      check_value_line 'Mac: 4G 数据链路' '!' '仅网关可达'
    else
      check_value_line 'Mac: 4G 数据链路' '✗' '不可达'
    fi
  else
    check_na_line 'Mac: ECM IPv4' '当前模式未获得地址'
    check_na_line 'Mac: 4G 数据链路' '当前模式不适用'
  fi

  say ''
  printf '当前状态：%s\n' "$(state_label "$state")"
  printf '日志文件：%s\n' "$EG25_LOG_FILE"
  if [ "$failures" -eq 0 ]; then
    say ''
    say '✅ 核心依赖检查通过。“-”表示当前模式不适用或服务处于待机状态，不代表故障。'
    return 0
  fi
  say ''
  error "发现 ${failures} 个核心依赖问题"
  info '请先解决带“✗”的核心依赖项目，再执行模式切换。'
  return 1
}
