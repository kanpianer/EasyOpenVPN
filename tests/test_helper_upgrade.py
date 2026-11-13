"""Unprivileged regressions: never installs helpers or changes Polkit/network state."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "scripts/openvpn-lib"


class HelperUpgradeTests(unittest.TestCase):
    def check_helper(self, marker="4\n", missing=None, unsafe=None):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name in ("openvpn-ctl", "openvpn-lib", "abi"):
                if name != missing:
                    (base / name).write_text(marker if name == "abi" else "fixture")
            # Simulate root ownership only. File opening, symlink flags, bounded
            # reads, ABI comparison and shell control flow remain real. This
            # suite must be runnable without root or a privileged installation.
            script = r'''
source "$1"
openvpn_installed_dir="$2"
openvpn_installed_ctl="$2/openvpn-ctl"
openvpn_installed_abi_file="$2/abi"
unsafe="$3"
openvpn_root_owned_file() { [[ -f "$1" && ! -L "$1" && "${1##*/}" != "$unsafe" ]]; }
python3() {
  shift 2  # Skip production isolation flags in this in-process mock.
  command python3 -I -S -c '
import os, sys
from unittest.mock import patch
code = sys.stdin.read()
real_fstat = os.fstat
def root_owned(fd):
    fields = list(real_fstat(fd))
    fields[4] = 0
    return os.stat_result(fields)
with patch("os.fstat", root_owned):
    sys.argv = sys.argv[1:]
    exec(compile(code, "<marker-reader>", "exec"))
' "$@"
}
openvpn_passwordless_available
'''
            return subprocess.run(
                ["bash", "-c", script, "test", str(LIB), str(base), unsafe or ""],
                capture_output=True, text=True, check=False,
            )

    def test_current_abi_accepted(self):
        self.assertEqual(self.check_helper().returncode, 0)

    def test_pre_parser_helper_rejected_with_refresh_instruction(self):
        result = self.check_helper("1\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("installed ABI 1, required ABI 4", result.stderr)
        self.assertIn(f"sudo {ROOT}/setup-passwordless.sh", result.stderr)

    def test_invalid_markers_rejected(self):
        for marker in ("", "2\n", "3\n", "4\nextra\n", "x" * 100, "é\n"):
            with self.subTest(marker=marker):
                self.assertNotEqual(self.check_helper(marker).returncode, 0)

    def test_partial_install_rejected(self):
        for name in ("openvpn-ctl", "openvpn-lib", "abi"):
            with self.subTest(name=name):
                self.assertNotEqual(self.check_helper(missing=name).returncode, 0)

    def test_untrusted_files_rejected(self):
        for name in ("openvpn-ctl", "openvpn-lib", "abi"):
            with self.subTest(name=name):
                self.assertNotEqual(self.check_helper(unsafe=name).returncode, 0)

    def test_installer_and_client_abi_match(self):
        required = re.search(r"^openvpn_helper_abi=(\d+)$", LIB.read_text(), re.M)[1]
        installer = (ROOT / "setup-passwordless.sh").read_text()
        installed = re.search(r"printf '(\d+)\\n' > \"\$install_dir/abi\"", installer)[1]
        self.assertEqual(required, installed)
        self.assertEqual(required, "4")

    def test_both_privileged_actions_gate_delegation(self):
        source = (ROOT / "scripts/openvpn-ctl").read_text()
        for action in ("connect", "disconnect"):
            self.assertRegex(source, rf'if openvpn_can_delegate; then\s+exec pkexec "\$openvpn_installed_ctl" {action}\s+fi')

    def test_root_installer_does_not_write_prompt_marker(self):
        installer = (ROOT / "setup-passwordless.sh").read_text()
        self.assertNotIn('> "$prompted_file"', installer)
        self.assertNotIn('chown "$target_uid:$target_gid"', installer)
        self.assertNotIn('target_home=', installer)


if __name__ == "__main__":
    unittest.main()
