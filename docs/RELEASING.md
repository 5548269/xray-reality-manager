# Release Process / 发布流程

Releases are created from reviewed commits on `main`. The release tag, script
version, changelog, and downloadable checksums must agree.

发布版本应来自 `main` 上已经审查的提交。版本标签、脚本版本、更新日志和下载校验值必须一致。

## Checklist

1. Update `VERSION` in `install.sh`.
2. Update both README files and `CHANGELOG.md`.
3. If `install-release.sh` changed, update [UPSTREAM.md](UPSTREAM.md) and the
   pinned revision and SHA-256 values in `install.sh`.
4. Run the same checks used by CI:

   ```bash
   bash -n install.sh
   bash -n install-release.sh
   bash -n tests/security_helpers_test.sh
   shellcheck --severity=error install.sh tests/security_helpers_test.sh
   bash tests/security_helpers_test.sh
   ```

5. Merge the Pull Request only after CI succeeds.
6. Create a signed or annotated `vX.Y.Z` tag matching `VERSION` and push it.
7. The release workflow verifies the version, reruns the checks, generates
   `SHA256SUMS`, and publishes both scripts as GitHub Release assets.
8. Download the published assets once and verify `SHA256SUMS`.
9. Confirm that the Release page and both README installation instructions are
   correct.

Do not move an existing release tag. Publish a new patch version if a release
needs correction.

不要移动已经发布的版本标签。如需修正已发布版本，请创建新的补丁版本。
