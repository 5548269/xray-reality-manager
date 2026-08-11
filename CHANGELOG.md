# 更新日志

本项目的重要变化将记录在此文件中。

## [Unreleased]

## [2.0.16] - 2026-08-11

### Added

- 记录 Ubuntu 22.04.5 LTS ARM64、Xray 26.3.27 的真实安装、端口创建、服务校验和客户端导入结果。

### Fixed

- 全新安装时先创建不含密钥和监听端口的有效初始配置，避免上游安装器在正式端口配置生成前因缺少 `config.json` 连续启动失败。

## [2.0.15] - 2026-08-11

### Fixed

- 兼容 Xray `v26.3.27` 将 Reality 公钥标签输出为 `Password (PublicKey)` 的格式，修复添加端口时自动生成密钥失败并退出的问题。

## [2.0.14] - 2026-08-11

### Added

- 增加安全回归测试，覆盖本地 UUID 生成、备份归档路径穿越和符号链接检查。
- 增加可复现发布工作流，为每个正式版本发布脚本及 `SHA256SUMS`。
- 增加上游来源、发布流程、维护者职责、CODEOWNERS 和 Dependabot 配置。

### Changed

- 固定并校验官方 `XTLS/Xray-install` 辅助脚本，不再以 root 权限执行可变的 `main` 分支内容。
- 将 `install-release.sh` 同步到官方提交 `e741a4f`，并记录 Git blob 和 SHA-256。
- UUID 改为完全在本机生成；Geo 数据回退下载改为完成后再替换线上文件。
- 兼容新版 Xray 使用 `Password` 表示 Reality 客户端公钥的输出格式，并明确拒绝将 `Hash32` 当作公钥。
- README 改为优先使用带校验值的正式版本安装方式，并明确脚本的高权限修改范围。

### Security

- 修复修改 UUID 时可由 UUID 推导 Reality 私钥的问题，改为独立随机生成密钥。
- 私钥输入不再回显，私钥也不再输出到终端或失败日志。
- Xray 配置权限限制为 root 与实际服务组可读，不再默认对所有本机用户开放。
- Geo 数据回退下载增加上游 SHA-256 校验，并在成对替换失败时回滚。
- 备份目录和归档改为所有者专用权限；恢复使用私有快照，并拒绝路径穿越、链接、特殊文件和无效配置。

## [2.0.13] - 2026-08-11

### Added

- 提供英文和简体中文 README，并在两个版本之间加入语言切换链接。
- 添加社区行为准则、支持说明、项目路线图、Issue/PR 模板及自动 Shell 检查。

### Changed

- 将项目下载地址更新为 `xray-reality-manager`。
- 完善安装、安全、贡献、许可证及上游项目说明。
- 采用与上游 `XTLS/Xray-install` 兼容的 GPL-3.0 许可证。
- SOCKS5 密码输入不再回显，并要求提供非空用户名和密码。

### Fixed

- 移除已删除二维码功能遗留的 `qrencode` 依赖和帮助文字。
- 移除固定及不安全的默认 SOCKS5 认证凭据。

## 2.0.12

### Fixed

- 修复 Reality 密钥生成与解析问题，避免将 `Hash32` 错误识别为公钥。

### Added

- 支持 Xray 多端口和多用户管理。
- 支持直连与 SOCKS5 中转模式。
- 支持 HAProxy 配置生成、连接信息展示、备份恢复及 Geo 数据更新。

[Unreleased]: https://github.com/5548269/xray-reality-manager/compare/v2.0.16...HEAD
[2.0.16]: https://github.com/5548269/xray-reality-manager/compare/v2.0.15...v2.0.16
[2.0.15]: https://github.com/5548269/xray-reality-manager/compare/v2.0.14...v2.0.15
[2.0.14]: https://github.com/5548269/xray-reality-manager/compare/v2.0.13...v2.0.14
[2.0.13]: https://github.com/5548269/xray-reality-manager/releases/tag/v2.0.13
