#!/usr/bin/env python3
"""Prepare a new private runtime from a python-build-standalone installation."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=pathlib.Path)
    parser.add_argument('destination', type=pathlib.Path)
    args = parser.parse_args()
    source = args.source.resolve()
    version = subprocess.check_output([str(source/'bin/python3'), '-I', '-B', '-c',
        'import sys; print("%d.%d" % sys.version_info[:2])'], text=True).strip()
    destination = args.destination
    destination.mkdir(parents=True)
    (destination/'bin').mkdir()
    (destination/'lib').mkdir()
    binary = source/f'bin/python{version}'
    library = source/f'lib/libpython{version}.dylib'
    shutil.copy2(binary, destination/f'bin/python{version}')
    shutil.copy2(library, destination/'lib'/library.name)
    ignored = shutil.ignore_patterns('__pycache__', '*.pyc', 'site-packages', 'test', 'tests',
        'ensurepip', 'idlelib', 'tkinter', 'turtledemo', '_tkinter*', 'config-*')
    shutil.copytree(source/f'lib/python{version}', destination/f'lib/python{version}', ignore=ignored)
    (destination/'RUNTIME.json').write_text(json.dumps({
        'version': version,
        'source': 'https://github.com/astral-sh/python-build-standalone',
        'build': (source/'BUILD').read_text().strip(),
        'sourceBinarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'sourceLibrarySHA256': hashlib.sha256(library.read_bytes()).hexdigest(),
        'license': f'lib/python{version}/LICENSE.txt'
    }, indent=2))
    print(destination.resolve())


if __name__ == '__main__':
    main()
