# Xray Reality Multi-Port Manager

**English** | [简体中文](README_zh-CN.md)

An interactive Xray management script for VLESS + Reality. It simplifies multi-port and multi-user configurations, direct connections, and SOCKS5 relay setups. The current script version is **2.0.13**.

## Features

- Install, reinstall, and uninstall Xray
- Create, view, edit, and delete multi-port configurations
- Generate UUIDs, Reality keys, Short IDs, and VLESS share links
- Configure a SOCKS5 relay independently for each port
- Install HAProxy and generate its configuration automatically
- Display connection information for configured ports
- Back up and restore configurations
- Update GeoIP and GeoSite data and view Xray logs

## Requirements

- Debian 10+ or Ubuntu 20.04+
- `root` privileges
- Network access to GitHub and the download sources required by Xray

Use a fresh server or a test environment whenever possible. This script installs packages and modifies system services and network-related configuration. Back up important data before running it.

## Installation

Download and review the script first:

```bash
curl -fL https://raw.githubusercontent.com/5548269/xray-reality-manager/main/install.sh -o install.sh
less install.sh
```

After reviewing it, run the script as `root`:

```bash
bash install.sh
```

Alternatively, launch it directly with a one-line command:

```bash
bash <(curl -fL https://raw.githubusercontent.com/5548269/xray-reality-manager/main/install.sh)
```

The script checks and installs its dependencies before opening the interactive management menu.

## Security

- Never run a remote script from an untrusted source without reviewing it.
- Protect generated UUIDs, private keys, proxy credentials, and backup files.
- Expose only the required ports and restrict management access with a firewall.
- Report security issues privately by following the [security policy](SECURITY.md).

## Upstream Project and Attribution

The bundled `install-release.sh` comes from [XTLS/Xray-install](https://github.com/XTLS/Xray-install) and is used to install and maintain Xray. The file retains its upstream project information and links.

This project continues the maintenance of a community script and fixes a Reality key generation and parsing issue that could incorrectly treat `Hash32` as a public key.

## Contributing

Read the [contribution guide](CONTRIBUTING.md) before opening an issue or submitting code. See [CHANGELOG.md](CHANGELOG.md) for notable changes.

Planned improvements are tracked in the public [roadmap](ROADMAP.md).

## Disclaimer

This project is intended only for lawful network administration, testing, and research. Users are responsible for complying with applicable laws and for any risks associated with running the script or modifying server configuration.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE), which is compatible with the license of the upstream `XTLS/Xray-install` project. Copyright in third-party components remains with their respective owners.
