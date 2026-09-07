"""Windows compatibility boundaries; exercised only by Cygwin Python."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))


@unittest.skipUnless(sys.platform == 'cygwin', 'Windows runtime only')
class WindowsRuntimeTests(unittest.TestCase):
    def test_bound_directory_survives_rename_and_rejects_rebinding(self):
        from _lib.cygwin_fs import BoundDirectoryOS, pinned_directory
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            current, held = root / 'current', root / 'held'
            current.mkdir()
            fd = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try:
                current.rename(held)
                current.mkdir()
                with pinned_directory(fd):
                    with self.assertRaises(OSError):
                        held.rename(root / 'moved')
                handle = BoundDirectoryOS().open('evidence', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=fd)
                os.close(handle)
                self.assertTrue((held / 'evidence').exists())
                self.assertFalse((current / 'evidence').exists())
                held.rename(root / 'moved')  # The temporary lease was released.
            finally:
                os.close(fd)

    def test_drive_namespace_supports_bound_traversal(self):
        from _lib.atomic_file import _open_directory_without_symlinks
        native = subprocess.check_output(['cygpath', '-w', str(ROOT)], text=True).strip()
        drive_path = Path(subprocess.check_output(['cygpath', '-u', native], text=True).strip())
        fd = _open_directory_without_symlinks(drive_path)
        try:
            self.assertEqual(os.fstat(fd).st_ino, drive_path.stat().st_ino)
        finally:
            os.close(fd)

    def test_node_preserves_prompt_and_utf8_stdin(self):
        prompt = '/pmai-design 一个新模块 $(literal)'
        code = 'let s="";process.stdin.setEncoding("utf8");process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>console.log(JSON.stringify([process.argv[1],s])))'
        result = subprocess.run(['node', '-e', code, prompt], input='中文正文', text=True, capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout), [prompt, '中文正文'])

    def test_node_preload_path_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix='pmai node 空间 ') as directory:
            preload = Path(directory) / 'preload.cjs'
            preload.write_text('global.fixturePreloaded = 42;', encoding='utf-8')
            environment = dict(os.environ, NODE_OPTIONS='--require=' + json.dumps(str(preload), ensure_ascii=False))
            result = subprocess.run(['node', '-p', 'global.fixturePreloaded'], env=environment, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), '42')

    def test_login_shell_keeps_selected_worktree(self):
        with tempfile.TemporaryDirectory(prefix='pmai cwd ') as directory:
            result = subprocess.run(['bash', '-lc', 'pwd -P'], cwd=directory, text=True, capture_output=True, check=True)
            self.assertEqual(Path(result.stdout.strip()).resolve(), Path(directory).resolve())


if __name__ == '__main__':
    unittest.main()
