// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BLAKE3Lib} from "../src/BLAKE3Lib.sol";

contract LibraryGasTest is Test {
    function testLibraryGasFixed1() public {
        uint256[1] memory x = [uint256(1)];
        vm.startSnapshotGas("library", "fixed1");
        uint256 result = BLAKE3Lib.hash(x);
        uint256 used = vm.stopSnapshotGas();
        assertEq(result, uint256(0x55bbfb5b05f80543bd662a7b7a74980a2992612798087fa24e1fc86b8e8508e4));
        assertLt(used, 10000);
    }

    function testLibraryGasFixed2() public {
        uint256[2] memory x = [uint256(1), 2];
        vm.startSnapshotGas("library", "fixed2");
        uint256 result = BLAKE3Lib.hash(x);
        uint256 used = vm.stopSnapshotGas();
        assertEq(result, uint256(0xa1852311a98ff4c66e0642c644a61d02a5ea1a4ab530a19cb83a82e42ff8011f));
        assertLt(used, 10000);
    }

    function testLibraryGasFixed3() public {
        uint256[3] memory x = [uint256(1), 2, 3];
        vm.startSnapshotGas("library", "fixed3");
        uint256 result = BLAKE3Lib.hash(x);
        uint256 used = vm.stopSnapshotGas();
        assertEq(result, uint256(0x5d2c070292048b013937f401e0116af8e6e983057d2b63f922cc910adae9710f));
        assertLt(used, 13000);
    }

    function testLibraryGasFixed4() public {
        uint256[4] memory x = [uint256(1), 2, 3, 4];
        vm.startSnapshotGas("library", "fixed4");
        uint256 result = BLAKE3Lib.hash(x);
        uint256 used = vm.stopSnapshotGas();
        assertEq(result, uint256(0x4a0f1814912f4ce727461aa4fb8786c087b571961dde489e6d4aa794ca9ebff7));
        assertLt(used, 13000);
    }

    function testLibraryGasFixed5() public {
        uint256[5] memory x = [uint256(1), 2, 3, 4, 5];
        vm.startSnapshotGas("library", "fixed5");
        uint256 result = BLAKE3Lib.hash(x);
        vm.stopSnapshotGas();
        assertEq(result, uint256(0x89a4006274bf2e9ac4d29746e1f7795050de0e19dcb8e1a746f858a51aa46f3b));
    }

    function testLibraryGasFixed6() public {
        uint256[6] memory x = [uint256(1), 2, 3, 4, 5, 6];
        vm.startSnapshotGas("library", "fixed6");
        uint256 result = BLAKE3Lib.hash(x);
        vm.stopSnapshotGas();
        assertEq(result, uint256(0xd33c27aa6c308d1a5ab23fdefe00422b4f72f2493fe0dc9626e57bdc8efc075f));
    }

    function testLibraryGasFixed7() public {
        uint256[7] memory x = [uint256(1), 2, 3, 4, 5, 6, 7];
        vm.startSnapshotGas("library", "fixed7");
        uint256 result = BLAKE3Lib.hash(x);
        vm.stopSnapshotGas();
        assertEq(result, uint256(0xae756a0c892f6d89c2034c153dd6c5f9199a6de1cce7eee6b2253a18cbc61151));
    }

    function testLibraryGasFixed8() public {
        uint256[8] memory x = [uint256(1), 2, 3, 4, 5, 6, 7, 8];
        vm.startSnapshotGas("library", "fixed8");
        uint256 result = BLAKE3Lib.hash(x);
        vm.stopSnapshotGas();
        assertEq(result, uint256(0x8252dca7823899ff153ef9b6c909da903f741ee1952858cc690b2efd04fe223d));
    }

    function testLibraryGasDynamic0() public {
        _dynamic(0, 0xaf1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262);
    }

    function testLibraryGasDynamic1() public {
        _dynamic(1, 0x55bbfb5b05f80543bd662a7b7a74980a2992612798087fa24e1fc86b8e8508e4);
    }

    function testLibraryGasDynamic2() public {
        _dynamic(2, 0xa1852311a98ff4c66e0642c644a61d02a5ea1a4ab530a19cb83a82e42ff8011f);
    }

    function testLibraryGasDynamic3() public {
        _dynamic(3, 0x5d2c070292048b013937f401e0116af8e6e983057d2b63f922cc910adae9710f);
    }

    function testLibraryGasDynamic4() public {
        _dynamic(4, 0x4a0f1814912f4ce727461aa4fb8786c087b571961dde489e6d4aa794ca9ebff7);
    }

    function testLibraryGasDynamic5() public {
        _dynamic(5, 0x89a4006274bf2e9ac4d29746e1f7795050de0e19dcb8e1a746f858a51aa46f3b);
    }

    function testLibraryGasDynamic6() public {
        _dynamic(6, 0xd33c27aa6c308d1a5ab23fdefe00422b4f72f2493fe0dc9626e57bdc8efc075f);
    }

    function testLibraryGasDynamic7() public {
        _dynamic(7, 0xae756a0c892f6d89c2034c153dd6c5f9199a6de1cce7eee6b2253a18cbc61151);
    }

    function testLibraryGasDynamic8() public {
        _dynamic(8, 0x8252dca7823899ff153ef9b6c909da903f741ee1952858cc690b2efd04fe223d);
    }

    function _dynamic(uint256 n, uint256 expected) private {
        uint256[] memory x = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            x[i] = i + 1;
        }
        string memory name = string.concat("dynamic", vm.toString(n));
        vm.startSnapshotGas("library", name);
        uint256 result = BLAKE3Lib.hash(x);
        uint256 used = vm.stopSnapshotGas();
        assertEq(result, expected);
        if (n <= 2) assertLt(used, 10000);
        else if (n <= 4) assertLt(used, 13000);
    }
}
