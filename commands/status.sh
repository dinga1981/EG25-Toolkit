#!/bin/bash
cmd_status() {
  header "EG25 Toolkit v${EG25_VERSION} 状态"
  local state iface ip gateway exit_info pubip exit_loc exit_colo default_iface default_service data_state runtime='unknown' vm_wwan_ip vm_public_ip usb_owner
  local mac_usb='否' vm_ssh='否' vm_usb='未知' qmi='未知' vohive='unknown'
  state="$(get_state)"
  usb_owner='未连接'
  mac_usb_present && usb_owner='Mac 主机'
  if vm_reachable && vm_usb_present; then usb_owner='Ubuntu VM'; fi
  iface="$(mac_baiwang_interface)"
  ip=''; gateway=''; exit_info=''; pubip=''; exit_loc=''; exit_colo=''
  mac_usb_present && mac_usb='是'
  if [ -n "$iface" ]; then
    ip="$(mac_interface_ipv4 "$iface")"
    gateway="$(mac_interface_gateway "$iface")"
  fi
  default_iface="$(mac_default_interface)"
  default_service="$(mac_default_service)"
  if vm_reachable; then
    vm_ssh='是'; vm_usb='否'; qmi='无'
    vm_usb_present && vm_usb='是'
    vm_qmi_present && qmi='存在'
    runtime="$(vm_vohive_runtime_state 2>/dev/null || printf unknown)"
    case "$runtime" in
      operational) vohive='operational' ;;
      idle) vohive='idle（服务运行但无完整模组设备）' ;;
      inactive) vohive='inactive' ;;
      *) vohive='unknown' ;;
    esac
  fi
  printf '模式：          %s
' "$(state_label "$state")"
  printf '物理 USB：      %s
' "$mac_usb"
  printf 'USB 当前归属：  %s
' "$usb_owner"
  printf 'Baiwang 接口：  %s
' "${iface:-无}"
  printf 'Baiwang IPv4：  %s
' "${ip:-无}"
  printf 'Baiwang 网关：  %s
' "${gateway:-无}"
  printf '默认接口：      %s
' "${default_iface:-无}"
  printf '默认服务：      %s
' "${default_service:-未知}"
  printf 'VM SSH：        %s
' "$vm_ssh"
  printf 'VM USB：        %s
' "$vm_usb"
  printf 'QMI 设备：      %s
' "$qmi"
  printf 'VoHive：        %s
' "$vohive"
  if [ "$qmi" = '存在' ]; then
    vm_wwan_ip="$(vm_wwan_ipv4 2>/dev/null || true)"
    vm_public_ip="$(vm_vohive_public_ipv4 2>/dev/null || true)"
    printf 'wwan0 IPv4：    %s\n' "${vm_wwan_ip:-无（数据连接未建立）}"
    [ -n "$vm_public_ip" ] && printf 'VoHive 公网出口：%s\n' "$vm_public_ip"
  fi
  if [ -n "$ip" ]; then
    data_state="$(mac_data_link_status "$iface")"
    case "$data_state" in
      CONNECTED)
        printf '4G 数据链路：   已连通（%s 可达）
' "${INTERNET_TEST_IP:-1.1.1.1}"
        exit_info="$(public_exit_via_interface "$iface" || true)"
        if [ -n "$exit_info" ]; then
          IFS='|' read -r pubip exit_loc exit_colo <<EOF
$exit_info
EOF
          printf '4G 公网出口：   %s
' "$pubip"
          [ -n "$exit_loc" ] && printf '出口地区：      %s
' "$exit_loc"
          [ -n "$exit_colo" ] && printf 'Cloudflare 节点：%s
' "$exit_colo"
          printf 'HTTPS 验证：    已通过
'
        else
          printf 'HTTPS 附加验证：未通过（不影响 4G 已连通判定）
'
        fi
        ;;
      GATEWAY_ONLY) printf '4G 数据链路：   仅网关可达，公网未通
' ;;
      *) printf '4G 数据链路：   不可达
' ;;
    esac
  fi
  [ "$runtime" = operational ] && printf 'VoHive 地址：   http://%s:%s
' "$VM_HOST" "$VOHIVE_PORT"
  say '========================================'
}
