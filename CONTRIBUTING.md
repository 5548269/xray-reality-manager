# 贡献指南

感谢你帮助改进 Xray Reality 多端口管理脚本。

## 提交问题

提交 Issue 前，请先搜索是否已有相同问题。报告问题时请说明：

- 操作系统及版本
- 脚本版本
- 执行的菜单操作或命令
- 实际结果与预期结果
- 已脱敏的相关日志

请勿提交 UUID、私钥、IP、密码、代理凭据或其他敏感信息。

## 提交代码

1. Fork 仓库并从 `main` 创建新分支。
2. 保持修改范围清晰，避免混入无关格式调整。
3. 对 Shell 脚本至少运行语法检查：

   ```bash
   bash -n install.sh
   bash -n install-release.sh
   ```

4. 如已安装 ShellCheck，请同时运行：

   ```bash
   shellcheck install.sh install-release.sh
   ```

5. 在 Pull Request 中说明修改目的、测试环境和验证结果。

涉及上游 `install-release.sh` 的变更时，请说明对应的 [XTLS/Xray-install](https://github.com/XTLS/Xray-install) 版本或提交。
