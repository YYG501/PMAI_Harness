"""Keep Cygwin *at operations bound to the actual Windows directory object.

Cygwin caches a dirfd's path across parent renames. For each relative syscall,
reopen the same directory with FILE_SHARE_DELETE disabled, verify its identity,
and attach its current name to a short-lived Cygwin fd. The Windows lease keeps
that name stable until the syscall returns. This does not change global os.
"""
from contextlib import contextmanager, ExitStack
import ctypes
import errno
import os
import stat

_cygwin = ctypes.CDLL('cygwin1.dll', use_errno=True)
_kernel = ctypes.CDLL('kernel32.dll')
_get_handle = _cygwin._get_osfhandle
_get_handle.argtypes = [ctypes.c_int]
_get_handle.restype = ctypes.c_void_p
_get_path = _kernel.GetFinalPathNameByHandleW
_get_path.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32]
_get_path.restype = ctypes.c_uint32
_create = _kernel.CreateFileW
_create.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                    ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
_create.restype = ctypes.c_void_p
_close = _kernel.CloseHandle
_close.argtypes = [ctypes.c_void_p]
_attach = _cygwin.cygwin_attach_handle_to_fd
_attach.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int, ctypes.c_uint32]
_attach.restype = ctypes.c_int
_convert = _cygwin.cygwin_conv_path
_convert.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
_convert.restype = ctypes.c_ssize_t
_INVALID_HANDLE = ctypes.c_void_p(-1).value


def _posix_path(windows_path):
    source = ctypes.create_unicode_buffer(windows_path)
    # CCP_WIN_W_TO_POSIX, absolute path. No shell or external resolver.
    size = _convert(3, source, None, 0)
    if size <= 0:
        raise OSError(ctypes.get_errno(), 'Cygwin directory path conversion failed')
    target = ctypes.create_string_buffer(size)
    if _convert(3, source, target, size) != 0:
        raise OSError(ctypes.get_errno(), 'Cygwin directory path conversion failed')
    return target.value


@contextmanager
def pinned_directory(fd):
    expected = os.fstat(fd)
    if not stat.S_ISDIR(expected.st_mode):
        raise NotADirectoryError(errno.ENOTDIR, 'dir_fd does not refer to a directory')
    # Cygwin's drive container is virtual and has no Windows HANDLE. Its entries
    # are provided by Cygwin itself, not a renameable filesystem directory.
    # /proc/cygdrive is the stable alias even with a custom cygdrive prefix.
    drives = os.stat('/proc/cygdrive')
    if (expected.st_dev, expected.st_ino) == (drives.st_dev, drives.st_ino):
        yield fd
        return
    original = _get_handle(fd)
    buffer = ctypes.create_unicode_buffer(32768)
    size = _get_path(original, buffer, len(buffer), 0)
    if not size or size >= len(buffer):
        raise OSError(errno.EIO, f'Windows directory path lookup failed: {_kernel.GetLastError()}')
    # READ | WRITE sharing, without DELETE: pins this path and its ancestors.
    # BACKUP_SEMANTICS permits directories; OPEN_REPARSE_POINT rejects redirection
    # through a final reparse point by the identity check below.
    handle = _create(buffer.value, 0x80000000, 3, None, 3, 0x02200000, None)
    if handle in (None, _INVALID_HANDLE):
        raise OSError(errno.EACCES, f'Windows directory lease failed: {_kernel.GetLastError()}')
    attached = -1
    try:
        attached = _attach(_posix_path(buffer.value), -1, handle, os.O_BINARY, 0x80000000)
        if attached < 0:
            raise OSError(ctypes.get_errno(), 'Could not attach Windows directory handle')
        actual = os.fstat(attached)
        if not stat.S_ISDIR(actual.st_mode) or (actual.st_dev, actual.st_ino) != (expected.st_dev, expected.st_ino):
            raise OSError(errno.ESTALE, 'Windows directory changed while acquiring lease')
        yield attached
    finally:
        if attached >= 0:
            os.close(attached)  # Owns the Windows handle after successful attach.
        else:
            _close(handle)


class BoundDirectoryOS:
    """Module-local proxy; callers and other libraries keep the original os."""
    _relative_functions = {'open', 'stat', 'unlink', 'mkdir', 'rmdir', 'readlink',
                           'chmod', 'utime', 'link', 'symlink', 'rename', 'replace'}

    def __getattr__(self, name):
        function = getattr(os, name)
        if name not in self._relative_functions:
            return function

        def relative_call(*args, **kwargs):
            with ExitStack() as stack:
                for key in ('dir_fd', 'src_dir_fd', 'dst_dir_fd'):
                    if kwargs.get(key) is not None:
                        kwargs[key] = stack.enter_context(pinned_directory(kwargs[key]))
                return function(*args, **kwargs)
        return relative_call
