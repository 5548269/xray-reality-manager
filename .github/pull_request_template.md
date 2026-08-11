## Summary

Describe what this Pull Request changes and why.

## Validation

- [ ] `bash -n install.sh`
- [ ] `bash -n install-release.sh`
- [ ] `bash tests/security_helpers_test.sh`
- [ ] ShellCheck was run on maintained scripts, or skipped checks are explained below.
- [ ] No credentials, private keys, UUIDs, IP addresses, or other sensitive data are included.
- [ ] Documentation and `CHANGELOG.md` were updated when behavior changed.

## Risk and rollback

Describe security impact, configuration-format changes, service disruption,
and how to undo the change safely.

## Test environment

List the operating system and the flows that were tested.

## Related Issue

Link the Issue this change addresses, if applicable.

If `install-release.sh` changed, link the immutable upstream commit and update
`docs/UPSTREAM.md`.
