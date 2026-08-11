# EG25-Toolkit 中文文档

[English](README.md) | 简体中文

EG25-Toolkit 是一套面向 macOS、UTM Ubuntu 虚拟机和 LTE 模组的命令行管理工具。它将 USB 设备切换、AT 指令、ECM/QMI 模式转换、VoHive 服务控制、网络验证与故障恢复整合为统一的 `eg25` 命令。

项目最初为 Quectel EG25-G 与 Baiwang 兼容设备开发，主要用于减少蜂窝模组在 macOS 主机和 Linux 虚拟机之间切换时的重复配置与排障工作。

> 当前稳定版本：**3.3.1**

## 主要功能

- 在 macOS ECM 与 VM QMI / VoHive 模式之间切换
- 自动识别模组在 Mac 或 Ubuntu VM 中的当前状态
- 尝试通过 UTM 将 USB 模组接入虚拟机
- 自动探测 VM 中可响应的 `ttyUSB` AT 端口
- 检查 ECM、QMI、`wwan0`、VoHive 和公网连通状态
- 在 QMI 数据连接失败时执行一次受控 CFUN 恢复
- 保存操作历史、恢复结果和运行日志
- 提供依赖检查、状态诊断和健康检查命令

## 工作方式

EG25-Toolkit 支持两种主要工作模式：

### macOS ECM 模式

LTE 模组由 macOS 使用，并以 ECM 网络接口提供蜂窝网络连接。

```text
LTE 模组 → macOS ECM 接口 → 4G 网络
```

### VM QMI / VoHive 模式

LTE 模组通过 USB 连接到 UTM Ubuntu 虚拟机，由 QMI 接口和 VoHive 服务建立数据连接。

```text
LTE 模组 → UTM Ubuntu VM → QMI / wwan0 → VoHive
```

## 已验证环境

- Apple Silicon Mac
- UTM Ubuntu 虚拟机
- Quectel EG25-G / USB ID `2c7c:0125`
- Baiwang 兼容 USB 设备
- VM 内的 QMI 设备 `/dev/cdc-wdm0`
- VM 内由 systemd 管理的 `vohive` 服务

其他 Quectel 兼容模组可通过配置尝试使用，但需要自行验证 USB ID、AT 指令、串口布局和网络接口。

## 前置条件

### macOS 主机

- UTM 已安装，虚拟机可以正常启动
- UTM 命令行工具 `utmctl` 可用
- 系统中可使用 `networksetup`、`route`、`ipconfig`、`ping`、`curl` 和 `ssh`
- 当前用户可以使用 `sudo` 安装文件到 `/usr/local`

### Ubuntu 虚拟机

- SSH 可从 macOS 免交互连接
- 已配置免密 `sudo`
- 已安装 `python3`、`pyserial`、`usbutils` 和 `iproute2`
- 已安装并配置 VoHive systemd 服务
- 模组处于 QMI 模式时可生成 `/dev/cdc-wdm0` 和 `wwan0`

Ubuntu 中可按需安装基础依赖：

```bash
sudo apt update
sudo apt install -y python3 python3-serial usbutils iproute2
```

确认 SSH 和免密 sudo：

```bash
ssh <VM_USER>@<VM_HOST> true
ssh <VM_USER>@<VM_HOST> sudo -n true
```

## 安装

克隆仓库并切换到稳定版本：

```bash
git clone https://github.com/dinga1981/EG25-Toolkit.git
cd EG25-Toolkit
git checkout v3.3.1
```

执行安装：

```bash
chmod +x install.sh uninstall.sh bin/eg25
./install.sh
```

安装完成后，程序和配置默认位于：

```text
/usr/local/bin/eg25
/usr/local/lib/eg25-toolkit/
```

## 配置

安装前可编辑：

```text
config/eg25.conf
```

安装后生效的配置文件位于：

```text
/usr/local/lib/eg25-toolkit/config/eg25.conf
```

建议至少确认以下项目：

```bash
VM_USER="liu"
VM_HOST="192.168.64.2"
VM_NAME="Linux"
VIDPID="2c7c:0125"
USB_MATCH_NAME="Baiwang"
MAC_SERVICE_NAME="Baiwang"
VOHIVE_SERVICE="vohive"
VOHIVE_PORT="7575"
UTMCTL="/Applications/UTM.app/Contents/MacOS/utmctl"
```

