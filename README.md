# EasyOpenVPN

<p align="center">
  <img src="preview.png" alt="EasyOpenVPN Panel" width="422" />
</p>

EasyOpenVPN is a lightweight, secure Omarchy bar widget for managing and running OpenVPN connections directly from the Omarchy desktop shell. It provides a compact status icon, a full-featured profile manager, saved credentials, direct connect/disconnect controls, automatic kill-switch protection, and recent OpenVPN log output.

The plugin is intentionally focused: it does not require NetworkManager VPN plugins or systemd services. It is built for users who already have `.ovpn` or `.conf` files and want a streamlined, theme-aware bar widget with reliable connection status and instant leak protection.

---

## Features

- **Profile Management**:
  - Add `.ovpn` or `.conf` configuration files with multi-selection file picker (**Add Profile**).
  - Select a folder to batch import all OpenVPN configuration files contained inside (**Open Folder**).
  - **Drag-and-Drop Reordering**: Press and hold any profile to drag and reorder; custom order is automatically saved across restarts.
  - **Multi-Selection & Batch Delete**: Select individual profiles with checkboxes or click **Select All**, then remove them with **Delete**.
  - **Quick Single-Profile Delete**: Per-profile trash icon with two-step click-to-confirm safety.
  - Profiles and settings persist across restarts under `~/.local/state`.

- **Profile-Specific Credentials**:
  - Store VPN username and password per configuration file (**Save for Profile**).
  - Credentials automatically switch when selecting different profiles.
  - Credentials files are stored with restricted private permissions (`0600`).

- **Accurate Connection State**:
  - Distinguishes between **Connecting…** (during TLS handshake) and **Connected**.
  - Only transitions to **Connected** once OpenVPN logs `Initialization Sequence Completed` and the tunnel device receives an IPv4 address.
  - Automatic connection timeout: aborts attempts taking longer than 9 seconds without tripping the kill switch.
  - Cancel pending connections at any time with a single click.

- **Integrated Kill Switch**:
  - Privileged background guard monitors the OpenVPN process, the tunnel device, and runtime logs.
  - If an established VPN connection drops unexpectedly, it instantly deploys an isolated `nftables` table (`inet simpleopenvpn`) dropping all non-loopback network traffic to prevent IP or DNS leaks.
  - In-panel alert: **Kill switch • network blocked**, reporting the failure reason and providing a **Restore Network** button.
  - Unblocking only happens by explicit user action; network is never silently restored behind the scenes.

- **Seamless Direct & Passwordless Connect**:
  - Connect and disconnect directly via the toggle switch in the panel header without repeated password prompts once configured.
  - Right-clicking the status bar icon disconnects immediately.
  - Optional one-time helper (`sudo ./setup-passwordless.sh`) authorizes a restricted Polkit rule.

- **Diagnostics & Theming**:
  - Embedded monospace log view showing recent OpenVPN output directly in the panel, safely rendered as plain text.
  - Themed OpenVPN icon in both the status bar and panel, automatically matching your active Omarchy theme colors.
  - Polished layout with hover highlighting and balanced spacing.
  - Centered version indicator (`v 0.1`) at the bottom margin linking directly to the project repository.

---

## Requirements

EasyOpenVPN is designed for Omarchy and its Quickshell-based desktop shell.

All runtime dependencies (`openvpn`, `jq`, `zenity`, `python`, `nftables`) are included directly in the integrated installation command below, so you do not need to run a separate command for requirements.

---

## Installation

### Via Omarchy CLI (Recommended)

Run the integrated command to install all required packages, add the plugin, and enable it in one step:

```sh
omarchy pkg add openvpn jq zenity python nftables && omarchy plugin add https://github.com/kanpianer/EasyOpenVPN.git --enable
```

Place the widget in the desired bar section (e.g. right side):

```sh
omarchy bar move io.github.kanpianer.easy-openvpn --section right
```

### From Local Source

Clone the repository and run the installer, which automatically handles dependencies and registers the plugin:

```sh
./install.sh
```

---

## Usage

1. **Open the Panel**: Click the EasyOpenVPN icon in the Omarchy status bar.
2. **Add Profiles**: Click **Add Profile** to select one or multiple `.ovpn` or `.conf` files. Click **Open Folder** to select a folder and batch import all OpenVPN configuration files contained inside.
3. **Reorder Profiles**: Long-press (press and hold) a profile row and drag it to your preferred position in the list.
4. **Manage Profiles**: Use the checkboxes to select profiles and click **Delete** (or click the individual trash icon) to remove profiles.
5. **Set Credentials**: If your VPN requires authentication, enter your username and password, then click **Save for Profile**.
6. **Connect**: Toggle the switch in the panel header to connect directly. Toggle it again to disconnect.
7. **Quick Control**: Right-clicking the bar icon disconnects immediately.

