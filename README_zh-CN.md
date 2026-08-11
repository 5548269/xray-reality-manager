# Xray Reality 多端口管理脚本

[English](README.md) | **简体中文**

一个面向 VLESS + Reality 的交互式 Xray 管理脚本，用于简化多端口、多用户、直连及 SOCKS5 中转配置。当前脚本版本为 **2.0.13**。

## 主要功能

- 安装、重装及卸载 Xray
- 创建、查看、修改和删除多端口配置
- 自动生成 UUID、Reality 密钥、Short ID 和 VLESS 分享链接
- 为不同端口配置 SOCKS5 中转
- 自动安装并生成 HAProxy 配置
- 显示已配置端口的连接信息
- 备份和恢复配置
- 更新 GeoIP、GeoSite 数据并查看 Xray 日志

## 环境要求

- Debian 10+ 或 Ubuntu 20.04+
- `root` 权限
- 能够访问 GitHub 及 Xray 所需的下载源

建议优先在全新服务器或测试环境中使用。脚本会安装软件、修改系统服务和网络相关配置，请先备份重要数据。

## 安装与使用

先下载并审查脚本内容：

```bash
curl -fL https://raw.githubusercontent.com/5548269/xray-reality-manager/main/install.sh -o install.sh
less install.sh
```

确认无误后，以 `root` 用户运行：

```bash
bash install.sh
```

也可以使用一行命令直接启动：

```bash
bash <(curl -fL https://raw.githubusercontent.com/5548269/xray-reality-manager/main/install.sh)
```

脚本会检查并安装所需依赖，然后显示交互式管理菜单。

## 安全提示

- 不要在未审查内容的情况下运行来源不明的远程脚本。
- 妥善保管脚本生成的 UUID、私钥、代理凭据和备份文件。
- 建议仅开放必要端口，并通过防火墙限制管理入口。
- 安全问题请按照 [安全策略](SECURITY.md) 私下报告。

## 上游项目与说明

仓库内的 `install-release.sh` 来自 [XTLS/Xray-install](https://github.com/XTLS/Xray-install)，用于安装和维护 Xray。该文件保留了上游项目说明及链接。

本项目基于社区脚本继续维护，并修复了 Reality 密钥生成与解析问题，避免在部分情况下错误地将 `Hash32` 当作公钥。

## 参与贡献

提交问题或代码前，请阅读 [贡献指南](CONTRIBUTING.md)。版本变化记录见 [CHANGELOG.md](CHANGELOG.md)。

计划中的改进记录在公开的 [项目路线图](ROADMAP.md) 中。

## 免责声明

本项目仅供合法的网络管理、测试和研究使用。使用者应自行遵守所在地区的法律法规，并承担运行脚本及修改服务器配置产生的风险。

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE)，与上游 `XTLS/Xray-install` 的许可证保持兼容。第三方组件的版权仍归其各自权利人所有。
