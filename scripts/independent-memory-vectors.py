#!/usr/bin/env python3
"""Generate deep-tree digests with pinned Servil over stdin (no argv limit)."""
import argparse
import json
from pathlib import Path
import subprocess
from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
lengths = [32 * n + delta for n in (2048, 4096, 8192, 16384, 32768) for delta in (-1, 0, 1)]
lengths += [1024 * n + delta for n in (63, 65, 127, 129, 255, 257, 511, 513, 1023, 1025) for delta in (0, 1)]
inputs, vectors = [], []
for index, length in enumerate(lengths):
    seed = index.to_bytes(32, 'big')
    # _misaligned starts the message at backing+128+offset, which is
    # (96+offset) bytes into backing's byte payload.
    offset = index % 31 + 1
    start = 96 + offset
    backing = b''.join(keccak.new(digest_bits=256, data=seed + i.to_bytes(32, 'big')).digest()
                       for i in range(0, length + 256, 32))
    inputs.append(backing[start:start+length])
    vectors.append({'length': length, 'seed': '0x'+seed.hex()})
output = subprocess.run([str(ROOT/'reference/servil/target/release/blake3-reference')],
                        input=''.join(x.hex()+'\n' for x in inputs), text=True,
                        capture_output=True, check=True).stdout.splitlines()
assert len(output) == len(inputs)
for vector, digest in zip(vectors, output):
    vector['digest'] = digest
path = ROOT / 'test/vectors/independent-memory.json'
fixture = json.dumps({'count': len(vectors), 'reference': {
    'repository': 'https://github.com/johnservil/BLAKE3',
    'commit': 'b5b988d8982bea9490c38c79ec4b8c5c2428270c',
    'encoding': 'raw bytes from misaligned alias into keccak256(seed || byte_offset) words',
}, 'vectors': vectors}, indent=2)+'\n'
if args.check:
    assert path.read_text() == fixture, 'Independent memory vectors differ from pinned reference'
else:
    path.write_text(fixture)
print(f'{len(vectors)} fixtures, {max(lengths)} bytes maximum')
