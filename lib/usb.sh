#!/bin/bash
# shellcheck shell=bash

mac_usb_present() {
  local vendor_hex product_hex
  vendor_hex="${VIDPID%%:*}"
  product_hex="${VIDPID##*:}"
  ioreg -p IOUSB -l -w 0 2>/dev/null | awk -v n="$USB_MATCH_NAME" -v v="$vendor_hex" -v p="$product_hex" '
    BEGIN { IGNORECASE=1; found=0 }
    index($0,n)>0 { found=1 }
    /idVendor/ && tolower($0) ~ "0x" v { vendor=1 }
    /idProduct/ && tolower($0) ~ "0x" p { product=1 }
    END { exit !((found) || (vendor && product)) }
  '
}

utm_running() {
  "$UTMCTL" list 2>/dev/null | grep -Fq "$VM_NAME"
}

connect_usb_to_vm_once() {
  "$UTMCTL" usb connect "$VM_NAME" "$VIDPID" >/dev/null 2>&1 || true
  wait_until "$USB_CONNECT_WAIT" 'VM 识别 USB 模组' vm_usb_present
}

connect_usb_to_vm() {
  [ -x "$UTMCTL" ] || { error "找不到 utmctl：$UTMCTL"; return 1; }
  local attempt=1
  while [ "$attempt" -le "$USB_CONNECT_RETRIES" ]; do
    info "USB 连接尝试 ${attempt}/${USB_CONNECT_RETRIES}..."
    if connect_usb_to_vm_once; then
      ok '模组已接入 VM'
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  return 1
}

wait_for_usb_leave_vm() {
  local seconds="${1:-20}"
  local elapsed=0
  while [ "$elapsed" -lt "$seconds" ]; do
    if ! vm_usb_present; then return 0; fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}


# USB 重枚举后 UTM 可能需要手动重新勾选 Baiwang；持续等待，无需重跑命令。
wait_for_vm_usb_reattach() {
  local seconds="${1:-$MANUAL_USB_WAIT_SECONDS}" elapsed=0 next_retry=0 announced=0
  while [ "$elapsed" -lt "$seconds" ]; do
    if vm_usb_present; then
      ok '模组已重新接入 VM'
      return 0
    fi
    if [ "$elapsed" -ge "$next_retry" ]; then
      "$UTMCTL" usb connect "$VM_NAME" "$VIDPID" >/dev/null 2>&1 || true
      next_retry=$((elapsed + 5))
    fi
    if [ "$announced" -eq 0 ] && [ "$elapsed" -ge 8 ]; then
      info '若 UTM 未自动接回，请现在在虚拟机窗口选择 USB → Baiwang；工具会继续等待，无需重跑命令。'
      announced=1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}
