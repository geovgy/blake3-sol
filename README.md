# BLAKE3 for Solidity

An unkeyed BLAKE3-256 library with `internal pure` overloads for `uint256[1]`
through `uint256[8]`, `uint256[]`, and `bytes`. The measured library costs for
one, two, and three words are **6,256**, **6,400**, and **12,203 gas**.

```solidity
import {BLAKE3Lib} from "./src/BLAKE3Lib.sol";

contract Example {
    function example(uint256 a, uint256 b, uint256 c, uint256[] memory values)
        external pure returns (uint256, uint256, uint256, uint256)
    {
        return (
            BLAKE3Lib.hash([a]),
            BLAKE3Lib.hash([a, b]),
            BLAKE3Lib.hash([a, b, c]),
            BLAKE3Lib.hash(values)
        );
    }
}
```

Each value contributes exactly 32 **big-endian** bytes, in array order, with
no length prefix. For a dynamic array `values`, the message is
`abi.encodePacked(values)`. Fixed and dynamic arrays containing the same words
produce the same result. Cast the first element of a literal when needed:
`BLAKE3Lib.hash([uint256(1), 2, 3])`.

The `hash(bytes memory data)` overload hashes exactly `data.length` raw bytes,
including lengths that are not multiples of 32. It ignores memory padding and
adds no length prefix. For example:

```solidity
uint256 result = BLAKE3Lib.hash(bytes("abc"));
uint256 sameAsArray = BLAKE3Lib.hash(abi.encodePacked(values));
```

The second call produces the same digest as `BLAKE3Lib.hash(values)`.

The return value contains the entire 32-byte digest, interpreted as a big-endian
integer. `bytes32(result)` gives the usual digest bytes. For example,
`hash([uint256(1)])` returns
`0x55bbfb5b05f80543bd662a7b7a74980a2992612798087fa24e1fc86b8e8508e4`.
An empty dynamic array returns the standard empty-message digest,
`0xaf1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262`.

Dynamic arrays and raw bytes support the full BLAKE3 chunk tree, including messages larger
than 1,024 bytes, subject to available EVM gas. The API computes the standard
unkeyed, 32-byte hash; keyed hashing and extended output are outside this API.
The library is embedded in the caller and requires no library deployment or
external linking.

## Build and test

The project was initialized with `forge init --empty --shallow .`. Use Foundry
1.8.5 and the settings in [foundry.toml](foundry.toml): Solidity 0.8.30,
`via_ir = true`, optimizer enabled with **1,000,000 runs**, and Cancun EVM.
The gas figures depend on these settings; lower optimizer runs increase costs.

```sh
forge install                 # only needed if dependencies were not cloned
forge build --sizes
forge test
forge test --match-path 'test/*Gas.t.sol' --gas-report --gas-snapshot-check true
```

The default suite runs offline using committed reference vectors. The native
reference and Noir checks below are separate, reproducible integration checks.

## Gas measurements

Inputs contain the words `[1, 2, ..., n]`. The following measurements surround
the internal library call with Foundry's `startSnapshotGas`/`stopSnapshotGas`;
the input array is already allocated. They include the hash's scratch memory
expansion and exclude input construction, transaction intrinsic gas, calldata,
and external calls. Values are recorded in [snapshots/library.json](snapshots/library.json)
by [test/LibraryGas.t.sol](test/LibraryGas.t.sol).

| Words | Input bytes | `uint256[n]` | `uint256[]` |
|---:|---:|---:|---:|
| 0 | 0 | — | 103 |
| 1 | 32 | 6,256 | 6,402 |
| 2 | 64 | 6,400 | 6,546 |
| 3 | 96 | 12,203 | 12,409 |
| 4 | 128 | 12,350 | 12,553 |
| 5 | 160 | 18,645 | 18,748 |
| 6 | 192 | 18,783 | 18,892 |
| 7 | 224 | 24,713 | 24,816 |
| 8 | 256 | 24,857 | 24,960 |

For contract integration, the next table measures the complete external
function frame in [HashHarness](test/helpers/HashHarness.sol), including its
ABI decoding and return. It excludes the caller's call charge and transaction
intrinsic/calldata gas. These values come from `snapshotGasLastFrame` and agree
with `forge test --gas-report`; see [snapshots/external.json](snapshots/external.json).

