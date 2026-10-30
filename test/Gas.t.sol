// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HashHarness} from "./helpers/HashHarness.sol";

contract GasTest is Test {
    HashHarness internal h;

    function setUp() public {
        h = new HashHarness();
    }

    function testGasFixed1() public {
        h.hash1([uint256(1)]);
        uint256 used = vm.snapshotGasLastFrame("external", "fixed1");
        assertLt(used, 15000);
    }

    function testGasFixed2() public {
        h.hash2([uint256(1), 2]);
        uint256 used = vm.snapshotGasLastFrame("external", "fixed2");
        assertLt(used, 15000);
    }

    function testGasFixed3() public {
        h.hash3([uint256(1), 2, 3]);
        uint256 used = vm.snapshotGasLastFrame("external", "fixed3");
        assertLt(used, 15000);
    }

    function testGasFixed4() public {
        h.hash4([uint256(1), 2, 3, 4]);
        vm.snapshotGasLastFrame("external", "fixed4");
    }

    function testGasFixed5() public {
        h.hash5([uint256(1), 2, 3, 4, 5]);
        vm.snapshotGasLastFrame("external", "fixed5");
    }

    function testGasFixed6() public {
        h.hash6([uint256(1), 2, 3, 4, 5, 6]);
        vm.snapshotGasLastFrame("external", "fixed6");
    }

    function testGasFixed7() public {
        h.hash7([uint256(1), 2, 3, 4, 5, 6, 7]);
        vm.snapshotGasLastFrame("external", "fixed7");
    }

    function testGasFixed8() public {
        h.hash8([uint256(1), 2, 3, 4, 5, 6, 7, 8]);
        vm.snapshotGasLastFrame("external", "fixed8");
    }

    function testGasDynamic0() public {
        _dynamic(0);
    }

    function testGasDynamic1() public {
        _dynamic(1);
    }

    function testGasDynamic2() public {
        _dynamic(2);
    }

    function testGasDynamic3() public {
        _dynamic(3);
    }

    function testGasDynamic4() public {
        _dynamic(4);
    }

    function testGasDynamic5() public {
        _dynamic(5);
    }

    function testGasDynamic6() public {
        _dynamic(6);
    }

    function testGasDynamic7() public {
        _dynamic(7);
    }

    function testGasDynamic8() public {
        _dynamic(8);
    }

    function testGasDynamic32() public {
        _dynamic(32);
    }

    function testGasDynamic33() public {
        _dynamic(33);
    }

    function testGasDynamic64() public {
        _dynamic(64);
    }

    function _dynamic(uint256 n) private {
        string memory name = string.concat("dynamic", vm.toString(n));
        uint256[] memory x = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            x[i] = i + 1;
        }
        h.hashDynamic(x);
        vm.snapshotGasLastFrame("external", name);
    }
}
