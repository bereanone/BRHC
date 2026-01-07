#!/usr/bin/env python3
import shutil
import sys
from pathlib import Path


BUNDLE_ID = "com.example.brhcApp"
SANDBOX_PATH = (
    Path.home()
    / "Library"
    / "Containers"
    / BUNDLE_ID
    / "Data"
)
DOCUMENTS_PATH = SANDBOX_PATH / "Documents"
APP_SUPPORT_PATH = SANDBOX_PATH / "Library" / "Application Support"

WIPE_PATHS = [
    Path("build"),
    Path(".dart_tool"),
    DOCUMENTS_PATH,
    APP_SUPPORT_PATH,
]

PROTECTED_DIRS = {
    Path("assets"),
    Path("lib"),
    Path("docs"),
    Path("reference"),
}


def _is_safe_path(path: Path) -> bool:
    try:
        path = path.resolve()
        return SANDBOX_PATH.resolve() in path.parents or path == SANDBOX_PATH.resolve()
    except Exception:
        return False


def _print_action(action: str, path: Path) -> None:
    print(f"{action}: {path}")


def _remove_path(path: Path) -> None:
    try:
        if not path.exists():
            _print_action("SKIP (missing)", path)
            return
        if path.is_symlink():
            _print_action("SKIP (symlink)", path)
            return
        if path.is_dir():
            _print_action("CLEAR DIR", path)
            for child in path.iterdir():
                _remove_path(child)
        else:
            _print_action("REMOVE FILE", path)
            path.unlink()
    except PermissionError as e:
        _print_action("PERMISSION DENIED", path)
        print(e)


def main() -> int:
    root = Path.cwd()
    for protected in PROTECTED_DIRS:
        if (root / protected).exists():
            _print_action("PROTECT", root / protected)

    for path in WIPE_PATHS:
        if not _is_safe_path(path):
            _print_action("SKIP (unsafe)", path)
            continue
        _remove_path(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