---

## Passwordless Connect (Recommended)

By default, connecting uses `pkexec`, prompting for your account password via the Omarchy Polkit dialog. To connect and disconnect directly from the panel toggle without entering your password, run the one-time helper script in a terminal:

```sh
sudo ./setup-passwordless.sh
```

The script installs a root-owned copy of the control script under `/usr/local/lib/simpleopenvpn` and a narrow Polkit rule authorizing **only** that exact program for `connect` and `disconnect`. The rule does not permit running arbitrary commands as root.

To remove the passwordless rule at any time:

```sh
sudo ./setup-passwordless.sh --remove
```

---

## Connection State & Kill Switch

### Handshake & Timeout

The bar and panel only display **Connected** after OpenVPN completes its TLS handshake (`Initialization Sequence Completed`) and the virtual interface has an IPv4 address. If the handshake does not complete within 9 seconds (e.g., unreachable server or wrong credentials), the attempt is aborted and the network remains untouched.

### Kill Switch Protection

When a connection is established, a privileged watchdog monitors the tunnel. If the server drops the connection, the tunnel interface is deleted, or the OpenVPN process dies unexpectedly, the guard:

1. Installs a dedicated `nftables` table (`inet simpleopenvpn`) that drops all incoming, outgoing, and forwarded traffic except loopback (`lo`).
2. Terminates OpenVPN.
3. Notifies the user with a **Kill switch • network blocked** status and displays a **Restore Network** button.

The firewall rules are removed only when the user explicitly clicks **Restore Network**, turns off the switch, or disconnects from the bar icon.

---

## Security Model

EasyOpenVPN is designed following security hardening practices:

- **Unprivileged Desktop Host**: The UI and state management run inside the desktop user's Quickshell session. Privileged actions are delegated strictly through `pkexec` or the optional locked Polkit helper.
- **Credential Safety**: VPN credentials are never passed via process command-line arguments (`argv`). Instead, private descriptor-relative mechanisms and strict file permissions (`0600`) are used.
- **Immutable Snapshot & TOCTOU Elimination**: User-supplied OpenVPN profiles are snapshotted into an immutable, root-owned descriptor (sealed `memfd` with write seals `F_SEAL_WRITE` / `O_TMPFILE`) before directive inspection. The mutable user descriptor is closed immediately, and validation is performed directly on the sealed snapshot passed to root OpenVPN, completely preventing in-place rewrite races (TOCTOU) from injecting forbidden directives (such as `plugin`).
- **Path & Directive Hardening**: OpenVPN profiles are inspected with `O_NOFOLLOW` checks. Dangerous directives that could trigger arbitrary code execution or hook into system processes (such as `plugin`, nested `config`, `iproute`, management sockets, and custom script hooks) are rejected.
- **Log Sanitization & Safe Rendering**: Recent OpenVPN logs are strictly rendered as `Text.PlainText`, preventing server-controlled log strings (such as `AUTH_FAILED`) from injecting rich text or triggering unauthorized network requests via HTML/image tags.
- **Firewall Isolation**: The kill switch uses an independent `inet simpleopenvpn` nftables table. Existing system firewall configurations (e.g., UFW) are left untouched.

---

## Removal

To disable and remove the plugin from Omarchy:

```sh
omarchy plugin remove io.github.kanpianer.easy-openvpn
```

If you configured the optional passwordless helper, remove it with:

```sh
sudo ./setup-passwordless.sh --remove
```

---

## Marketplace Metadata

For reference when submitting to the [Omarchy Plugin Marketplace](https://plugins.omarchy.org/):

- **ID**: `io.github.kanpianer.easy-openvpn`
- **Repository**: `https://github.com/kanpianer/EasyOpenVPN`
- **Category**: `Widgets`
- **Tags**: `VPN`, `Bar`, `Quickshell`
- **Preview Asset**: `preview.png`

---

## Credits & Acknowledgments

- **Original Author**: [Diogo Carvalho](https://github.com/diogogc) ([diogogc/simple-openvpn](https://github.com/diogogc/simple-openvpn)) for creating SimpleOpenVPN and providing its solid foundation.
- **Security Hardening**: Security review and hardening recommendations provided by [HANCORE-linux](https://github.com/HANCORE-linux).

---

## License

This project is licensed under the [MIT License](LICENSE).
