"""Probe Windows runtime primitives before claiming PMAI readiness."""
import ctypes
import os
from pathlib import Path
import sys
import tempfile
import shutil
import subprocess

if sys.platform != 'cygwin':
    raise SystemExit('PMAI Windows entry requires Cygwin Python, not native Windows Python.')
import fcntl

for executable in ('bash', 'git', 'python3', 'node', 'shasum', 'jq'):
    if not shutil.which(executable):
        raise SystemExit(f'Windows runtime missing required executable: {executable}')

# Finding a name in PATH is insufficient: a native Windows binary may not
# understand Cygwin paths. Exercise the actual dependencies before any suite.
for command in (['bash', '--version'], ['git', '--version'], ['node', '--version']):
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, timeout=10)
checksum = subprocess.run(['shasum', '-a', '256'], input=b'', capture_output=True, check=True, timeout=10)
if not checksum.stdout.startswith(b'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'):
    raise SystemExit('Windows runtime shasum did not calculate the expected digest.')
parsed = subprocess.run(['jq', '-r', '.ready'], input='{"ready":true}', text=True, capture_output=True, check=True, timeout=10)
if parsed.stdout.strip() != 'true':
    raise SystemExit('Windows runtime jq did not parse the probe.')

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from _lib.atomic_file import _rename_noreplace, _open_directory_without_symlinks

assert hasattr(ctypes.CDLL('cygwin1.dll'), 'renameat2')
with tempfile.TemporaryDirectory(prefix='pmai-runtime-probe-') as directory:
    root = Path(directory).resolve()
    source, target = root / 'source', root / 'target'
    source.write_text('candidate')
    target.write_text('existing')
    with source.open('rb') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(handle, fcntl.LOCK_UN)
    fd = _open_directory_without_symlinks(root)
    try:
        try:
            _rename_noreplace(fd, source.name, target.name)
        except FileExistsError:
            pass
        else:
            raise RuntimeError('RENAME_NOREPLACE overwrote an existing target')
        assert target.read_text() == 'existing' and source.read_text() == 'candidate'
        _rename_noreplace(fd, source.name, 'created')
        assert (root / 'created').read_text() == 'candidate'
    finally:
        os.close(fd)
print(f'Windows runtime primitives passed: {sys.version.split()[0]}, {sys.platform}')
