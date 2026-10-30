// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BLAKE3Lib} from "../src/BLAKE3Lib.sol";

/// @dev Independent differential checks for valid noncanonical memory layouts.
contract IndependentMemoryTest is Test {
    function _oracle(bytes memory data) private returns (uint256) {
        string[] memory command = new string[](2);
        command[0] = "reference/servil/target/release/blake3-reference";
        command[1] = vm.toString(data);
        return abi.decode(vm.ffi(command), (uint256));
    }

    function _fill(bytes memory data, bytes32 seed) private pure {
        assembly ("memory-safe") {
            mstore(0, seed)
            for { let i := 0 } lt(i, mload(data)) { i := add(i, 32) } {
                mstore(32, i)
                mstore(add(add(data, 32), i), keccak256(0, 64))
            }
        }
    }

    function _misaligned(uint256 n, uint256 offset, bytes32 seed)
        private
        pure
        returns (bytes memory backing, bytes memory data)
    {
        backing = new bytes(n + 256);
        _fill(backing, seed);
        assembly ("memory-safe") {
            data := add(add(backing, 96), offset)
            mstore(data, n)
        }
    }

    function _checkMemory(bytes memory backing, bytes memory data, uint256 expected) private pure {
        bytes32 beforeInput = keccak256(backing);
        uint256 beforeFree;
        // Dirty the temporary region permitted to memory-safe assembly. A
        // caller may leave arbitrary values here after an earlier operation.
        assembly ("memory-safe") {
            beforeFree := mload(0x40)
            for { let i := 0 } lt(i, 1024) { i := add(i, 32) } {
                mstore(add(beforeFree, i), xor(not(0), i))
            }
        }
        uint256 actual = BLAKE3Lib.hash(data);
        uint256 afterFree;
        uint256 zero;
        assembly ("memory-safe") {
            afterFree := mload(0x40)
            zero := mload(0x60)
        }
        assertEq(actual, expected, "bytes digest");
        assertEq(beforeFree, afterFree, "free-memory pointer changed");
        assertEq(zero, 0, "zero slot changed");
        assertEq(keccak256(backing), beforeInput, "allocated memory changed");

        // Allocate over the temporary region, then rehash with that allocation
        // live, and make sure both allocations retain all their logical bytes.
        bytes memory other = new bytes(4193);
        _fill(other, bytes32(expected));
        bytes32 beforeOther = keccak256(other);
        assertEq(BLAKE3Lib.hash(data), expected, "after allocation");
        assertEq(keccak256(other), beforeOther, "other allocation changed");
        assertEq(keccak256(backing), beforeInput, "input changed on repeat");
    }

    function testFuzzMisalignedBytes(bytes32 seed, uint16 size, uint8 shift) public {
        uint256 n = bound(size, 0, 17409);
        uint256 offset = bound(shift, 0, 31);
        (bytes memory backing, bytes memory data) = _misaligned(n, offset, seed);
        _checkMemory(backing, data, _oracle(data));
    }

    function testAllAlignmentsAndTransitions() public {
        uint256[16] memory sizes = [uint256(0), 1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 1023, 1024, 1025, 3072, 3073];
        for (uint256 j; j < sizes.length; ++j) {
            (bytes memory baseBacking, bytes memory original) = _misaligned(sizes[j], 0, bytes32(j));
            uint256 expected = _oracle(original);
            baseBacking; // keep the allocation live while constructing aliases
            for (uint256 offset; offset < 32; ++offset) {
                // Construct the same message at every possible byte alignment.
                bytes memory backing = new bytes(sizes[j] + 256);
                _fill(backing, bytes32(type(uint256).max - offset));
                bytes memory aliasInput;
                assembly ("memory-safe") {
                    aliasInput := add(add(backing, 96), offset)
                    mstore(aliasInput, mload(original))
                    mcopy(add(aliasInput, 32), add(original, 32), mload(original))
                }
                _checkMemory(backing, aliasInput, expected);
            }
        }
    }

    function _fixed(uint256 n, uint256 p) private pure returns (uint256) {
        if (n == 1) {
            uint256[1] memory x;
            assembly ("memory-safe") { x := p }
            return BLAKE3Lib.hash(x);
        }
        if (n == 2) {
            uint256[2] memory x;
            assembly ("memory-safe") { x := p }
            return BLAKE3Lib.hash(x);
        }
        if (n == 3) {
            uint256[3] memory x;
            assembly ("memory-safe") { x := p }
            return BLAKE3Lib.hash(x);
        }
        if (n == 4) {
            uint256[4] memory x;
            assembly ("memory-safe") { x := p }
            return BLAKE3Lib.hash(x);
        }
        if (n == 5) {
            uint256[5] memory x;
            assembly ("memory-safe") { x := p }
            return BLAKE3Lib.hash(x);
        }
        if (n == 6) {
            uint256[6] memory x;
            assembly ("memory-safe") { x := p }
            return BLAKE3Lib.hash(x);
        }
        if (n == 7) {
            uint256[7] memory x;
            assembly ("memory-safe") { x := p }
            return BLAKE3Lib.hash(x);
        }
        uint256[8] memory x8;
        assembly ("memory-safe") { x8 := p }
        return BLAKE3Lib.hash(x8);
    }

    function testFuzzInterleavedAllOverloads(bytes32 seed, uint8 shift) public {
        uint256 offset = bound(shift, 0, 31);
        for (uint256 n; n <= 8; ++n) {
            (bytes memory backing, bytes memory data) = _misaligned(n * 32, offset, seed);
            uint256 expected = _oracle(data);
            bytes32 beforeInput = keccak256(backing);
            uint256 p;
            uint256[] memory words;
            assembly ("memory-safe") {
                p := add(data, 32)
                words := data
                mstore(words, n)
            }
            assertEq(BLAKE3Lib.hash(words), expected, "dynamic words");
            if (n != 0) assertEq(_fixed(n, p), expected, "fixed words");
            assembly ("memory-safe") { mstore(data, mul(n, 32)) }
            _checkMemory(backing, data, expected);
            assertEq(keccak256(backing), beforeInput, "word input changed");
        }
    }

    function _deepTreeFixture(uint256 i) private view {
        string memory json = vm.readFile("test/vectors/independent-memory.json");
        string memory key = string.concat(".vectors[", vm.toString(i), "]");
        uint256 n = vm.parseJsonUint(json, string.concat(key, ".length"));
        bytes32 seed = vm.parseJsonBytes32(json, string.concat(key, ".seed"));
        uint256 expected = uint256(vm.parseJsonBytes32(json, string.concat(key, ".digest")));
        (bytes memory backing, bytes memory data) = _misaligned(n, i % 31 + 1, seed);
        _checkMemory(backing, data, expected);
    }

    function testDeepTreeFixture00() public view {
        _deepTreeFixture(0);
    }

    function testDeepTreeFixture01() public view {
        _deepTreeFixture(1);
    }

    function testDeepTreeFixture02() public view {
        _deepTreeFixture(2);
    }

    function testDeepTreeFixture03() public view {
        _deepTreeFixture(3);
    }

    function testDeepTreeFixture04() public view {
        _deepTreeFixture(4);
    }

    function testDeepTreeFixture05() public view {
        _deepTreeFixture(5);
    }

    function testDeepTreeFixture06() public view {
        _deepTreeFixture(6);
    }

    function testDeepTreeFixture07() public view {
        _deepTreeFixture(7);
    }

    function testDeepTreeFixture08() public view {
        _deepTreeFixture(8);
    }

    function testDeepTreeFixture09() public view {
        _deepTreeFixture(9);
    }

    function testDeepTreeFixture10() public view {
        _deepTreeFixture(10);
    }

    function testDeepTreeFixture11() public view {
        _deepTreeFixture(11);
    }

    function testDeepTreeFixture12() public view {
        _deepTreeFixture(12);
    }

    function testDeepTreeFixture13() public view {
        _deepTreeFixture(13);
    }

    function testDeepTreeFixture14() public view {
        _deepTreeFixture(14);
    }

    function testDeepTreeFixture15() public view {
        _deepTreeFixture(15);
    }

    function testDeepTreeFixture16() public view {
        _deepTreeFixture(16);
    }

    function testDeepTreeFixture17() public view {
        _deepTreeFixture(17);
    }

    function testDeepTreeFixture18() public view {
        _deepTreeFixture(18);
    }

    function testDeepTreeFixture19() public view {
        _deepTreeFixture(19);
    }

    function testDeepTreeFixture20() public view {
        _deepTreeFixture(20);
    }

    function testDeepTreeFixture21() public view {
        _deepTreeFixture(21);
    }

    function testDeepTreeFixture22() public view {
        _deepTreeFixture(22);
    }

    function testDeepTreeFixture23() public view {
        _deepTreeFixture(23);
    }

    function testDeepTreeFixture24() public view {
        _deepTreeFixture(24);
    }

    function testDeepTreeFixture25() public view {
        _deepTreeFixture(25);
    }

    function testDeepTreeFixture26() public view {
        _deepTreeFixture(26);
    }

    function testDeepTreeFixture27() public view {
        _deepTreeFixture(27);
    }

    function testDeepTreeFixture28() public view {
        _deepTreeFixture(28);
    }

    function testDeepTreeFixture29() public view {
        _deepTreeFixture(29);
    }

    function testDeepTreeFixture30() public view {
        _deepTreeFixture(30);
    }

    function testDeepTreeFixture31() public view {
        _deepTreeFixture(31);
    }

    function testDeepTreeFixture32() public view {
        _deepTreeFixture(32);
    }

    function testDeepTreeFixture33() public view {
        _deepTreeFixture(33);
    }

    function testDeepTreeFixture34() public view {
        _deepTreeFixture(34);
    }
}
