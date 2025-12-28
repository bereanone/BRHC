#!/usr/bin/env python3
import shutil
import sys
from pathlib import Path


SANDBOX_PATH = Path.home() / "Library" / "Containers" / "com.example.brhcApp" / "Data"
WIPE_PATHS = [
    Path("build"),
    Path(".dart_tool"),
    SANDBOX_PATH,
]

PROTECTED_DIRS = {
    Path("assets"),
    Path("lib"),
    Path("docs"),
    Path("reference"),
}


def _is_safe_path(path: Path) -> bool:
    if path.is_absolute():
        return str(path) == str(SANDBOX_PATH)
    return True


def _print_action(action: str, path: Path) -> None:
    print(f"{action}: {path}")


def _remove_path(path: Path) -> None:
    if not path.exists():
        _print_action("SKIP (missing)", path)
        return
    if path.is_symlink():
        _print_action("SKIP (symlink)", path)
        return
    if path.is_dir():
        _print_action("REMOVE DIR", path)
        shutil.rmtree(path)
    else:
        _print_action("REMOVE FILE", path)
        path.unlink()


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
