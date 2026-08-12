# Mac 4G Toolkit Setup Guide

适用于：
- Apple Silicon Mac (M系列)
- DJI 4G模块
- Baiwang / Quectel EG25系列模组
- DJOneHub
- EG25 Toolkit


# 1. 系统环境

## Homebrew

安装：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

配置：
echo 'eval "$(/opt/homebrew/bin/brew shellenv bash)"' >> ~/.bash_profile

eval "$(/opt/homebrew/bin/brew shellenv bash)"
验证：
brew --version
2. 安装依赖
brew install go
brew install libusb
brew install pkg-config
检查：
go version

pkg-config --modversion libusb-1.0
3. 安装 DJOneHub
下载：
git clone git@github.com:dinga1981/DJOneHub-mac-enhanced.git
进入：
cd DJOneHub-mac-enhanced
切换稳定版本：
git checkout v0.1.7-2c7c
编译：
go test ./cmd/djonehub-macos

go build \
-o build-local/djonehub-macos \
./cmd/djonehub-macos
安装：
sudo install -m 755 \
build-local/djonehub-macos \
/usr/local/libexec/djonehub/bin/djonehub-macos
启动：
/usr/local/libexec/djonehub/bin/djonehub-macos
访问：
http://127.0.0.1:7575
4. 安装 EG25 Toolkit
下载：
git clone git@github.com:dinga1981/EG25-Toolkit.git
进入：
cd EG25-Toolkit
切换版本：
git checkout v3.3.2
安装：
chmod +x install.sh uninstall.sh bin/eg25

./install.sh
检查：
eg25 doctor

eg25 status
5. SSH配置
GitHub SSH：
检查：
ssh -T git@github.com
成功：
Hi dinga1981! You've successfully authenticated
6. DJI 4G模块使用流程
启动DJOneHub：
djonehub
浏览器：
http://127.0.0.1:7575
模式：
ECM模式：
macOS直接使用4G网络

VoHive模式：
UTM Ubuntu + VoHive

7. 重装系统恢复顺序
安装 Homebrew

安装 Go/libusb/pkg-config

配置 GitHub SSH

下载 DJOneHub

checkout 稳定tag

下载 EG25 Toolkit

checkout 稳定tag

运行安装脚本

当前稳定版本
DJOneHub:
v0.1.7-2c7c
EG25 Toolkit:
v3.3.2
