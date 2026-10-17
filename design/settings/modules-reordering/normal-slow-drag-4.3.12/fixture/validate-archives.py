#!/usr/bin/env python3
"""Read-only pre-extraction validation for the frozen source and private tools."""
from pathlib import PurePosixPath
import sys
import tarfile

if len(sys.argv) != 3:
    raise SystemExit("Expected SOURCE_TAR TOOLS_TAR")
for archive_path in sys.argv[1:]:
    with tarfile.open(archive_path, "r:gz") as archive:
        seen = set()
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            if (path.is_absolute() or ".." in path.parts or not path.parts
                    or member.name in seen or not (member.isfile() or member.isdir())):
                raise SystemExit("Unsafe or duplicate archive entry: " + member.name)
            seen.add(member.name)
print("Both archives contain only distinct, relative files/directories")
