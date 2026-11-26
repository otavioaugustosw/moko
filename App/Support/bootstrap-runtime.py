#!/usr/bin/env python3
"""Fetch or rebuild the runtimes a moko build embeds, into Local/Runtime.

    python3 App/Support/bootstrap-runtime.py                  download the pinned development payload
    python3 App/Support/bootstrap-runtime.py --from-source    rebuild it from the published source kits
    python3 App/Support/bootstrap-runtime.py --check          report missing or mismatched runtime files
    python3 App/Support/bootstrap-runtime.py --package OUT    archive Local/Runtime and pin it
    python3 App/Support/bootstrap-runtime.py --write-inputs   list Combined Payload in Runtime Inputs.xcfilelist

The build needs two trees: Local/Runtime/Payload (PostgreSQL, PHP and Connector/C; headers and
libraries the app links) and Local/Runtime/Combined Payload (the same plus MariaDB Server; what
embed-runtimes.py copies into the app). Every download is checked against the SHA-256 pinned in
App/Config/Runtime.payload.json. Runs on Apple Silicon macOS; --check and the downloads work anywhere.
"""
import argparse
import hashlib
import json
import lzma
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'App'
RUNTIME = ROOT / 'Local/Runtime'
DOWNLOADS = RUNTIME / 'Downloads'
RECIPES = APP / 'Support/Runtime'
PIN = APP / 'Config/Runtime.payload.json'
LOCK = APP / 'Config/Runtime.lock.json'
TOOLS = APP / 'Config/Runtime.build-tools.json'
INPUTS = APP / 'Config/Runtime Inputs.xcfilelist'
TREES = ['Payload', 'Combined Payload']
# Present in both source kits with kit-specific content; everything else shared must be identical.
KIT_SPECIFIC = {'Runtime.lock.json', 'Kit Files.json'}


class Failure(Exception):
    pass


def release_url(pin, tag, asset):
    return f'https://github.com/{pin["repository"]}/releases/download/{tag}/{asset}'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def download(url, name, expected_sha256, expected_bytes=None):
    """Download once into Local/Runtime/Downloads and return the verified file."""
    target = DOWNLOADS / name
    if target.exists() and sha256(target) == expected_sha256:
        print('Using verified download:', target)
        return target
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(name + '.partial')
    print('Downloading', url, flush=True)
    digest, size = hashlib.sha256(), 0
    with urllib.request.urlopen(url) as response, partial.open('wb') as output:
        for block in iter(lambda: response.read(1 << 20), b''):
            digest.update(block)
            size += len(block)
            output.write(block)
    if expected_bytes is not None and size != expected_bytes:
        partial.unlink()
        raise Failure(f'{name}: expected {expected_bytes} bytes, got {size}')
    if digest.hexdigest() != expected_sha256:
        partial.unlink()
        raise Failure(f'{name}: SHA-256 mismatch (expected {expected_sha256}, got {digest.hexdigest()})')
    partial.replace(target)
    return target


def inside(path, root):
    return os.path.realpath(path) == os.path.realpath(root) or \
        os.path.realpath(path).startswith(os.path.realpath(root) + os.sep)


def extract_tar(archive, destination):
    """Extract regular files, directories and symlinks that stay inside destination."""
    with tarfile.open(archive) as contents:
        members = contents.getmembers()
        for member in members:
            target = destination / member.name
            if member.name.startswith('/') or '..' in Path(member.name).parts or not inside(target, destination):
                raise Failure('unsafe path in payload: ' + member.name)
            if not (member.isfile() or member.isdir() or member.issym()):
                raise Failure('unsupported entry in payload: ' + member.name)
            if member.issym():
                if member.linkname.startswith('/') or not inside(target.parent / member.linkname, destination):
                    raise Failure('payload symlink escapes the payload: ' + member.name)
        options = {'filter': 'tar'} if hasattr(tarfile, 'tar_filter') else {}
        contents.extractall(destination, members=members, **options)


def extract_kit(archive, destination):
    """Extract a source kit's 'Corresponding Source' folder, merging with a kit extracted before."""
    prefix = 'Corresponding Source/'
    with zipfile.ZipFile(archive) as contents:
        for info in contents.infolist():
            if not info.filename.startswith(prefix) or info.is_dir():
                continue
            relative = info.filename[len(prefix):]
            if Path(relative).name in KIT_SPECIFIC and '/' not in relative:
                continue
            target = destination / relative
            if relative.startswith('/') or '..' in Path(relative).parts or not inside(target, destination):
                raise Failure('unsafe path in source kit: ' + info.filename)
            data = contents.read(info)
            if target.exists():
                if target.read_bytes() != data:
                    raise Failure('source kits disagree on ' + relative)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        return json.loads(contents.read(prefix + 'Runtime.lock.json'))


