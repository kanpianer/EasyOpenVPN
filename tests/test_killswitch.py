"""Exercise the production guard without root, VPN, or firewall changes."""
import ast
import os
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]


def guard_namespace(polls):
    source = (ROOT / 'scripts/openvpn-ctl').read_text().split("<<'PY'\n", 1)[1].split('\nPY', 1)[0]
    tree = ast.parse(source)
    tree.body = [n for n in tree.body if
                 isinstance(n, ast.FunctionDef) and n.name == 'guard_loop' or
                 isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id in
                 ('LOSS_MARKERS', 'CONNECT_TIMEOUT') for t in n.targets)]
    poller = SimpleNamespace(register=Mock(), poll=Mock(side_effect=polls))
    ns = dict(os=os, re=re, select=SimpleNamespace(poll=lambda: poller, POLLIN=1),
              time=SimpleNamespace(monotonic=lambda: 0, sleep=Mock()),
              engage_killswitch=Mock(), terminate_pid=Mock(),
              find_tun_iface=lambda: '', iface_has_ipv4=lambda name: False)
    exec(compile(tree, '<production-guard>', 'exec'), ns)
    return ns


class KillSwitchTests(unittest.TestCase):
    def run_guard(self, log, polls, intentional=False):
        ns = guard_namespace(polls)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'log').write_text(log)
            if intentional:
                (root / 'stop').touch()
            ns['guard_loop'](123, 42, '/mock/nft', str(root / 'log'),
                             str(root / 'stop'), str(root / 'killswitch'), str(root / 'auth'))
        return ns

    def test_exit_before_first_poll_consumes_success_log(self):
        ns = self.run_guard('Initialization Sequence Completed\n', [True])
        ns['engage_killswitch'].assert_called_once()

    def test_failed_handshake_does_not_block_network(self):
        ns = self.run_guard('AUTH_FAILED\n', [True])
        ns['engage_killswitch'].assert_not_called()

    def test_explicit_disconnect_does_not_block_network(self):
        ns = self.run_guard('Initialization Sequence Completed\n', [], intentional=True)
        ns['engage_killswitch'].assert_not_called()

    def test_server_restart_after_connection_blocks_network(self):
        ns = self.run_guard('Initialization Sequence Completed\nSIGUSR1[soft,connection-reset] received\n', [False])
        ns['engage_killswitch'].assert_called_once()

    def test_address_loss_on_existing_tunnel_blocks_network(self):
        # loopback is guaranteed to exist; mock reports no IPv4 to model a
        # persistent tunnel whose address was removed on server disconnect.
        ns = self.run_guard('TUN/TAP device lo opened\nInitialization Sequence Completed\n', [False, True])
        ns['engage_killswitch'].assert_called_once()
        self.assertIn('address', ns['engage_killswitch'].call_args.args[5])


if __name__ == '__main__':
    unittest.main()
