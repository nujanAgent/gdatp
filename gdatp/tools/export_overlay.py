"""Writes the GDatp repository that is published: the files GDatp adds to Godot or changes, as HEAD stores them.

Every file that differs between Godot's tag and HEAD is copied from git byte for byte. gdatp/overlay.sha256 lists each
one with its SHA-256 for gdatp/tools/apply_to_godot.sh, and a .gitattributes keeps git from changing line endings in a
checkout, so the digests hold on every system. A file GDatp deletes or renames would need the apply script to remove
it from Godot's tree, which it does not do, so the export refuses one.

Run from the repository root: python gdatp/tools/export_overlay.py <new or empty folder>
"""

import hashlib
import re
import subprocess
import sys
from pathlib import Path

BASE_TAG = "4.7.2-stable"
APPLY_SCRIPT = "gdatp/tools/apply_to_godot.sh"
MANIFEST = "gdatp/overlay.sha256"


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1])
        return 2
    out = Path(sys.argv[1])
    if out.exists() and any(out.iterdir()):
        print(f"{out} is not empty")
        return 1

    base = git("rev-parse", f"{BASE_TAG}^{{commit}}").decode().strip()
    script = git("cat-file", "blob", f"HEAD:{APPLY_SCRIPT}").decode()
    pinned = re.search(r"^BASE_COMMIT=([0-9a-f]{40})$", script, re.MULTILINE)
    if not pinned or pinned.group(1) != base:
        print(f"{APPLY_SCRIPT} must pin BASE_COMMIT={base}, the commit {BASE_TAG} names")
        return 1

    entries = git("diff", "--name-status", "--no-renames", "-z", base, "HEAD").split(b"\0")
    changes = [(entries[i].decode(), entries[i + 1].decode()) for i in range(0, len(entries) - 1, 2)]
    refused = [f"{status} {path}" for status, path in changes if status not in ("A", "M")]
    if refused:
        print("The apply script only adds and replaces files; these changes need it to do more:")
        print("\n".join(refused))
        return 1
    paths = sorted(path for _, path in changes)
    if MANIFEST in paths:
        print(f"{MANIFEST} is written by this export and must not be committed")
        return 1
    if any(re.search(r"\s", path) for path in paths):
        print("A path with a space would not survive the apply script's manifest reading")
        return 1

    lines = []
    for path in paths:
        data = git("cat-file", "blob", f"HEAD:{path}")
        target = out / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        lines.append(f"{hashlib.sha256(data).hexdigest()}  {path}")
    manifest = ("\n".join(lines) + "\n").encode()
    (out / MANIFEST).parent.mkdir(parents=True, exist_ok=True)
    (out / MANIFEST).write_bytes(manifest)
    (out / ".gitattributes").write_bytes(b"* -text\n")

    digest = hashlib.sha256(manifest).hexdigest()
    head = git("rev-parse", "HEAD").decode().strip()
    print(f"{len(paths)} files of GDatp at {head[:12]} over {BASE_TAG} ({base[:12]}), "
          f"plus {MANIFEST} (sha256 {digest}) and .gitattributes, in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
