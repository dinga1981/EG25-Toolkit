# EG25 Toolkit v3.3.1

适用于 macOS + UTM Ubuntu + Quectel/Baiwang 模组，在以下模式间切换：

- macOS ECM：Mac 原生使用 4G 网络
- VM QMI / VoHive：模组接入 Ubuntu VM，由 VoHive 使用

## 安装

```bash
cd eg25-toolkit-v3.3.1
chmod +x install.sh uninstall.sh bin/eg25
./install.sh
```

安装程序会读取 V2 的配置并迁移仍适用的参数，同时删除指向 V2 的旧命令软链接，避免误运行旧代码。

## 首次检查

```bash
eg25 doctor
eg25 status
```

## 核心命令

```bash
eg25 mac
eg25 vohive
eg25 repair
eg25 status
eg25 at 'AT+CSQ'
eg25 doctor
```

## V3.0 的关键变化

1. 只有一个入口 `eg25`。
2. 不固定 `en9` 或 `/dev/ttyUSB2`。
3. AT 指令通过 Base64 传参，避免 SSH 多层引号错误。
4. AT 端口由远端 Python 3 逐个探测，不依赖 VM 内的 `eg25-at.sh`。
5. 所有等待函数都校验参数，不再触发 V2 的 unbound variable。
6. 模式切换后验证 ECM IPv4、QMI 设备及 VoHive 状态。
7. 日志位于 `~/Library/Logs/eg25-toolkit/`。

## VM 前提

- SSH 密钥免密登录
- `sudo -n true` 成功
- 安装 `python3`、`usbutils`
- VoHive systemd 服务名为 `vohive`

Ubuntu 可执行：

```bash
sudo apt update
sudo apt install -y python3 usbutils
sudo usermod -aG dialout "$USER"
```

修改用户组后需要重新登录 VM。V3 的 AT 探测默认通过 `sudo -n python3` 访问串口，因此关键要求仍是 sudo 免密。

## 配置

安装后配置文件：

```text
/usr/local/lib/eg25-toolkit/config/eg25.conf
```

默认值已经按当前环境设置：

- VM 用户：liu
- VM 地址：192.168.64.2
- VM 名称：Linux
- USB ID：2c7c:0125
- macOS 硬件端口：Baiwang

## V3.1.1 稳定性修正

- 4G 主连通性判断改为从 ECM IPv4 指定源地址 ping `1.1.1.1`，不再把第三方 HTTPS 查询失败误判为断网。
- 公网 IP 查询降级为附加验证；失败时仍可判定 4G 数据链路已连通。
- Doctor 在 macOS ECM 模式下将 VM USB、ttyUSB、cdc-wdm0 显示为 N/A。
- VoHive 状态细分为 `operational`、`idle`、`inactive`。
- 已处于 ECM 模式时，`eg25 mac` 会停止 VM 中仍在空转的 VoHive 服务。

## V3.1.1 AT 探测修复

针对部分 QDC507/EC25 USB 接口在 UTM 中打开 `/dev/ttyUSB0` 或 `/dev/ttyUSB1` 时发生底层阻塞的问题：

- 优先探测 Baiwang `if02`、`ttyUSB2`、`if03`、`ttyUSB3`。
- 每个端口由独立 Python 子进程负责。
- 单端口整个探测过程默认最多 4 秒，包括打开、termios 初始化、写入和读取。
- 阻塞端口会被强制结束，不会再卡住 `eg25 vohive`。
- 可在 `config/eg25.conf` 中通过 `AT_PROBE_TIMEOUT` 调整单端口超时。


## V3.1.2 优化

- HTTPS 验证改用 Cloudflare `1.1.1.1/cdn-cgi/trace` 为首选，`api.ipify.org` 与 `icanhazip.com` 作为备用。
- 状态页可显示公网 IPv4、出口地区和 Cloudflare 节点。
- QMI 切换后的 USB 重枚举会持续自动重试 90 秒；UTM 需要手动勾选 USB 时，无需退出或重新执行命令。
- 等待 AT 端口期间不再反复输出中间失败日志；仅在最终超时时显示最后一次诊断。
- USB 模式指令成功只表示模组接受配置，实际模式以 ECM 接口或 `/dev/cdc-wdm0` 最终确认。


## V3.2 新功能

- `eg25 vohive` 不再以“服务已启动”作为成功标准，必须确认 `wwan0` 已获得 IPv4。
- 自动识别 VoHive 日志中的 `call end type=2 code=241`。
- 检测到 code 241 时，自动停止 VoHive、执行一次 `AT+CFUN=1,1`、等待 USB/QMI 重新枚举、重新启动 VoHive并验证数据连接。
- 新增 `eg25 repair`，用于修复 QMI 模式下 `wwan0` 无地址或 code 241。
- 首次自动接入 UTM 失败时会继续等待用户手动选择 USB，无需退出后重跑。
- `eg25 status` 增加 USB 当前归属、`wwan0` IPv4 和 VoHive 公网出口。
- 自动恢复只执行一次，避免模组陷入无限重启循环。

## V3.3 事务式切换

- `eg25 vohive` 全程阻塞执行，直到 `wwan0` 获得 IPv4 或确认失败。
- 首轮等待无 IPv4 时，不再依赖日志是否出现 code 241，直接执行一次受控恢复。
- 受控恢复流程：停止 VoHive → `AT+CFUN=1,1` → 等待 USB/QMI 重枚举 → 重启 VoHive → 再次验证 `wwan0`。
- 自动恢复最多一次，避免循环重启。
- `eg25 repair`：当前 QMI 模式无 IPv4时执行一次受控恢复。
- `eg25 health`：检查 VM、USB、QMI、VoHive、wwan0 和公网出口。
- `eg25 reset`：强制执行一次 CFUN 重启并恢复 QMI 数据连接。


## V3.3.1 维护版

- 保持 v3.3 的 ECM/QMI 事务式切换和 CFUN 自动恢复流程不变。
- 新增 `eg25 info`，显示安装路径、配置、数据目录、VM 和 VoHive 地址。
- 新增 `eg25 history [条数]`，显示最近切换、耗时、结果和自动恢复统计。
- 运行数据统一保存在 `~/.eg25/`，包括日志、历史记录和 `stats.json`。
- `eg25 health` 在当前状态 READY 时，不再把已经成功恢复的历史 code 241 误报为当前故障。
- `mac`、`vohive`、`repair` 和 `reset` 会自动记录成功/失败、耗时及恢复结果。
- 安装程序会显示版本、命令位置、程序目录和数据目录，并自动验证版本。
