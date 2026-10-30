// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BLAKE3Lib} from "../../src/BLAKE3Lib.sol";

/// @dev External entry points for gas reporting and integration tests.
contract HashHarness {
    function hash1(uint256[1] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hash2(uint256[2] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hash3(uint256[3] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hash4(uint256[4] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hash5(uint256[5] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hash6(uint256[6] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hash7(uint256[7] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hash8(uint256[8] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hashDynamic(uint256[] memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }

    function hashBytes(bytes memory x) external pure returns (uint256) {
        return BLAKE3Lib.hash(x);
    }
}