| Words | Fixed array function | Dynamic array function |
|---:|---:|---:|
| 0 | — | 529 |
| 1 | 6,635 | 6,896 |
| 2 | 6,891 | 7,108 |
| 3 | 12,851 | 13,039 |
| 4 | 12,953 | 13,251 |
| 5 | 19,399 | 19,517 |
| 6 | 19,674 | 19,729 |
| 7 | 25,559 | 25,721 |
| 8 | 25,859 | 25,933 |
| 32 | — | 100,383 |
| 33 | — | 112,837 |
| 64 | — | 206,115 |

The array benchmarks enforce a **10,000 gas ceiling** through two words,
then **13,000 gas** for internal calls and **14,000 gas** for external functions
through four words. The harness exposing all ten overloads has a 16,497-byte
runtime, below the 24,576-byte EIP-170 limit.

Inputs up to 64 bytes meet the intended 10,000-gas upper target;
65–128 byte inputs still require more than 10,000 gas.
For comparison, the previous fixed-array costs and the current measurements are:

| Words | Previous library gas | Current library gas | Reduction |
|---:|---:|---:|---:|
| 1 | 7,043 | 6,256 | 11.2% |
| 2 | 7,297 | 6,400 | 12.3% |
| 3 | 13,777 | 12,203 | 11.4% |
| 4 | 14,022 | 12,350 | 11.9% |

### Bytes and compact encoding

The bytes overload uses the same compression engine. For the same input bytes,
its hashing cost is essentially the same as the array overloads. Encoding
full-width `uint256` values with `abi.encodePacked` still contributes 32 bytes
per value. More substantial savings come from using a shorter encoding that
fits into fewer 64-byte compression blocks.

For example, three values of type `uint8` occupy just three bytes:

```solidity
uint256 full = BLAKE3Lib.hash(abi.encodePacked(uint256(1), uint256(2), uint256(3)));
uint256 compact = BLAKE3Lib.hash(abi.encodePacked(uint8(1), uint8(2), uint8(3)));
```

These encode different messages and produce different digests. The first
matches the three-word array hash. Use a compact format when the values fit
the selected types and the caller and verifier agree on that format.

The following measurements **include constructing the input and hashing** in
one region, using the expressions above and the values 1, 2, 3:

| Input | Bytes | Gas including construction |
|---|---:|---:|
| `[uint256(1), 2, 3]` | 96 | 12,083 |
| `abi.encodePacked(uint256(1), uint256(2), uint256(3))` | 96 | 12,557 |
| `abi.encodePacked(uint8(1), uint8(2), uint8(3))` | 3 | 6,563 |

The compact example saves about **48%**, including the encoding work. Values
are recorded in [snapshots/construction.json](snapshots/construction.json).

For preallocated raw-byte inputs, the following table uses the same measurement
methods as the array tables. It excludes constructing the input. The byte at
index `i` is `(i + 1) % 256`; benchmark cases named `words1` through `words8`
also check the identical full-word encodings used by the array benchmarks.

| Byte length | Library hash | External function |
|---:|---:|---:|
| 0 | 94 | 624 |
| 3 | 6,412 | 6,951 |
| 24 | 6,412 | 6,951 |
| 32 | 6,390 | 6,929 |
| 33 | 6,575 | 7,120 |
| 64 | 6,534 | 7,079 |
| 65 | 12,419 | 12,970 |
| 96 | 12,397 | 12,948 |
| 128 | 12,541 | 13,098 |
| 256 | 24,887 | 25,532 |
| 1024 | 97,703 | 98,494 |
| 1025 | 110,107 | 110,908 |

[test/BytesGas.t.sol](test/BytesGas.t.sol) records these results in
[snapshots/library_bytes.json](snapshots/library_bytes.json) and
[snapshots/external_bytes.json](snapshots/external_bytes.json). The small extra
cost for a partial word is the mask that discards bytes past the logical end.
Bytes benchmarks enforce a 10,000 gas ceiling through 64 bytes, then
13,000 gas internally and 14,000 gas externally through 128 bytes.

## Correctness checks