| 配置项 | 说明 |
| --- | --- |
| `VM_USER` | Ubuntu VM 的 SSH 用户名 |
| `VM_HOST` | Ubuntu VM 的 IP 地址 |
| `VM_NAME` | UTM 中显示的虚拟机名称 |
| `VIDPID` | LTE 模组的 USB VID:PID |
| `USB_MATCH_NAME` | macOS USB 设备名称匹配值 |
| `MAC_SERVICE_NAME` | macOS 中 ECM 网络硬件端口名称 |
| `VOHIVE_SERVICE` | VM 内的 systemd 服务名 |
| `VOHIVE_PORT` | VoHive Web 服务端口 |
| `UTMCTL` | `utmctl` 的完整路径 |

配置文件还提供 USB 重试次数、AT 探测、ECM/QMI 等待时间、网络测试地址和自动恢复等待时间等高级参数。

> 升级安装会保留一部分现有环境参数；新增配置项使用新版本默认值。升级后仍建议检查最终配置文件。

## 首次检查

先检查运行依赖：

```bash
eg25 doctor
```

再查看模组、VM 和网络状态：

```bash
eg25 status
```

`doctor` 中的 `-` 表示当前模式不适用或服务处于待机状态，并不一定代表故障。优先处理带 `✗` 的核心依赖问题。

## 命令说明

| 命令 | 用途 |
| --- | --- |
| `eg25 status` | 查看当前模式、USB 归属、网络接口和数据连接状态 |
| `eg25 mac` | 切换到 macOS ECM 模式 |
| `eg25 vohive` | 切换到 VM QMI / VoHive 模式并验证数据连接 |
| `eg25 repair` | `wwan0` 无 IPv4 时执行一次受控恢复 |
| `eg25 health` | 检查 QMI、VoHive、`wwan0` 和最近恢复状态 |
| `eg25 reset` | 执行 `AT+CFUN=1,1` 并恢复 QMI 数据连接 |
| `eg25 at 'AT+CSQ'` | 自动探测 VM 内的 AT 端口并发送指令 |
| `eg25 doctor` | 检查主机、UTM、VM 和 VoHive 依赖 |
| `eg25 info` | 显示版本、路径、配置和当前模式 |
| `eg25 history [条数]` | 查看最近操作及自动恢复统计，默认显示 20 条 |
| `eg25 version` | 显示版本 |
| `eg25 help` | 显示命令帮助 |

## 常用流程

### 切换到 macOS ECM

```bash
eg25 mac
```

该命令会停止 VM 内的 VoHive 服务，向模组发送 ECM 模式指令，等待 USB 重新枚举，并检查 macOS ECM 接口的 IPv4 与 4G 连通性。

### 切换到 VM QMI / VoHive

```bash
eg25 vohive
```

该命令会尝试把模组接入 UTM VM，探测 AT 端口，切换到 QMI 模式，启动 VoHive，并等待 `wwan0` 获得 IPv4。

USB 重新枚举后，UTM 可能无法自动重新连接设备。如果终端出现提示，请在 UTM 虚拟机窗口选择：

```text
USB → Baiwang
```

工具会在等待时间内继续运行，无需重新执行命令。

### 发送 AT 指令

```bash
eg25 at 'AT'
eg25 at 'AT+CSQ'
eg25 at 'AT+QCFG="usbnet"'
```

AT 命令只能在模组已接入 VM、串口设备存在且 `pyserial` 可用时执行。请确认指令适用于你的模组；错误的 AT 配置可能导致设备失联或网络模式改变。

### 修复 QMI 数据连接

```bash
eg25 repair
```

当 `/dev/cdc-wdm0` 已存在，但 `wwan0` 没有 IPv4 时，工具会：

1. 停止 VoHive，释放 QMI 控制通道；
2. 发送 `AT+CFUN=1,1` 重启模组；
3. 等待 USB 和 QMI 设备重新出现；
4. 重新启动 VoHive；
5. 验证 `wwan0` 是否获得 IPv4。

