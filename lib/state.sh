#!/bin/bash
# shellcheck shell=bash

get_state() {
  if mac_ecm_ready; then
    printf '%s\n' 'MAC_ECM'
    return 0
  fi
  if vm_reachable && vm_usb_present; then
    if vm_qmi_present; then
      printf '%s\n' 'VM_QMI'
    else
      printf '%s\n' 'VM_USB_NO_QMI'
    fi
    return 0
  fi
  if mac_usb_present; then
    printf '%s\n' 'MAC_USB_NO_ECM'
  else
    printf '%s\n' 'UNKNOWN'
  fi
}

state_label() {
  case "$1" in
    MAC_ECM) printf '%s' 'macOS ECM' ;;
    VM_QMI) printf '%s' 'VM QMI / VoHive' ;;
    VM_USB_NO_QMI) printf '%s' '模组在 VM，但 QMI 未就绪' ;;
    MAC_USB_NO_ECM) printf '%s' '模组在 Mac，但 ECM 未就绪' ;;
    *) printf '%s' '未知/过渡状态' ;;
  esac
}
