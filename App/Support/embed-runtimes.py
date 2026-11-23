#!/usr/bin/env python3
"""Embed independent user-space runtimes and their licenses; no privileged helper."""
import hashlib
import json
import re
import shutil
import subprocess
import sys
import os
from pathlib import Path

resources = Path(sys.argv[1])
resources.mkdir(parents=True, exist_ok=True)
identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or '-'
root = Path(__file__).resolve().parent.parent.parent
# The combined payload also carries the MariaDB server; the base payload is PostgreSQL/PHP only.
payload = root / 'Local/Runtime/Combined Payload'
if os.environ.get('MOKO_BASE_ONLY') == '1' or not payload.is_dir():
    payload = root / 'Local/Runtime/Payload'
fingerprint = hashlib.sha256(identity.encode())
fingerprint.update(Path(__file__).read_bytes())
for file in sorted(payload.rglob('*')):
    fingerprint.update(str(file.relative_to(payload)).encode())
    if file.is_symlink():
        fingerprint.update(os.readlink(file).encode())
    elif file.is_file():
        status = file.stat()
        fingerprint.update(str((status.st_size, status.st_mtime_ns)).encode())
cache = Path(os.environ.get('DERIVED_FILE_DIR', root / 'Local/Resource Embed Cache'))
cache.mkdir(parents=True, exist_ok=True)
stamp = cache / 'moko-runtime-embed.stamp'
state = fingerprint.hexdigest() + ':' + payload.name + ':' + str(resources.resolve())
required = [resources / 'Runtime/PostgreSQL/bin/postgres', resources / 'Runtime/PHP/bin/php',
            resources.parent / 'Frameworks/libpq.5.dylib', resources.parent / 'Frameworks/libmariadb.3.dylib']
if stamp.exists() and stamp.read_text() == state and all(file.is_file() for file in required):
    print('Bundled runtime input is unchanged; existing resources and signatures preserved.')
    sys.exit(0)
# Embed runtimes and dynamically linked LGPL connector; never depend on a Homebrew prefix.
for name, destination in [('Runtime', resources / 'Runtime'),
                          ('Frameworks', resources.parent / 'Frameworks')]:
    if destination.exists(): shutil.rmtree(destination)
    source = payload / ('Resources/Runtime' if name == 'Runtime' else name)
    shutil.copytree(source, destination, symlinks=True)

# Source URLs and hashes are portable; the build machine's Cellar hint is not a runtime setting.
for metadata in (resources / 'Runtime').rglob('*.json'):
    records = json.loads(metadata.read_text())
    values = records.values() if metadata.name == 'Manifest.json' else [records]
    for record in values:
        if isinstance(record, dict) and isinstance(record.get('bottle'), dict):
            record['bottle'].pop('cellar', None)
    metadata.write_text(json.dumps(records, indent=2) + '\n')

for path in (resources / 'Runtime', resources.parent / 'Frameworks'):
    for binary in path.rglob('*'):
        if not binary.is_file() or binary.is_symlink(): continue
        if 'Mach-O' in subprocess.check_output(['file', str(binary)], text=True):
            subprocess.run(['codesign', '--force', '--sign', identity, '--options', 'runtime',
                            '--timestamp=none', str(binary)], check=True, capture_output=True)
stamp.write_text(state)
