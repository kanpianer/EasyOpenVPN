"""Security audit regressions; never invoke Polkit or alter the firewall."""
import ast
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AuditSecurityTests(unittest.TestCase):
    def test_special_profile_file_rejected_without_blocking(self):
        source = (ROOT / 'scripts/openvpn-ctl').read_text().split("<<'PY'\n", 1)[1].split('\nPY', 1)[0]
        tree = ast.parse(source)
        tree.body = [n for n in tree.body if isinstance(n, ast.FunctionDef)
                     and n.name in ('fail', 'open_user_file')]
        code = 'import os, stat, sys\nuid = os.getuid()\n' + ast.unparse(tree)
        code += '\nopen_user_file(sys.argv[1], True)\n'
        with tempfile.TemporaryDirectory() as directory:
            fifo = Path(directory) / 'profile.ovpn'
            os.mkfifo(fifo)
            try:
                result = subprocess.run(['/usr/bin/python3', '-I', '-S', '-c', code, str(fifo)],
                                        capture_output=True, text=True, timeout=2)
            except subprocess.TimeoutExpired:
                self.fail('privileged profile reader blocks on caller-controlled FIFO')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('not a regular file', result.stderr)

    def test_ui_timeout_cannot_restore_network_automatically(self):
        source = (ROOT / 'BarWidget.qml').read_text()
        self.assertNotIn('id: connectTimeout', source,
                         'UI timeout must not call disconnect and clear firewall protection')

    def test_guard_identity_is_acquired_before_fork(self):
        source = (ROOT / 'scripts/openvpn-ctl').read_text()
        guard = source.split('def spawn_guard(', 1)[1].split('\nruntime_fd =', 1)[0]
        self.assertLess(guard.index('os.pidfd_open('), guard.index('os.fork('))
        self.assertIn('"Kill switch guard failed"', guard)

    def test_guard_logging_cannot_be_muted_by_profile(self):
        source = (ROOT / 'scripts/openvpn-ctl').read_text()
        args = source.split('args = [\n    openvpn_bin,', 1)[1].split('\n]', 1)[0]
        self.assertIn('"--verb", "3"', args)
        self.assertIn('"--mute", "0"', args)

    def test_installer_rejects_untrusted_destination(self):
        source = (ROOT / 'setup-passwordless.sh').read_text()
        code = source.split("<<'PY'\n", 1)[1].split('\nPY', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'helper'
            target.symlink_to('/usr')
            result = subprocess.run(['/usr/bin/python3', '-I', '-S', '-', str(target),
                                     str(Path(directory) / 'rule')], input=code,
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('unsafe installation path', result.stderr)

    def test_runtime_log_is_not_user_writable(self):
        source = (ROOT / 'scripts/openvpn-ctl').read_text()
        self.assertIn('secure_replace(runtime_fd, log_name, b"", 0o640, 0, gid)', source)
        self.assertIn('log_st.st_uid != 0', source)


if __name__ == '__main__':
    unittest.main()
