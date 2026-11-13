# EasyOpenVPN security audit — 2026-11-13

## Scope and limits

Source review of the privileged launcher, profile validator, installer/Polkit rule,
state and credential helpers, and QML control/status paths. Baseline HEAD:
`2ccdd837b1d3fa23ac1295171cd5b3ee9ec01243`, including the uncommitted parser,
Python-isolation and kill-switch fixes from this session. No production firewall,
Polkit rule, installed helper, or VPN connection was changed during testing.
This is a scoped source audit, not a security certification.

## Findings fixed in this round

| Finding | Assessment | Fix |
| --- | --- | --- |
| UI timeout automatically invokes disconnect, which removes protection even when status is stale | High confidentiality impact under the race; source-confirmed, live timing not reproduced | Removed automatic disconnect timer; only root guard handles handshake timeout |
| Guard trusts a caller-writable runtime log | Medium integrity / availability; authorized caller can already explicitly disconnect, so this is not a new root escalation | Root-owned log mode 0640, requesting primary group read-only; descriptor ownership checks updated |
| Profile verbosity/muting can suppress guard lifecycle events | Medium availability / loss-detection weakness | Force `--verb 3 --mute 0` after profile options |
| FIFO profile blocks root before regular-file validation | Medium local resource exhaustion | Nonblocking opens before fstat; state readers also nonblocking, single-line state reads bounded |
| Detached guard opens pidfd too late and silently swallows exceptions | Medium loss of supervision | Acquire pidfd before fork while child identity is retained; guard exceptions engage protection rather than silently exit |
| Installer trusts destination ancestry and existing leaf files | Conditional High if destination was previously attacker-controlled; standard root-owned system paths do not meet this prerequisite | Reject symlink, non-root-owned, writable ancestors and unsafe installed leaves before changes |
| Additional profile file surfaces: memstats, tls-crypt-v2-metadata | Defense-in-depth against build-dependent file access | Reject direct and deferred forms |
| Credential line protocol and dynamic directory label | Low / defense-in-depth | Reject newline/NUL fields in QML; render directory label as plain text |

ABI is now **4**, so ABI 1/2/3 helpers are not selected automatically.

## Previous fixes retained and checked

- Conservative OpenVPN token parsing, forbidden native modules and deferred forms.
- Frozen profile snapshot before validation and execution.
- Python `-I -S` startup, including library calls on root paths.
- User credential data travels over stdin, not process argv.
- Descriptor-based regular-file/ownership checks and atomic state publishing.
- Guard drains final log before classifying process exit; address loss detection.
- Explicit user disconnect and failed initial handshake do not trigger protection.
- UI log and control-error plain-text rendering; argv arrays rather than shell strings.

## Validation

27 unittest tests pass. Shell syntax validation and `git diff --check` pass.
The FIFO regression demonstrably timed out before the fix and rejects promptly
after it. Guard tests execute extracted production functions with mocked process,
network and firewall interactions. Some UI, launch-flag and permission regressions
are source assertions rather than end-to-end tests. Installer ancestry validation
is tested in a child Python process without root writes.

ShellCheck and qmllint were not available. No live Polkit, QML rendering,
root-owned installation, packet capture, real server disconnect, or network
namespace firewall integration test was performed.

## Residual risks / follow-up work

- The kill switch is reactive, not an always-on packet-filter policy. Detection,
  polling and nft execution introduce a leak window. It does not guarantee zero
  packets outside the tunnel; that requires preinstalled rules allowing only the
  selected VPN transport and tunnel, plus controlled reconnect handling.
- nft installation failures are recorded as unenforced; software cannot promise
  blocked traffic when kernel firewall changes fail. Guard failure recovery also
  depends on nft remaining functional.
- The nft table is global (`inet simpleopenvpn`), whereas runtime paths are per
  UID. Multi-user/multiple concurrent sessions and overlapping connect/disconnect
  actions are not isolated or serialized. Use one desktop VPN session at a time.
- Profile policy is a denylist plus conservative syntax checks, not a versioned
  allowlist. Future OpenVPN options/build variants require re-review. Some advanced
  profiles are intentionally rejected, including lines over 255 UTF-8 bytes.
- Logs are root-owned and readable by the user's primary group. Accounts sharing
  that group may read log information; a private per-user group is recommended.
- Saved credentials remain plaintext mode 0600 in a mode 0700 state directory;
  this protects other users, not compromise of the same desktop account.
- The source installer intentionally trusts the source checkout authorized by the
  administrator. Do not authorize installation from an untrusted checkout.

## Deployment

Run from this plugin checkout in a terminal:

```sh
sudo ./setup-passwordless.sh
```

Then explicitly disconnect and reconnect to replace an already-running guard.
Old ABI rejection does not revoke direct Polkit access to an old installed copy;
installation (or removal of passwordless access) is required. The installer now
fails closed on untrusted installation paths; do not bypass that diagnostic by
blindly changing ownership of unknown files. Inspect and repair the installation
as administrator if that occurs.
