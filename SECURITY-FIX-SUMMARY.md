# EasyOpenVPN — Pre-release Review Fix Brief

## Scope

EasyOpenVPN is a **new plugin awaiting its first marketplace listing**. This
brief describes the review findings, local fixes, and remaining release checks.
It does not prescribe an existing-user migration or claim marketplace approval.

## Latest reviewer feedback

Reference: [latest reviewer comment](https://github.com/omacom/omarchy-plugin-marketplace/issues/13434#issuecomment-6599015349).

The reviewer reported **High — stale privileged helper**: the submitted
repository still pointed to `6eb9644`, where ABI 1 could accept a helper from
before the profile parser and snapshot security fixes. The announced `045fcf9`
fix was not available in the submitted repository.

There are two distinct concerns:

1. **Helper acceptance:** the local implementation now requires ABI 2, and the
   installer writes ABI 2. Incompatible helpers are not automatically selected
   for privileged connect/disconnect operations.
2. **Reviewable publication:** the fix must actually be present in the public
   revision submitted for review. During the earlier repository check in this
   repair session, public HEAD was still `6eb9644`, while local HEAD contained
   `045fcf9`. This submission includes that ABI fix together with the follow-up
   changes described below. Review should target the published submission
   commit rather than the previously reviewed `6eb9644`.

This initial release is intended to install the current helper from the outset;
there is no existing-user migration section or migration requirement here.
ABI rejection is a client-side selection safeguard, not revocation of a
previously installed executable or Polkit rule.

## Additional findings and local fixes

### 1. ABI-marker trust and diagnostic path

The ABI marker previously received only a readability check. It now requires a
root-owned regular file without group/other write access, is opened with
`O_NOFOLLOW` and `O_NONBLOCK`, and is checked again through `fstat()` on the
opened descriptor. Reads are bounded. The diagnostic points to the actual
source setup script rather than an unrelated directory.

### 2. Privileged write through user-controlled directories

Pending installer changes wrote, chowned, and chmodded a UI prompt marker
inside the desktop user's home as root. A symlink or replaced parent directory
could redirect those operations to an unrelated file. That sequence was
removed. Prompt bookkeeping is performed by the unprivileged caller before
Polkit authorization; the root installer does not need to write it.

### 3. Missing OpenVPN dependency produced an unhandled exception

The connection launcher could raise `FileNotFoundError` while inspecting
`/usr/bin/openvpn`. A profile file or directory existing does not establish
that the OpenVPN executable is installed. In the diagnostic environment, both
the executable and the installed package were absent.

The launcher now returns a clear dependency error with the command
`omarchy pkg add openvpn`, instead of an unhandled Python traceback. This is
improved error handling, **not** automatic installation or a confirmed live
connection fix. The authorized package installation attempt was blocked by the
environment's `no new privileges` restriction; a successful installation and
connection were not verified.

### 4. Removing a list entry deleted its source file

The old remove action called `gio trash`, falling back to `rm`, on the original
profile file. It now edits the remembered-profile list only, preserving local
`.ovpn`/`.conf` files and saved credentials. Selection moves to a remaining
entry, or is cleared when the list becomes empty.

Status refresh also previously rescanned the selected folder, which would
reintroduce entries once deletion became non-destructive. It now lists only
explicitly imported profiles. Users can intentionally re-import files through
**Add Profile** or **Open Folder**.

## Previously confirmed review fixes

The review history had already confirmed the snapshot-before-validation order
and plain-text log rendering. The local source also retains plain-text
rendering for the kill-switch reason and control errors. Those prior fixes are
not presented as new work in this round.

## Documentation changes

The README now describes a source-installed, pre-listing plugin; initial
passwordless setup and helper compatibility; missing-dependency diagnostics;
and non-destructive profile removal. The existing-user upgrade/migration
section has been removed.

## Validation

The latest code validation completed with **10 passing tests**, plus successful
shell syntax and whitespace checks:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
bash -n scripts/openvpn-lib scripts/openvpn-ctl setup-passwordless.sh install.sh
git diff --check
```

Coverage includes ABI compatibility, invalid or untrusted markers, partial
helper installations, installer/client ABI consistency, both delegation call
sites, absence of the privileged prompt-marker write, missing-executable error
handling, and real controller operations against disposable profile/state
fixtures. Profile removal tests also check selection and status refresh.

Tests do not install a system helper, authorize Polkit, establish a VPN, or
modify the firewall. Ownership checks are mocked where necessary; some checks
are source assertions rather than integration tests. ShellCheck and qmllint
were unavailable. Live Polkit/GUI and connection/kill-switch validation remain
outstanding. This targeted repair is not a security certification or a complete
new audit of the plugin.

## Before resubmission

- Publish the intended source changes, tests, and documentation to the submitted
  repository and provide reviewers with the actual published commit SHA.
- Verify a clean installation with the documented dependencies and ABI 2 helper.
- Complete live authorization, connection, disconnect, and kill-switch checks
  on the desktop host.

No marketplace approval or completed live VPN validation is claimed by this
brief. The public commit SHA should be supplied with the review response.