def ensure_replaceable(force):
    existing = [tree for tree in TREES if (RUNTIME / tree).exists()]
    if existing and not force:
        raise Failure('Local/Runtime already has ' + ' and '.join(existing) + '; pass --force to replace it')


def replace_trees(staging, force):
    """Move Payload and Combined Payload from staging into Local/Runtime."""
    for tree in TREES:
        if not (staging / tree).is_dir():
            raise Failure(f'the result has no "{tree}" folder')
    ensure_replaceable(force)
    for tree in TREES:
        if (RUNTIME / tree).exists():
            shutil.rmtree(RUNTIME / tree)
        shutil.move(str(staging / tree), str(RUNTIME / tree))


def fetch_payload(pin, force):
    payload = pin['payload']
    if not payload.get('sha256'):
        raise Failure('no prebuilt payload is pinned yet in App/Config/Runtime.payload.json.\n'
                      'Rebuild from source with --from-source, then publish one with --package.')
    ensure_replaceable(force)
    archive = download(release_url(pin, payload['tag'], payload['asset']), payload['asset'],
                       payload['sha256'], payload.get('bytes'))
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=RUNTIME, prefix='.staging-') as staging:
        print('Extracting', archive.name, flush=True)
        extract_tar(archive, Path(staging))
        replace_trees(Path(staging), force)


def require_build_host():
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise Failure('--from-source needs Apple Silicon macOS')
    missing = [tool for tool in ['xcrun', 'clang', 'cmake', 'make', 'otool', 'install_name_tool', 'codesign']
               if shutil.which(tool) is None]
    if missing:
        raise Failure('missing build tools: ' + ', '.join(missing) + ' (install Xcode command-line tools and CMake)')


def build_from_source(pin, work, jobs, force):
    require_build_host()
    ensure_replaceable(force)
    work = work.resolve()
    if ' ' in str(work) or '@' in str(work):
        raise Failure(f'the build directory cannot contain spaces or "@" (upstream tools reject them): {work}')
    lock = json.loads(LOCK.read_text())
    # Not work/Sources: build-runtimes.py unpacks upstream trees there, under similar names.
    sources = work / 'Kit'
    if sources.exists():
        shutil.rmtree(sources)
    sources.mkdir(parents=True)
    for asset in pin['sources']['assets']:
        archive = download(release_url(pin, pin['sources']['tag'], asset['name']), asset['name'],
                           asset['sha256'], asset.get('bytes'))
        print('Extracting', archive.name, flush=True)
        for name, record in extract_kit(archive, sources).items():
            if lock.get(name) != record:
                raise Failure(f'{asset["name"]} pins {name} differently from App/Config/Runtime.lock.json')
    python = sys.executable
    common = ['--sources', sources, '--manifest', LOCK, '--work', work, '--cache', work / 'Cache']
    for component in ['postgresql', 'php', 'connector', 'server']:
        print(f'\n== Building {component} ==', flush=True)
        subprocess.run([python, RECIPES / 'build-runtimes.py', *common, '--tools', TOOLS,
                        '--jobs', str(jobs), '--component', component], check=True)
    staging = work / 'Assembled'
    if staging.exists():
        shutil.rmtree(staging)
    for tree, flags in [('Payload', ['--base']), ('Combined Payload', [])]:
        print(f'\n== Assembling {tree} ==', flush=True)
        output = work / ('Base' if flags else 'Combined')
        subprocess.run([python, RECIPES / 'assemble-runtime.py', '--manifest', LOCK, '--sources', sources,
                        '--work', work, '--cache', work / 'Cache', '--output', output, *flags], check=True)
        staging.mkdir(exist_ok=True)
        shutil.move(str(output), str(staging / tree))
    RUNTIME.mkdir(parents=True, exist_ok=True)
    replace_trees(staging, force)
    # A rebuilt payload can add or drop files (contrib modules, for example); keep Xcode's input list exact.
    write_inputs()


def write_inputs():
    """List every entry of Combined Payload in Runtime Inputs.xcfilelist, so Xcode reruns the embed phase."""
    combined = RUNTIME / 'Combined Payload'
    if not combined.is_dir():
        raise Failure('Local/Runtime has no "Combined Payload" to list')
    prefix = '$(SRCROOT)/../Local/Runtime/Combined Payload'
    entries = [prefix + '/' + path.relative_to(combined).as_posix()
               for path in combined.rglob('*') if path.name != '.DS_Store']
    lines = sorted(['$(SRCROOT)/../App/Support/embed-runtimes.py', prefix, *entries])
    INPUTS.write_text('\n'.join(lines) + '\n')
    print(f'Listed {len(entries)} payload entries in {INPUTS.relative_to(ROOT)}.')


