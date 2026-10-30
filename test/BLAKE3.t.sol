// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BLAKE3Lib} from "../src/BLAKE3Lib.sol";
import {HashHarness} from "./helpers/HashHarness.sol";

contract BLAKE3Test is Test {
    HashHarness internal harness;

    function setUp() public {
        harness = new HashHarness();
    }

    function testEmpty() public pure {
        uint256[] memory values = new uint256[](0);
        assertEq(BLAKE3Lib.hash(values), uint256(0xaf1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262));
    }

    function testArrayLiteral() public pure {
        uint256 value = 1;
        assertEq(BLAKE3Lib.hash([value]), uint256(0x55bbfb5b05f80543bd662a7b7a74980a2992612798087fa24e1fc86b8e8508e4));
    }

    function testDirtyScratchAndSurroundings() public pure {
        uint256[] memory x = new uint256[](97);
        for (uint256 i; i < x.length; ++i) {
            x[i] = type(uint256).max - i;
        }
        bytes32 inputBefore = keccak256(abi.encode(x));
        uint256[2] memory sentinel = [uint256(0x1234), type(uint256).max];
        uint256 first = BLAKE3Lib.hash(x);
        // Scratch memory is allowed to contain arbitrary data on entry.
        assembly ("memory-safe") {
            let p := mload(0x40)
            for { let i := 0 } lt(i, 1024) { i := add(i, 32) } { mstore(add(p, i), not(0)) }
        }
        assertEq(BLAKE3Lib.hash(x), first);
        assertEq(keccak256(abi.encode(x)), inputBefore);
        assertEq(sentinel[0], 0x1234);
        assertEq(sentinel[1], type(uint256).max);
        uint256 zeroSlot;
        assembly ("memory-safe") { zeroSlot := mload(0x60) }
        assertEq(zeroSlot, 0);
    }

    function testReferenceVectors() public view {
        string memory json = vm.readFile("test/vectors/reference.json");
        uint256 count = vm.parseJsonUint(json, ".count");
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(".vectors[", vm.toString(i), "]");
            bytes memory input = vm.parseJsonBytes(json, string.concat(key, ".input"));
            uint256[] memory values = new uint256[](input.length / 32);
            for (uint256 j; j < values.length; ++j) {
                uint256 word;
                assembly ("memory-safe") { word := mload(add(add(input, 32), mul(j, 32))) }
                values[j] = word;
            }
            uint256 expected = uint256(vm.parseJsonBytes32(json, string.concat(key, ".digest")));
            assertEq(BLAKE3Lib.hash(values), expected, vm.toString(i));
            assertEq(BLAKE3Lib.hash(input), expected, vm.toString(i));
            _assertFixed(values, expected);
        }
    }

    function _assertFixed(uint256[] memory x, uint256 expected) internal view {
        // Each fixed overload sees exactly the same bytes as its dynamic peer.
        uint256 p;
        assembly ("memory-safe") { p := add(x, 32) }
        if (x.length == 1) {
            uint256[1] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash1(a), expected);
        }
        if (x.length == 2) {
            uint256[2] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash2(a), expected);
        }
        if (x.length == 3) {
            uint256[3] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash3(a), expected);
        }
        if (x.length == 4) {
            uint256[4] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash4(a), expected);
        }
        if (x.length == 5) {
            uint256[5] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash5(a), expected);
        }
        if (x.length == 6) {
            uint256[6] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash6(a), expected);
        }
        if (x.length == 7) {
            uint256[7] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash7(a), expected);
        }
        if (x.length == 8) {
            uint256[8] memory a;
            assembly ("memory-safe") { a := p }
            assertEq(harness.hash8(a), expected);
        }
    }

    function testFuzzFixedAndMemory(uint256[8] memory words, uint8 length) public view {
        uint256 n = bound(length, 1, 8);
        uint256[] memory x = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            x[i] = words[i];
        }
        bytes32 beforeHash = keccak256(abi.encode(x));
        uint256 result = BLAKE3Lib.hash(x);
        assertEq(BLAKE3Lib.hash(abi.encodePacked(x)), result);
        _assertFixed(x, result);
        assertEq(keccak256(abi.encode(x)), beforeHash, "input changed");
        // Allocation after the call must remain safe and repeat calls must agree.
        uint256[] memory copy = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            copy[i] = words[i];
        }
        assertEq(BLAKE3Lib.hash(copy), result);
    }
}
