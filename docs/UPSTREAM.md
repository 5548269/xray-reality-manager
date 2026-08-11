# Upstream Provenance

This repository vendors `install-release.sh` from the
[XTLS/Xray-install](https://github.com/XTLS/Xray-install) project.

## Verified source

| Field | Value |
| --- | --- |
| Local file | `install-release.sh` |
| Upstream repository | `XTLS/Xray-install` |
| Upstream revision | `e741a4f56d368afbb9e5be3361b40c4552d3710d` |
| Upstream file | [install-release.sh at the recorded revision](https://github.com/XTLS/Xray-install/blob/e741a4f56d368afbb9e5be3361b40c4552d3710d/install-release.sh) |
| Upstream Git blob | `e78442bfaed4a209e2c2e3f0a07acd6de5a4b2da` |
| SHA-256 with LF line endings | `7F70C95F6B418DA8B4F4883343D602964915E28748993870FD554383AFDBE555` |
| License | GNU General Public License v3.0 |
| Last verified | 2026-08-11 |

At the verification date, the local file content exactly matched the recorded
upstream Git blob and had no project-specific source changes. The upstream
file's executable mode (`100755`) is retained.

`install.sh` downloads this immutable upstream revision to a temporary file,
checks the SHA-256 value above, and executes it only after the check succeeds.
It does not execute the moving upstream `main` branch.

## Update procedure

1. Review changes in the official upstream repository.
2. Select an immutable upstream commit rather than the moving `main` branch.
3. Compare the downloaded file with the vendored copy.
4. Preserve the upstream header, attribution, license notices, and executable
   file mode.
5. Run `bash -n install-release.sh` and review the complete diff.
6. Update `INSTALL_RELEASE_REF` and `INSTALL_RELEASE_SHA256` in `install.sh`.
7. Update the revision, Git blob, SHA-256, and verification date in this file.
8. Submit the synchronization through a Pull Request and wait for CI.

## License and attribution

`install-release.sh` is redistributed under the upstream project's
[GNU General Public License v3.0](https://github.com/XTLS/Xray-install/blob/e741a4f56d368afbb9e5be3361b40c4552d3710d/LICENSE).
Copyright in the upstream file remains with its original contributors.

If this project modifies the vendored file in the future, the modification and
its date must be documented here. Modified versions must continue to be
distributed with corresponding source code under GPL-compatible terms.
