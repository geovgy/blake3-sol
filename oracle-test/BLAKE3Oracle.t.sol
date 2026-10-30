// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BLAKE3Lib} from "../src/BLAKE3Lib.sol";
import {HashHarness} from "../test/helpers/HashHarness.sol";

/// @dev Opt-in live differential tests: FOUNDRY_PROFILE=oracle forge test.
contract BLAKE3OracleTest is Test {
    HashHarness internal h;

    function setUp() public {
        h = new HashHarness();
    }

    function _reference(uint256[] memory x) private returns (uint256) {
        return _referenceBytes(abi.encodePacked(x));
    }

    function _referenceBytes(bytes memory x) private returns (uint256) {
        string[] memory command = new string[](2);
        command[0] = "reference/servil/target/release/blake3-reference";
        command[1] = vm.toString(x);
        return abi.decode(vm.ffi(command), (uint256));
    }

    function testFuzzReleaseDynamic(bytes32 seed, uint16 size) public {
        uint256 n = bound(size, 0, 1025);
        uint256[] memory x = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            x[i] = uint256(keccak256(abi.encode(seed, i)));
        }
        assertEq(BLAKE3Lib.hash(x), _reference(x));
    }

    function testFuzzReleaseBytes(bytes32 seed, uint16 size) public {
        uint256 n = bound(size, 0, 8193);
        bytes memory data = new bytes(n);
        for (uint256 i; i < n; i += 32) {
            bytes32 word = keccak256(abi.encode(seed, i));
            assembly ("memory-safe") { mstore(add(add(data, 32), i), word) }
        }
        assertEq(BLAKE3Lib.hash(data), _referenceBytes(data));
    }

    function testFuzzReleaseShortBytes(bytes32 seed, uint8 size) public {
        uint256 n = bound(size, 0, 129);
        bytes memory data = new bytes(n);
        for (uint256 i; i < n; i += 32) {
            bytes32 word = keccak256(abi.encode(seed, i));
            assembly ("memory-safe") { mstore(add(add(data, 32), i), word) }
        }
        _assertDirtyBytes(data);
    }

    /// @dev Exercise every short tail with values that stress lane carries.
    function testReleaseShortTailsAndCarries() public {
        for (uint256 n; n <= 129; ++n) {
            bytes memory data = new bytes(n);
            _assertDirtyBytes(data);
            for (uint256 i; i < n; ++i) {
                data[i] = 0xff;
            }
            _assertDirtyBytes(data);
            for (uint256 i; i < n; ++i) {
                data[i] = i % 2 == 0 ? bytes1(0x55) : bytes1(0xaa);
            }
            _assertDirtyBytes(data);
        }
    }

    function _assertDirtyBytes(bytes memory data) private {
        uint256 expected = _referenceBytes(data);
        bytes memory dirty = bytes.concat(data, abi.encodePacked(type(uint256).max));
        bytes32 beforeHash = keccak256(dirty);
        uint256 n = data.length;
        assembly ("memory-safe") { mstore(dirty, n) }
        assertEq(BLAKE3Lib.hash(dirty), expected);
        assertEq(h.hashBytes(dirty), expected);
        uint256 zeroSlot;
        assembly ("memory-safe") {
            zeroSlot := mload(0x60)
            mstore(dirty, add(n, 32))
        }
        assertEq(zeroSlot, 0);
        assertEq(keccak256(dirty), beforeHash, "input or padding changed");
    }

    function testFuzzReleaseFixed(uint256[8] memory x) public {
        for (uint256 n = 1; n <= 8; ++n) {
            uint256[] memory dynamicInput = new uint256[](n);
            for (uint256 i; i < n; ++i) {
                dynamicInput[i] = x[i];
            }
            uint256 expected = _reference(dynamicInput);
            uint256 p;
            assembly ("memory-safe") { p := x }
            if (n == 1) {
                uint256[1] memory a;
                assembly ("memory-safe") { a := p }
                assertEq(h.hash1(a), expected);
            }
            if (n == 2) {
                uint256[2] memory a;
                assembly ("memory-safe") { a := p }
                assertEq(h.hash2(a), expected);
            }
            if (n == 3) {
                uint256[3] memory a;
                assembly ("memory-safe") { a := p }
                assertEq(h.hash3(a), expected);
            }
            if (n == 4) {
                uint256[4] memory a;
                assembly ("memory-safe") { a := p }
                assertEq(h.hash4(a), expected);
            }
            if (n == 5) {
                uint256[5] memory a;
                assembly ("memory-safe") { a := p }
                assertEq(h.hash5(a), expected);
            }
            if (n == 6) {
                uint256[6] memory a;
                assembly ("memory-safe") { a := p }
                assertEq(h.hash6(a), expected);
            }
            if (n == 7) {
                uint256[7] memory a;
                assembly ("memory-safe") { a := p }
                assertEq(h.hash7(a), expected);
            }
            if (n == 8) assertEq(h.hash8(x), expected);
        }
    }
}
