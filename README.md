# Xray Reality Multi-Port Manager

**English** | [简体中文](README_zh-CN.md)

[![Shell validation](https://github.com/5548269/xray-reality-manager/actions/workflows/shell-check.yml/badge.svg)](https://github.com/5548269/xray-reality-manager/actions/workflows/shell-check.yml)
[![Latest release](https://img.shields.io/github/v/release/5548269/xray-reality-manager)](https://github.com/5548269/xray-reality-manager/releases/latest)
[![License: GPL-3.0](https://img.shields.io/github/license/5548269/xray-reality-manager)](LICENSE)

An interactive Bash manager for Xray VLESS + Reality deployments. It turns
multi-port, multi-user, SOCKS5 relay, HAProxy, backup, and recovery tasks into
a guided workflow for Linux server administrators. The current stable release
is **v2.0.15**.

## Why this project

Maintaining several Xray inbounds by hand requires coordinated edits across
JSON configuration, Reality keys, systemd services, relay settings, and
firewall-facing ports. This project keeps those operations in one auditable
script while retaining per-port connection information for later maintenance.

## Features

- Install, reinstall, and uninstall Xray
- Create, view, edit, and delete multi-port configurations
- Generate UUIDs, Reality keys, Short IDs, and VLESS share links
- Configure a SOCKS5 relay independently for each port
- Install HAProxy and generate its configuration automatically
- Display connection information for configured ports
- Back up and restore configurations
- Update GeoIP and GeoSite data and view Xray logs

## System changes

The script runs with elevated privileges and may install packages, manage
`xray` and `haproxy` services, and write to:

- `/usr/local/bin/xray` and `/usr/local/etc/xray/`
- `/etc/systemd/system/` and `/etc/haproxy/haproxy.cfg`
- `$HOME/.xray_port_info.json` and `$HOME/.xray_management.log`
- `$HOME/xray_backup_*.tar.gz`

Review the script and back up important server data before use.

## Requirements

- Target platforms: Debian 10+ and Ubuntu 20.04+
- `root` privileges
- Network access to GitHub and the download sources required by Xray

Cross-version installation testing is tracked in
[Issue #1](https://github.com/5548269/xray-reality-manager/issues/1).
Until each environment is verified, use a fresh server or test environment
whenever possible.

## Installation

### Verified release (recommended)

Download the release script and its published checksum:

```bash
VERSION=v2.0.15
curl -fLO "https://github.com/5548269/xray-reality-manager/releases/download/${VERSION}/install.sh"
curl -fLO "https://github.com/5548269/xray-reality-manager/releases/download/${VERSION}/SHA256SUMS"
grep '  install.sh$' SHA256SUMS | sha256sum -c -
less install.sh
```

After reviewing it, run the script as `root`:

```bash
bash install.sh
```

### Development version

The `main` branch contains the latest development changes and may differ from
the current release. Download it only when testing or reviewing unreleased
work.

## Security

- Never run a remote script from an untrusted source without reviewing it.
- Protect generated UUIDs, private keys, proxy credentials, and backup files.
- Expose only the required ports and restrict management access with a firewall.
- UUIDs are generated locally; Reality private keys are not printed to the terminal.
- Xray configuration containing private keys is limited to root and the effective service group.
- The XTLS installer is pinned to an immutable upstream commit and verified with SHA-256 before execution.
- Geo fallback downloads are checked against upstream SHA-256 files before replacement.
- Backup archives use owner-only permissions and a locked snapshot is checked before restoration.
- Report security issues privately by following the [security policy](SECURITY.md).

## Upstream Project and Attribution

The bundled `install-release.sh` comes from [XTLS/Xray-install](https://github.com/XTLS/Xray-install) and is used to install and maintain Xray. Its exact upstream revision, Git blob, checksum, and synchronization process are recorded in [docs/UPSTREAM.md](docs/UPSTREAM.md).

This project continues the maintenance of a community script and fixes a Reality key generation and parsing issue that could incorrectly treat `Hash32` as a public key.

## Contributing

Read the [contribution guide](CONTRIBUTING.md) before opening an issue or submitting code. See [CHANGELOG.md](CHANGELOG.md) for notable changes and [docs/RELEASING.md](docs/RELEASING.md) for the reproducible release process.

Planned improvements are tracked in the public [roadmap](ROADMAP.md) and
[Issue tracker](https://github.com/5548269/xray-reality-manager/issues).
Usage questions can be posted in
[GitHub Discussions](https://github.com/5548269/xray-reality-manager/discussions).
Maintainer responsibilities are listed in [MAINTAINERS.md](MAINTAINERS.md).

## Disclaimer

This project is intended only for lawful network administration, testing, and research. Users are responsible for complying with applicable laws and for any risks associated with running the script or modifying server configuration.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE), which is compatible with the license of the upstream `XTLS/Xray-install` project. Copyright in third-party components remains with their respective owners.
