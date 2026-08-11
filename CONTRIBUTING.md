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
   bash -n tests/security_helpers_test.sh
   ```

4. 如已安装 ShellCheck，请同时运行：

   ```bash
   shellcheck --severity=error install.sh tests/security_helpers_test.sh
   bash tests/security_helpers_test.sh
   ```

   `install-release.sh` 保持与上游一致，因此只对它执行语法检查；其来源和同步步骤见
   [docs/UPSTREAM.md](docs/UPSTREAM.md)。

5. 在 Pull Request 中说明修改目的、测试环境、风险、回滚方法和验证结果。

涉及上游 `install-release.sh` 的变更时，请按照
[上游同步流程](docs/UPSTREAM.md)记录对应的提交和校验值。

正式发布流程记录在 [docs/RELEASING.md](docs/RELEASING.md)。