每次操作最多执行一次受控恢复，避免无休止重启。

## 状态与故障排查

### 无法连接 VM

检查地址、SSH 和免密 sudo：

```bash
ssh <VM_USER>@<VM_HOST>
ssh <VM_USER>@<VM_HOST> sudo -n true
```

然后确认 `VM_USER` 和 `VM_HOST` 与配置文件一致。

### VM 中找不到 USB 模组

在 Ubuntu VM 中运行：

```bash
lsusb
```

默认配置应能看到 USB ID `2c7c:0125`。如未出现，请在 UTM 中手动选择 `USB → Baiwang`，或修改 `VIDPID` 为实际设备值。

### 找不到 AT 端口

在 VM 中检查：

```bash
ls -l /dev/ttyUSB*
python3 -c 'import serial; print(serial.__version__)'
```

工具会优先探测 Baiwang `if02/if03`、`/dev/ttyUSB2` 和 `/dev/ttyUSB3`，随后扫描其他 `ttyUSB` 端口。

### 找不到 QMI 设备

```bash
ls -l /dev/cdc-wdm0
eg25 doctor
```

如果模组仍处于 ECM 模式，可运行 `eg25 vohive`。如果 USB 重枚举后没有自动接回 VM，请在 UTM 中手动重新选择设备。

### VoHive 已启动但 wwan0 无 IPv4

```bash
eg25 health
eg25 repair
```

如自动恢复仍失败，在 VM 中查看服务日志：

```bash
journalctl -u vohive -n 100 --no-pager
ip -4 addr show dev wwan0
```

### macOS ECM 已获得地址但公网不通

```bash
eg25 status
networksetup -listallhardwareports
route -n get default
```

检查 `MAC_SERVICE_NAME` 是否与 macOS 中的硬件端口名称一致。工具会区分“公网已连通”“仅网关可达”和“不可达”。

## 日志与运行数据

默认数据目录：

```text
~/.eg25/
├── history.tsv
├── stats.env
├── stats.json
└── log/
```

- `history.tsv`：最近操作、耗时和恢复结果
- `stats.json`：累计运行及恢复统计
- `log/`：按日期保存命令日志

查看路径和当前环境：

```bash
eg25 info
```

查看最近 30 条操作：

```bash
eg25 history 30
```

## 升级

```bash
cd EG25-Toolkit
git fetch --tags
git checkout v3.3.1
./install.sh
```

安装脚本会重新部署程序，并迁移部分旧配置。升级前建议备份：

```text
/usr/local/lib/eg25-toolkit/config/eg25.conf
```

## 卸载

```bash
./uninstall.sh
```

卸载会删除：

```text
/usr/local/bin/eg25
/usr/local/lib/eg25-toolkit/
```

运行历史和日志仍会保留在 `~/.eg25`，如不再需要可手动删除。

## 项目结构

```text
EG25-Toolkit/
├── bin/          # eg25 命令入口
├── commands/     # 各子命令实现
├── config/       # 默认配置
├── lib/          # USB、VM、网络、AT、状态和日志模块
├── install.sh
└── uninstall.sh
```

## 使用边界

- 当前工具面向特定的 macOS + UTM Ubuntu + Quectel/Baiwang 工作流，并非通用蜂窝网络管理器。
- `eg25 mac` 和 `eg25 vohive` 会修改模组 USB 网络模式，并可能引起 USB 重新枚举。
- `eg25 repair` 和 `eg25 reset` 会通过 `AT+CFUN=1,1` 重启模组，执行期间蜂窝连接会暂时中断。
- 在不同硬件上使用前，请先确认 USB ID、AT 指令、端口布局和 QMI 驱动兼容性。

## 反馈与贡献

如果遇到问题，请在提交 Issue 时附上以下信息：

- macOS、UTM 和 Ubuntu 版本
- 模组型号及 `lsusb` 输出
- `eg25 version`、`eg25 doctor` 和 `eg25 status` 输出
- 相关的 VoHive 日志
- 可复现问题的操作步骤

项目地址：[dinga1981/EG25-Toolkit](https://github.com/dinga1981/EG25-Toolkit)

