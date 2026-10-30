# BLAKE3 for Solidity

An unkeyed BLAKE3-256 library with `internal pure` overloads for `uint256[1]`
through `uint256[8]`, `uint256[]`, and `bytes`. The measured library costs for
one, two, and three words are **7,043**, **7,297**, and **13,777 gas**.

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
| 0 | 0 | — | 6,842 |
| 1 | 32 | 7,043 | 7,098 |
| 2 | 64 | 7,297 | 7,346 |
| 3 | 96 | 13,777 | 13,832 |
| 4 | 128 | 14,022 | 14,080 |
| 5 | 160 | 20,511 | 20,566 |
| 6 | 192 | 20,750 | 20,814 |
| 7 | 224 | 27,242 | 27,300 |
| 8 | 256 | 27,490 | 27,548 |

For contract integration, the next table measures the complete external
function frame in [HashHarness](test/helpers/HashHarness.sol), including its
ABI decoding and return. It excludes the caller's call charge and transaction
intrinsic/calldata gas. These values come from `snapshotGasLastFrame` and agree
with `forge test --gas-report`; see [snapshots/external.json](snapshots/external.json).

| Words | Fixed array function | Dynamic array function |
|---:|---:|---:|
| 0 | — | 7,283 |
| 1 | 7,427 | 7,607 |
| 2 | 7,796 | 7,923 |
| 3 | 14,429 | 14,477 |
| 4 | 14,635 | 14,793 |
| 5 | 21,286 | 21,347 |
| 6 | 21,656 | 21,663 |
| 7 | 28,103 | 28,217 |
| 8 | 28,507 | 28,533 |
| 32 | — | 110,976 |
| 33 | — | 124,009 |
| 64 | — | 227,383 |

The array benchmark suites enforce a **15,000 gas ceiling** on fixed sizes 1–3.
The harness exposing all ten overloads has a 15,337-byte runtime, below the
24,576-byte EIP-170 limit. Callers with fewer entry points can be smaller.

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
| `[uint256(1), 2, 3]` | 96 | 13,874 |
| `abi.encodePacked(uint256(1), uint256(2), uint256(3))` | 96 | 13,992 |
| `abi.encodePacked(uint8(1), uint8(2), uint8(3))` | 3 | 7,278 |

The compact example saves about **48%**, including the encoding work. Values
are recorded in [snapshots/construction.json](snapshots/construction.json).

For preallocated raw-byte inputs, the following table uses the same measurement
methods as the array tables. It excludes constructing the input. The byte at
index `i` is `(i + 1) % 256`; benchmark cases named `words1` through `words8`
also check the identical full-word encodings used by the array benchmarks.

| Byte length | Library hash | External function |
|---:|---:|---:|
| 0 | 6,836 | 7,378 |
| 3 | 7,127 | 7,675 |
| 24 | 7,127 | 7,675 |
| 32 | 7,092 | 7,640 |
| 33 | 7,407 | 7,961 |
| 64 | 7,340 | 7,894 |
| 65 | 13,861 | 14,421 |
| 96 | 13,826 | 14,386 |
| 128 | 14,074 | 14,640 |
| 256 | 27,542 | 28,132 |
| 1024 | 108,350 | 109,087 |
| 1025 | 121,344 | 122,093 |

[test/BytesGas.t.sol](test/BytesGas.t.sol) records these results in
[snapshots/library_bytes.json](snapshots/library_bytes.json) and
[snapshots/external_bytes.json](snapshots/external_bytes.json). The small extra
cost for a partial word is the mask that discards bytes past the logical end.
All bytes benchmarks through 96 input bytes enforce a 15,000 gas ceiling.

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
inside each EVM word. The spare bits isolate addition carries. Multiplication
by `2**32 + 1`, followed by a shift and mask, rotates all four lanes at once.
The seven rounds are unrolled, with message permutations resolved by the
generator. Two EVM words retain the complete 64-byte message block.

The explicit compression workspace is 160 bytes. The iterative chunk tree
uses another 64 bytes per stacked chaining value, with logarithmic space in
the input length. The Solidity compiler may allocate additional spill slots.
Scratch storage begins at the free-memory pointer, is temporary, and does not
modify the input array, free-memory pointer, or zero slot.

```sh
python3 scripts/generate.py
python3 scripts/generate.py --check
forge fmt --check src test oracle-test
```

[CI](.github/workflows/test.yml) runs formatting, regeneration checks, Foundry
tests and gas snapshots, native differential fuzzing, and Noir execution.
