"""Holds the vendored ATP drop to exactly what its SHA256SUMS lists.

platform/android/java/third_party/atp is ATP's wire module and provider kit, copied byte for byte from the ATP
repository by its export script, and SHA256SUMS lists every file of the drop with its hash. Every listed file must match
its hash, and no other file may be in the drop's folder: only GDatp's own two build.gradle.kts files and Gradle's build
output are outside the drop. A change comes in as a new drop, never as an edit here, which the next export would undo.

Run from the repository root: python gdatp/checks/atp_drop_check.py [another drop folder]
"""

import hashlib
import os
import sys
from pathlib import Path

DROP = Path("platform/android/java/third_party/atp")
# GDatp's own files in the drop's folder.
OWN = {"SHA256SUMS", "wire/build.gradle.kts", "provider/build.gradle.kts"}
# Folders of build output, which are not looked into.
BUILD_OUTPUT = {"build", ".gradle", ".kotlin"}


def main() -> int:
    drop = Path(sys.argv[1]) if len(sys.argv) > 1 else DROP
    problems: list = []
    listed = {}
    for line in (drop / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, _, name = line.partition("  ")
        if not name:
            problems.append(f"SHA256SUMS: a line without a hash and a file: {line}")
        else:
            listed[name] = digest
    if not listed:
        problems.append("SHA256SUMS lists no files")
    for name, digest in sorted(listed.items()):
        path = drop / name
        if not path.is_file():
            problems.append(f"{name}: listed, but missing")
        elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            problems.append(f"{name}: differs from the drop")
    for folder, subfolders, files in os.walk(drop):
        subfolders[:] = sorted(sub for sub in subfolders if sub not in BUILD_OUTPUT)
        for file in sorted(files):
            name = (Path(folder) / file).relative_to(drop).as_posix()
            if name not in listed and name not in OWN:
                problems.append(f"{name}: in the drop's folder, but not in SHA256SUMS")
    if problems:
        print("The vendored ATP drop is not what SHA256SUMS lists:")
        print("\n".join(problems))
        return 1
    print(f"{len(listed)} files of the ATP drop, each matching SHA256SUMS, and no others")
    return 0


if __name__ == "__main__":
    sys.exit(main())
