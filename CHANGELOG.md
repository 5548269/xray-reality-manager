# 更新日志

本项目的重要变化将记录在此文件中。

## [Unreleased]

### Changed

- 将项目下载地址更新为 `xray-reality-manager`。
- 完善安装、安全、贡献、许可证及上游项目说明。
- 采用与上游 `XTLS/Xray-install` 兼容的 GPL-3.0 许可证。

## [2.0.12]

### Fixed

- 修复 Reality 密钥生成与解析问题，避免将 `Hash32` 错误识别为公钥。

### Added

- 支持 Xray 多端口和多用户管理。
- 支持直连与 SOCKS5 中转模式。
- 支持 HAProxy 配置生成、连接信息展示、备份恢复及 Geo 数据更新。