def check():
    """Return a list of problems with Local/Runtime; empty means a build can find what it needs."""
    problems = []
    expected = []
    for line in INPUTS.read_text().splitlines():
        line = line.strip()
        if line and '/Local/Runtime/' in line:
            expected.append(Path(os.path.normpath(line.replace('$(SRCROOT)', str(APP)))))
    required = [RUNTIME / 'Payload' / path for path in
                ['Headers/mariadb/mysql.h', 'Headers/PostgreSQL/libpq-fe.h',
                 'Frameworks/libpq.5.dylib', 'Frameworks/libmariadb.3.dylib']]
    missing = [path for path in required + expected if not os.path.lexists(path)]
    if missing:
        problems.append(f'{len(missing)} runtime files are missing, for example:')
        problems += ['  ' + str(path.relative_to(ROOT)) for path in missing[:10]]
    lock = json.loads(LOCK.read_text())
    for tree in TREES:
        manifest = RUNTIME / tree / 'Resources/Runtime/Manifest.json'
        if not manifest.exists():
            continue
        for name, record in json.loads(manifest.read_text()).items():
            def key(entry):
                return entry['version'], (entry.get('bottle') or {}).get('sha256'), (entry.get('source') or {}).get('checksum')
            if name not in lock or key(lock[name]) != key(record):
                problems.append(f'{tree}: {name} {record["version"]} does not match App/Config/Runtime.lock.json')
    combined = RUNTIME / 'Combined Payload'
    if combined.is_dir():
        listed = {str(path) for path in expected}
        extra = [path for path in combined.rglob('*') if str(path) not in listed and path.name != '.DS_Store']
        if extra:
            print(f'Note: {len(extra)} files in Combined Payload are not listed in Runtime Inputs.xcfilelist; '
                  'Xcode will not rerun the embed phase when only they change.')
    return problems


def package(output, force):
    problems = check()
    if problems:
        raise Failure('Local/Runtime is incomplete; fix it before packaging:\n' + '\n'.join(problems))
    output = output.resolve()
    if output.exists() and not force:
        raise Failure(f'{output} exists; pass --force to overwrite it')
    print('Archiving Local/Runtime into', output, flush=True)

    def clean(info):
        if Path(info.name).name == '.DS_Store':
            return None
        info.uid = info.gid = 0
        info.uname = info.gname = ''
        return info

    with lzma.open(output, 'wb', preset=6) as compressed, \
            tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
        for tree in TREES:
            archive.add(RUNTIME / tree, arcname=tree, filter=clean)
    digest, size = sha256(output), output.stat().st_size
    pin = json.loads(PIN.read_text())
    pin['payload'].update(asset=output.name, sha256=digest, bytes=size)
    PIN.write_text(json.dumps(pin, indent=2) + '\n')
    print(f'{digest}  {output.name}\n{size} bytes')
    print(f'Pinned in {PIN.relative_to(ROOT)}. Upload it to the release "{pin["payload"]["tag"]}" '
          f'and link that release to "{pin["sources"]["tag"]}".')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--from-source', action='store_true', help='rebuild every runtime from the source kits')
    mode.add_argument('--check', action='store_true', help='only report what Local/Runtime is missing')
    mode.add_argument('--package', type=Path, metavar='OUT', help='archive Local/Runtime as OUT (.tar.xz) and pin it')
    mode.add_argument('--write-inputs', action='store_true',
                      help='regenerate App/Config/Runtime Inputs.xcfilelist from Local/Runtime/Combined Payload')
    parser.add_argument('--force', action='store_true', help='replace an existing Local/Runtime or output file')
    parser.add_argument('--work', type=Path, default=Path(tempfile.gettempdir()) / 'moko-runtime-build',
                        help='build directory for --from-source, without spaces or "@" (default: %(default)s)')
    parser.add_argument('--jobs', type=int, default=os.cpu_count() or 4, help='parallel build jobs')
    args = parser.parse_args()
    pin = json.loads(PIN.read_text())
    try:
        if args.check:
            problems = check()
            print('\n'.join(problems) if problems else 'Local/Runtime has everything the build needs.')
            return 1 if problems else 0
        if args.package:
            package(args.package, args.force)
            return 0
        if args.write_inputs:
            write_inputs()
            return 0
        if args.from_source:
            build_from_source(pin, args.work, args.jobs, args.force)
        else:
            fetch_payload(pin, args.force)
        problems = check()
        if problems:
            raise Failure('the runtime was installed but is incomplete:\n' + '\n'.join(problems))
        print('Local/Runtime is ready. Generate the project with `cd App && xcodegen`.')
        return 0
    except (Failure, subprocess.CalledProcessError, OSError) as error:
        print('error:', error, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