The oracle is built from the exact
[v0.8.0 release](https://github.com/johnservil/BLAKE3/releases/tag/v0.8.0%2Bb3c5efc7c975d903762dea809066f7c0a0603861),
commit `b5b988d8982bea9490c38c79ec4b8c5c2428270c`. Its Rust dependency and transitive
dependencies are pinned in [reference/servil/Cargo.lock](reference/servil/Cargo.lock).
The tool calls `initialize()` and `convenience::hash()` from that release.

```sh
# Tested with Rust 1.99.1; requires a C compiler for the reference's assembly.
cargo build --release --locked --manifest-path reference/servil/Cargo.toml
python3 scripts/vectors.py --check
FOUNDRY_PROFILE=oracle forge test -vv
```

The checks cover:

- **99 committed word-array vectors**, from empty input through **32,800 bytes**, checked
  against the release and then Solidity. Patterns include zeros, all ones,
  ascending bytes, and deterministic random words. Lengths cover both sides
  of block, chunk, and multiple tree boundaries, including uneven trees.
  All fixed overloads are checked wherever the vector has 1–8 words.
- **318 raw-byte vectors**, including every length from 0 through 129 and
  boundaries around blocks and chunk trees through 32,769 bytes, checked in
  both the library and external bytes entry point. The existing word-array
  vectors are also checked through the bytes overload.
- **256 fuzz cases** comparing fixed/dynamic calls and preserving input memory,
  plus tests of dirty scratch memory, repeated calls, and surrounding allocations.
- **256 bytes fuzz cases** and all 130 short lengths with deliberately nonzero
  padding, checking that hashing ignores padding and preserves input memory.
- **128 live differential fuzz cases** for dynamic arrays of up to 1,025 words,
  **128 cases checking all eight fixed overloads**, and **128 raw-byte cases**
  of up to 8,193 bytes against the native oracle: 1,280 native comparisons per
  integration run.
- **128 additional short-byte fuzz cases** with dirty padding, plus **390 native
  comparisons** covering each length from 0–129 with zero, all-ones, and alternating
  `0x55`/`0xaa` bytes. Both internal and external bytes functions must match the
  release and preserve the complete input allocation, including dirty padding.
  The default oracle profile makes **1,798 native comparisons** in total.

The optimized implementation also passes this larger run with **6,022 native
comparisons**, including all eight fixed overloads:

```sh
FOUNDRY_PROFILE=oracle forge test --fuzz-runs 512 --fuzz-seed 0xb1a3 -vv
```

[Noir's standard-library black box](https://noir-lang.org/docs/libraries/standard_library/cryptographic_primitives/hashes#blake3)
is checked independently with Nargo **1.0.0-rc.3**, compiler commit
`5a7ee9bf5ed8973076df7bb0d2b723024db09ae7`:

```sh
noirup --version 1.0.0-rc.3    # if this version is not installed
python3 scripts/vectors.py --check --noir
```

This generates the [Noir program](reference/noir/src/main.nr) and its
`Prover.toml` from the same vectors, then executes `std::hash::blake3` against
the release digests. All **333 cases from 0–1,024 bytes** match. Nonempty inputs
are runtime witnesses; the script also verifies **332 BLAKE3 black-box opcodes**
in the compiled circuit. The empty input is a local constant because Noir
rejects empty array parameters. The selected Noir version limits the black box
to 1,024 bytes; longer Solidity inputs are checked against the release.
These checks execute the black-box solver; they do not generate a ZK proof.

## Implementation and regeneration

[src/BLAKE3Lib.sol](src/BLAKE3Lib.sol) uses Yul throughout the hash engine.
Four independent 32-bit lanes occupy the lower halves of four 64-bit lanes
inside each EVM word, in descending order at offsets 192, 128, 64, and 0.
The spare bits isolate addition carries. Multiplication by `2**32 + 1`,
followed by a shift and mask, rotates all four lanes at once. Each addition
must discard its carry bits before the next XOR and rotation.

The generator resolves all seven message permutations and the diagonal lane
rotations. It keeps message words in their original order and swaps bytes
inside each u32 on input and output. This removes the full-word reversal
stages. The mixing function uses a measured argument and return order to
reduce EVM stack shuffling.

Compression takes its block and chaining values in registers. The chunk loop
processes full nonfinal blocks before a separate final block, retaining
`CHUNK_END` on exact block boundaries. Inputs through 128 bytes use one or two
compressions with counter zero and the appropriate root flags; empty input
returns the standard digest constant.

The iterative chunk tree uses 64 bytes per stacked chaining value, with
logarithmic space in the input length. The compiler may reserve spill slots.
Temporary tree storage starts at the free-memory pointer; the library preserves
the input, free-memory pointer, and zero slot.

```sh
python3 scripts/generate.py
python3 scripts/generate.py --check
forge fmt --check src test oracle-test
```

[CI](.github/workflows/test.yml) runs formatting, regeneration checks, Foundry
tests and gas snapshots, native differential fuzzing, and Noir execution.
