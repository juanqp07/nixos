import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHECKER = REPO_ROOT / "scripts" / "nix-reboot-check.sh"
COMPONENTS = ("kernel", "kernel-modules", "initrd", "systemd")


class RebootCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.old_system = self.root / "old-system"
        self.new_system = self.root / "new-system"
        self.targets = self.root / "component-targets"
        self.old_system.mkdir()
        self.new_system.mkdir()
        self.targets.mkdir()

        for component in COMPONENTS:
            target = self.targets / component
            target.write_text(component, encoding="utf-8")
            (self.old_system / component).symlink_to(target)
            (self.new_system / component).symlink_to(target)

        self.booted_link = self.root / "booted-system"
        self.selected_link = self.root / "selected-system"
        self.booted_link.symlink_to(self.old_system)
        self.selected_link.symlink_to(self.new_system)

        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        fake_nix = fake_bin / "nix"
        fake_nix.write_text(
            "#!/usr/bin/env bash\nprintf '%s' \"$TEST_DEPLOY_OPERATION\"\n",
            encoding="utf-8",
        )
        fake_nix.chmod(0o755)

        self.env = os.environ.copy()
        self.env["PATH"] = f"{fake_bin}{os.pathsep}{self.env['PATH']}"
        self.env["NIX_REBOOT_CHECK_BOOTED_PATH"] = str(self.booted_link)
        self.env["NIX_REBOOT_CHECK_NEXT_PATH"] = str(self.selected_link)
        self.env["TEST_DEPLOY_OPERATION"] = "switch"

    def tearDown(self):
        self.temp_dir.cleanup()

    def run_check(self, operation="switch"):
        env = self.env.copy()
        env["TEST_DEPLOY_OPERATION"] = operation
        return subprocess.run(
            ["bash", str(CHECKER), "--status"],
            cwd=REPO_ROOT,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_switch_without_boot_component_changes_does_not_require_reboot(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "not-required|")

    def test_switch_with_kernel_change_requires_reboot(self):
        new_kernel = self.targets / "kernel-new"
        new_kernel.write_text("new kernel", encoding="utf-8")
        (self.new_system / "kernel").unlink()
        (self.new_system / "kernel").symlink_to(new_kernel)

        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "required|cambios en kernel")

    def test_boot_operation_reports_pending_generation(self):
        result = self.run_check(operation="boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "required|hay una nueva generación preparada para el próximo arranque",
        )

    def test_missing_component_reports_unknown_instead_of_no_reboot(self):
        (self.new_system / "systemd").unlink()

        result = self.run_check()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "unknown|faltan componentes necesarios para comparar las generaciones",
        )

    def test_missing_booted_system_reports_unknown(self):
        self.booted_link.unlink()

        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "unknown|no se puede identificar el sistema arrancado",
        )


if __name__ == "__main__":
    unittest.main()
