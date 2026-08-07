#!/bin/bash
# shellcheck shell=bash

# V3.1.1 AT 通信层：使用已在目标 VM 验证成功的 pyserial。
remote_at_python='import os,sys,glob,time,base64,multiprocessing
import serial
cmd=base64.b64decode(sys.argv[1]).decode("ascii")
probe_timeout=float(sys.argv[2]) if len(sys.argv)>2 else 4.0
preferred=["/dev/serial/by-id/usb-BAIWANG_Baiwang-if02-port0","/dev/ttyUSB2","/dev/serial/by-id/usb-BAIWANG_Baiwang-if03-port0","/dev/ttyUSB3"]
all_ports=preferred+sorted(glob.glob("/dev/ttyUSB*"))
ports=[]; seen=set()
for p in all_ports:
 if not os.path.exists(p): continue
 key=os.path.realpath(p)
 if key in seen: continue
 seen.add(key); ports.append(p)
if not ports:
 print("ERROR: 未找到 /dev/ttyUSB*", file=sys.stderr); sys.exit(20)
def exchange(port, command, conn):
 ser=None
 try:
  ser=serial.Serial(port=port,baudrate=115200,timeout=0.2,write_timeout=1,exclusive=True)
  time.sleep(0.2)
  try: ser.reset_input_buffer()
  except Exception: pass
  ser.write(b"AT\r"); ser.flush()
  end=time.monotonic()+1.5; probe=bytearray()
  while time.monotonic()<end:
   waiting=ser.in_waiting
   if waiting:
    probe.extend(ser.read(waiting))
    if b"OK" in probe or b"ERROR" in probe: break
   time.sleep(0.05)
  if b"OK" not in probe:
   conn.send(("reject",bytes(probe).decode("utf-8","replace"))); return
  if command.strip().upper()=="AT":
   conn.send(("ok",bytes(probe).decode("utf-8","replace"))); return
  try: ser.reset_input_buffer()
  except Exception: pass
  ser.write((command+"\r").encode("ascii")); ser.flush()
  end=time.monotonic()+min(8.0,max(1.0,probe_timeout-0.5)); out=bytearray()
  while time.monotonic()<end:
   waiting=ser.in_waiting
   if waiting:
    out.extend(ser.read(waiting))
    if b"OK" in out or b"ERROR" in out: break
   time.sleep(0.05)
  raw=bytes(out)
  if b"OK" in raw: conn.send(("ok",raw.decode("utf-8","replace")))
  elif b"ERROR" in raw: conn.send(("command_error",raw.decode("utf-8","replace")))
  else: conn.send(("no_response",raw.decode("utf-8","replace")))
 except BaseException as e:
  try: conn.send(("exception",type(e).__name__+": "+str(e)))
  except Exception: pass
 finally:
  if ser is not None:
   try: ser.close()
   except Exception: pass
  try: conn.close()
  except Exception: pass
results=[]
for port in ports:
 parent,child=multiprocessing.Pipe(False)
 proc=multiprocessing.Process(target=exchange,args=(port,cmd,child))
 proc.start(); child.close(); proc.join(probe_timeout)
 if proc.is_alive():
  try: proc.kill()
  except AttributeError: proc.terminate()
  proc.join(1.0); results.append(port+"=TIMEOUT"); parent.close(); continue
 if parent.poll(): status,text=parent.recv()
 else: status,text="exception","子进程未返回结果"
 parent.close(); results.append(port+"="+status)
 if status in ("ok","command_error","no_response"):
  print("PORT: "+port); print(text.strip())
  if status=="ok": sys.exit(0)
  if status=="command_error": sys.exit(21)
  sys.exit(23)
print("ERROR: 找到 ttyUSB，但没有可用 AT 端口", file=sys.stderr)
print("探测结果："+"; ".join(results), file=sys.stderr)
sys.exit(22)'

base64_ascii() {
  printf '%s' "$1" | base64 | tr -d '\r\n'
}

vm_send_at() {
  local command="$1"
  local encoded
  local probe_timeout="${AT_PROBE_TIMEOUT:-4}"
  encoded="$(base64_ascii "$command")" || return 1
  ssh_vm "python3 -c '$remote_at_python' '$encoded' '$probe_timeout'"
}

wait_for_vm_at_port() {
  local seconds="${1:-$AT_PORT_WAIT}"
  local elapsed=0 output='' rc=0 last_output='' last_rc=0
  while [ "$elapsed" -lt "$seconds" ]; do
    output="$(vm_send_at 'AT' 2>&1)" && {
      [ -n "$output" ] && printf '%s
' "$output" >&2
      return 0
    }
    rc=$?
    last_output="$output"; last_rc="$rc"
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [ -n "$last_output" ]; then
    printf '    最后一次 AT 探测失败（rc=%s）：%s
' "$last_rc" \
      "$(printf '%s' "$last_output" | tail -n 2 | tr '
' ' ')" >&2
  fi
  return 1
}
