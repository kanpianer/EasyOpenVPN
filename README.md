# EasyOpenVPN

<p align="center">
  <img src="preview.png" alt="EasyOpenVPN Panel" width="422" />
</p>

EasyOpenVPN is a lightweight Omarchy bar widget for managing and running OpenVPN connections directly from the Omarchy desktop shell. It provides a compact status icon, a full-featured profile manager, saved credentials, direct connect/disconnect controls, automatic kill-switch protection, and recent OpenVPN log output.

The plugin is intentionally focused: it does not require NetworkManager VPN plugins or systemd services. It is built for users who already have `.ovpn` or `.conf` files and want a streamlined, theme-aware bar widget with reliable connection status and instant leak protection.

---

## Features

- **Profile Management**:
  - Add `.ovpn` or `.conf` configuration files with multi-selection file picker (**Add Profile**).
  - Select a folder to batch import all OpenVPN configuration files contained inside (**Open Folder**).
  - **Drag-and-Drop Reordering**: Press and hold any profile to drag and reorder; custom order is automatically saved across restarts.
  - **Multi-Selection & Batch Delete**: Select individual profiles with checkboxes or click **Select All**, then remove them with **Delete**.
  - **Quick Single-Profile Delete**: Per-profile trash icon with two-step click-to-confirm safety.
  - **Non-destructive Removal**: Delete removes entries from the plugin list only. Local `.ovpn`/`.conf` files and saved credentials are retained; use **Add Profile** or **Open Folder** to import them again.
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
  - Automatically prompts for authorization via Polkit upon first use after installation, or configure manually with `sudo ./setup-passwordless.sh`.
  - Decline authorization anytime if you prefer entering your password on every connection.

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

**Release status:** this is a new plugin under marketplace review and is not yet
listed. The commands below install directly from the source repository.

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

When you first open EasyOpenVPN after installing, a Polkit authorization dialog will automatically appear requesting superuser privileges to enable passwordless VPN connections.

- **To enable**: enter your user password and confirm. Future connections and disconnections from the panel will not prompt for a password.
- **To decline**: click **Cancel** in the Polkit prompt. EasyOpenVPN will remember your choice and will not prompt automatically again. Connections will continue to use standard `pkexec` password prompts on each connect.
- **To change later**: you can click **Enable** directly on the Passwordless card in the panel, or run the helper script in a terminal:

```sh
sudo ./setup-passwordless.sh
```

The script installs a root-owned copy of the control script under `/usr/local/lib/simpleopenvpn` and a narrow Polkit rule authorizing **only** that exact program for `connect` and `disconnect`. The rule does not permit running arbitrary commands as root.

The helper uses ABI **4**, requiring strict OpenVPN token boundaries, immutable
profile snapshots, isolated Python startup (`-I -S`), and guard/log integrity fixes. The client checks the
installed scripts and ABI marker before delegation. Missing, incompatible, or
unsafe helper files prevent automatic delegation; normal connections use a
Polkit password prompt when the optional helper is unavailable.

**Security upgrade:** existing ABI 1/2/3 installations must rerun the setup command
above (or remove passwordless access). Updating the plugin alone does not replace
the installed privileged copy or revoke its Polkit authorization; rejecting an
old ABI in the UI does not prevent direct invocation of that old helper.

The privileged validator deliberately rejects ambiguous quote concatenation,
NUL/BOM bytes, noncanonical inline tags, and config lines over 255 UTF-8 bytes.
Use whitespace-separated tokens and conventional inline certificate/key blocks.

To remove the passwordless rule at any time:

```sh
sudo ./setup-passwordless.sh --remove
```

---

## Troubleshooting

### OpenVPN executable not found

A `.ovpn` or `.conf` file is a connection profile, not the OpenVPN application.
The controller requires the system executable `/usr/bin/openvpn`. If the panel
reports that it is missing, install the package from a desktop terminal:

```sh
omarchy pkg add openvpn
/usr/bin/openvpn --version
```

The controller now reports an actionable error instead of an unhandled
`FileNotFoundError`. A missing dependency is not fixed by selecting a different
profile or creating a directory. If installation reports a privilege or
container restriction, complete installation in your normal desktop terminal;
the plugin does not bypass system authorization.

### A removed profile is still on disk

This is intentional. **Delete** only removes the plugin's list entry, not the
local configuration file or saved credentials. Removed entries stay absent
across status refreshes. Use **Add Profile** or **Open Folder** to import them
again; **Clear Auth** can separately remove saved credentials for a selected
profile.

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
