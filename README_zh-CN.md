# Xray Reality 多端口管理脚本

[English](README.md) | **简体中文**

[![Shell validation](https://github.com/5548269/xray-reality-manager/actions/workflows/shell-check.yml/badge.svg)](https://github.com/5548269/xray-reality-manager/actions/workflows/shell-check.yml)
[![Latest release](https://img.shields.io/github/v/release/5548269/xray-reality-manager)](https://github.com/5548269/xray-reality-manager/releases/latest)
[![License: GPL-3.0](https://img.shields.io/github/license/5548269/xray-reality-manager)](LICENSE)

一个面向 Xray VLESS + Reality 部署的交互式 Bash 管理工具。它把多端口、多用户、SOCKS5
中转、HAProxy、备份和恢复等操作整理成适合 Linux 服务器管理员使用的引导流程。
当前稳定版本为 **v2.0.14**。

## 为什么维护这个项目

手工维护多个 Xray 入站配置，需要同时处理 JSON 配置、Reality 密钥、systemd 服务、
中转设置及对外端口。本项目把这些操作集中在一个可审查的脚本中，并保存每个端口的
连接信息，便于后续维护。

## 主要功能

- 安装、重装及卸载 Xray
- 创建、查看、修改和删除多端口配置
- 自动生成 UUID、Reality 密钥、Short ID 和 VLESS 分享链接
- 为不同端口配置 SOCKS5 中转
- 自动安装并生成 HAProxy 配置
- 显示已配置端口的连接信息
- 备份和恢复配置
- 更新 GeoIP、GeoSite 数据并查看 Xray 日志

## 脚本会修改什么

脚本以高权限运行，可能安装软件包、管理 `xray` 和 `haproxy` 服务，并写入：

- `/usr/local/bin/xray` 与 `/usr/local/etc/xray/`
- `/etc/systemd/system/` 与 `/etc/haproxy/haproxy.cfg`
- `$HOME/.xray_port_info.json` 与 `$HOME/.xray_management.log`
- `$HOME/xray_backup_*.tar.gz`

使用前请审查脚本，并备份服务器上的重要数据。

## 环境要求

- 目标平台：Debian 10+、Ubuntu 20.04+
- `root` 权限
- 能够访问 GitHub 及 Xray 所需的下载源

不同系统版本的安装验证记录在
[Issue #1](https://github.com/5548269/xray-reality-manager/issues/1)。
在每个环境完成验证前，建议优先使用全新服务器或测试环境。

## 安装与使用

### 使用已校验的正式版本（推荐）

下载正式版本脚本及其公开校验值：

```bash
VERSION=v2.0.14
curl -fLO "https://github.com/5548269/xray-reality-manager/releases/download/${VERSION}/install.sh"
curl -fLO "https://github.com/5548269/xray-reality-manager/releases/download/${VERSION}/SHA256SUMS"
grep '  install.sh$' SHA256SUMS | sha256sum -c -
less install.sh
```

确认无误后，以 `root` 用户运行：

```bash
bash install.sh
```

### 开发版本

`main` 分支包含尚未发布的最新改动，可能与当前正式版本不同。只有在测试或审查
未发布功能时才建议下载该分支。

## 安全提示

- 不要在未审查内容的情况下运行来源不明的远程脚本。
- 妥善保管脚本生成的 UUID、私钥、代理凭据和备份文件。
- 建议仅开放必要端口，并通过防火墙限制管理入口。
- UUID 在本机生成；Reality 私钥不会显示在终端。
- 包含私钥的 Xray 配置只允许 root 和实际服务组读取。
- XTLS 安装脚本固定到不可变的上游提交，并在执行前校验 SHA-256。
- Geo 数据回退下载会先核对上游 SHA-256，再替换线上文件。
- 备份归档仅允许所有者读取，恢复时会锁定副本并拒绝危险路径和链接。
- 安全问题请按照 [安全策略](SECURITY.md) 私下报告。

## 上游项目与说明

仓库内的 `install-release.sh` 来自 [XTLS/Xray-install](https://github.com/XTLS/Xray-install)，用于安装和维护 Xray。准确的上游提交、Git blob、SHA-256 及同步流程记录在 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

本项目基于社区脚本继续维护，并修复了 Reality 密钥生成与解析问题，避免在部分情况下错误地将 `Hash32` 当作公钥。

## 参与贡献

提交问题或代码前，请阅读 [贡献指南](CONTRIBUTING.md)。版本变化记录见
[CHANGELOG.md](CHANGELOG.md)，可复现发布流程见
[docs/RELEASING.md](docs/RELEASING.md)。

计划中的改进记录在公开的 [项目路线图](ROADMAP.md) 和
[Issue 列表](https://github.com/5548269/xray-reality-manager/issues) 中。
使用问题可以在
[GitHub Discussions](https://github.com/5548269/xray-reality-manager/discussions)
提出。维护职责见 [MAINTAINERS.md](MAINTAINERS.md)。

## 免责声明

本项目仅供合法的网络管理、测试和研究使用。使用者应自行遵守所在地区的法律法规，并承担运行脚本及修改服务器配置产生的风险。

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE)，与上游 `XTLS/Xray-install` 的许可证保持兼容。第三方组件的版权仍归其各自权利人所有。
