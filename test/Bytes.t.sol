// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BLAKE3Lib} from "../src/BLAKE3Lib.sol";
import {HashHarness} from "./helpers/HashHarness.sol";

contract BytesTest is Test {
    HashHarness internal h;

    function setUp() public {
        h = new HashHarness();
    }

    function testEmptyBytes() public pure {
        assertEq(BLAKE3Lib.hash(bytes("")), uint256(0xaf1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262));
    }

    function testABC() public pure {
        assertEq(
            BLAKE3Lib.hash(bytes("abc")), uint256(0x6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85)
        );
    }

    function testByteReferenceVectors() public view {
        string memory json = vm.readFile("test/vectors/bytes.json");
        uint256 count = vm.parseJsonUint(json, ".count");
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(".vectors[", vm.toString(i), "]");
            bytes memory data = vm.parseJsonBytes(json, string.concat(key, ".input"));
            uint256 expected = uint256(vm.parseJsonBytes32(json, string.concat(key, ".digest")));
            assertEq(BLAKE3Lib.hash(data), expected, vm.toString(i));
            assertEq(h.hashBytes(data), expected, vm.toString(i));
        }
    }

    function testFuzzDirtyPaddingAndMemory(bytes memory data) public pure {
        _checkPadding(data);
    }

    function testEveryShortTailPadding() public pure {
        for (uint256 n; n < 130; ++n) {
            bytes memory data = new bytes(n);
            for (uint256 i; i < n; ++i) {
                data[i] = bytes1(uint8(i));
            }
            _checkPadding(data);
        }
    }

    function _checkPadding(bytes memory data) private pure {
        uint256 expected = BLAKE3Lib.hash(data);
        // The allocated suffix guarantees a safe, deliberately dirty word
        // immediately after the logical input, even at an unaligned address.
        bytes memory dirty = bytes.concat(data, abi.encodePacked(type(uint256).max));
        uint256 length = data.length;
        assembly ("memory-safe") { mstore(dirty, length) }
        bytes32 beforeHash = keccak256(dirty);
        assertEq(BLAKE3Lib.hash(dirty), expected);
        assertEq(keccak256(dirty), beforeHash);
        uint256 suffix;
        uint256 zeroSlot;
        assembly ("memory-safe") {
            suffix := mload(add(add(dirty, 32), length))
            zeroSlot := mload(0x60)
        }
        assertEq(suffix, type(uint256).max, "padding was modified");
        assertEq(zeroSlot, 0);
        bytes memory copy = bytes.concat(data);
        assertEq(BLAKE3Lib.hash(copy), expected);
    }
}
