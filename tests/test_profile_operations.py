"""Exercise real controller actions with disposable profiles and state."""
import ast
import contextlib
import io
import os
import sys
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CTL = ROOT / "scripts/openvpn-ctl"


def launcher_functions():
    source = CTL.read_text().split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
    tree = ast.parse(source)
    functions = [node for node in tree.body if isinstance(node, ast.FunctionDef)]
    namespace = {"os": os, "stat": stat, "sys": sys}
    exec(compile(ast.Module(body=functions, type_ignores=[]), "<connect-helper>", "exec"), namespace)
    return namespace


class ProfileOperationsTests(unittest.TestCase):
    def test_remove_only_forgets_profile_and_updates_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            env = dict(os.environ, HOME=directory, XDG_STATE_HOME=str(base / "state"))
            env.pop("PKEXEC_UID", None)
            profiles = [base / "one.ovpn", base / "two.conf"]
            for profile in profiles:
                profile.write_text("client\n")
            def run(*args):
                result = subprocess.run(["bash", str(CTL), *map(str, args)], env=env,
                                        text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                return result
            for profile in profiles:
                run("set_config", profile)
            # The final set_config selected two.conf.
            run("remove_profile", profiles[1])
            self.assertTrue(profiles[1].is_file(), "Removing a node must not delete its local file")
            state = base / "state/omarchy-openvpn"
            self.assertEqual((state / "profiles").read_text().splitlines(), [str(profiles[0])])
            self.assertEqual((state / "config").read_text().strip(), str(profiles[0]))
            # Real status command must not rediscover removed files in the folder.
            import json
            self.assertEqual(json.loads(run("status").stdout)["configs"], [str(profiles[0])])
            run("remove_profiles", profiles[0])
            self.assertTrue(profiles[0].is_file())
            self.assertEqual(json.loads(run("status").stdout)["configs"], [])
            self.assertFalse((state / "config").exists())

    def test_missing_binary_has_actionable_error_not_traceback(self):
        functions = launcher_functions()
        error = io.StringIO()
        with contextlib.redirect_stderr(error), patch.object(os, "stat", side_effect=FileNotFoundError(2, "No such file or directory")):
            with self.assertRaises(SystemExit):
                functions["validate_root_executable"]("/usr/bin/openvpn")
        self.assertIn("omarchy pkg add openvpn", error.getvalue())
        self.assertNotIn("Traceback", error.getvalue())


if __name__ == "__main__":
    unittest.main()
