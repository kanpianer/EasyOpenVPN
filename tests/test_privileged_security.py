"""No root, native modules, network operations, or Polkit changes required."""
import ast
import contextlib
import io
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CTL = (ROOT / "scripts/openvpn-ctl").read_text()


def validator_functions():
    code = CTL.split("<<'PY'\n", 1)[1].split("\nPY", 1)[0]
    tree = ast.parse(code)
    names = {"fail", "tokenize_config_line", "normalize_config_line", "validate_openvpn_config_fd"}
    tree.body = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
    import sys
    namespace = {"os": os, "sys": sys}
    exec(compile(tree, "<production-validator>", "exec"), namespace)
    return namespace


class ProfileSecurityTests(unittest.TestCase):
    def validate(self, data):
        with tempfile.TemporaryFile() as profile:
            profile.write(data.encode())
            profile.flush()
            validator_functions()["validate_openvpn_config_fd"](profile.fileno(), "fixture")

    def test_native_modules_and_ambiguous_boundaries_rejected(self):
        for directive in ("plugin", "providers", "pkcs11-providers", "engine", "memstats", "tls-crypt-v2-metadata"):
            for line in (f'{directive} /missing', f'"{directive}"/missing',
                         f"'{directive}'/missing", f'setenv opt "{directive}"/missing',
                         f'setenv opt\v{directive} /missing',
                         f'setenv opt\f{directive} /missing'):
                with self.subTest(line=line), contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit):
                        self.validate(line + "\n")

    def test_inline_and_c_string_differentials_rejected(self):
        for text in ('<ca>\ndata\n</ca>\0\nplugin /missing\n',
                     '<ca>\ndata\n</ca> trailing\nplugin /missing\n',
                     '\ufeffplugin /missing\n', ' ' * 256 + 'plugin /missing\n'):
            with self.subTest(text=text), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    self.validate(text)

    def test_normal_profiles_and_inline_data_accepted(self):
        self.validate('client\nremote vpn.example 1194\nproto udp\nauth-user-pass\n'
                      'verify-x509-name "VPN Server" name # comment\n'
                      '<ca>\nplugin is inert certificate data\n</ca>\n')

    def test_comment_characters_inside_tokens_are_literal(self):
        tokenize = validator_functions()["tokenize_config_line"]
        self.assertEqual(tokenize('setenv name value#suffix ; comment'),
                         ['setenv', 'name', 'value#suffix'])


class PythonIsolationTests(unittest.TestCase):
    def test_all_python_shell_invocations_are_isolated(self):
        for filename in ('scripts/openvpn-ctl', 'scripts/openvpn-lib'):
            source = (ROOT / filename).read_text()
            calls = re.findall(r'python3 (-(?:I|c| )[^\n]*)', source)
            self.assertTrue(calls)
            for call in calls:
                self.assertTrue(call.startswith('-I -S '), call)

    def test_hostile_cwd_and_pythonpath_cannot_supply_imports(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for module in ('re', 'select', 'signal', 'subprocess', 'sitecustomize', 'usercustomize'):
                (base / (module + '.py')).write_text('raise RuntimeError("untrusted import")\n')
            env = dict(os.environ, PYTHONPATH=directory, PYTHONHOME=directory)
            result = subprocess.run(
                ['/usr/bin/python3', '-I', '-S', '-', 'argument'],
                input='import re, select, signal, subprocess, sys\nassert sys.argv[1:] == ["argument"]\n',
                text=True, capture_output=True, cwd=directory, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
