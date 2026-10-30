// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BLAKE3Lib} from "../src/BLAKE3Lib.sol";
import {HashHarness} from "./helpers/HashHarness.sol";

contract BytesGasTest is Test {
    HashHarness internal h;

    function setUp() public {
        h = new HashHarness();
    }

    function testPackingArray3() public {
        vm.startSnapshotGas("construction", "array3");
        uint256 result = BLAKE3Lib.hash([uint256(1), 2, 3]);
        vm.stopSnapshotGas();
        assertEq(result, uint256(0x5d2c070292048b013937f401e0116af8e6e983057d2b63f922cc910adae9710f));
    }

    function testPackingFullWords3() public {
        vm.startSnapshotGas("construction", "fullWords3");
        uint256 result = BLAKE3Lib.hash(abi.encodePacked(uint256(1), uint256(2), uint256(3)));
        vm.stopSnapshotGas();
        assertEq(result, uint256(0x5d2c070292048b013937f401e0116af8e6e983057d2b63f922cc910adae9710f));
    }

    function testPackingCompact3() public {
        vm.startSnapshotGas("construction", "compact3");
        uint256 result = BLAKE3Lib.hash(abi.encodePacked(uint8(1), uint8(2), uint8(3)));
        uint256 used = vm.stopSnapshotGas();
        assertEq(result, uint256(0xb177ec1bf26dfb3b7010d473e6d44713b29b765b99c6e60ecbfae742de496543));
        assertLt(used, 15000);
    }

    function testBytesGas0() public {
        _length(0, 0xaf1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262);
    }

    function testBytesGas1() public {
        _length(1, 0x48fc721fbbc172e0925fa27af1671de225ba927134802998b10a1568a188652b);
    }

    function testBytesGas2() public {
        _length(2, 0xb7d770040f780e9deff6bc038abea66e108b88d098d16d24cd7486eb671060b2);
    }

    function testBytesGas3() public {
        _length(3, 0xb177ec1bf26dfb3b7010d473e6d44713b29b765b99c6e60ecbfae742de496543);
    }

    function testBytesGas4() public {
        _length(4, 0x63781d171425a36312fa058d8712d5d05135a991ec20351ce9d65cdb19a05432);
    }

    function testBytesGas8() public {
        _length(8, 0xe576e94c11c598aad6ac7815010f1c1525c21dec54cf177a8be6a6142c7a39a4);
    }

    function testBytesGas16() public {
        _length(16, 0x586dd8f75518c704219c80741892676cccc647226eeca3228c775a17d9df4bff);
    }

    function testBytesGas24() public {
        _length(24, 0x2cdcc7b7dc97508a34e86672ff94736ea12fe561633df1d1489869d03075e9c2);
    }

    function testBytesGas31() public {
        _length(31, 0x3828a695285f58f12c1a3575caaf331bf6a16c05fb1e622686740855a35bf8d7);
    }

    function testBytesGas32() public {
        _length(32, 0xf0d184663caeb47e78a42f7235250fa0d61962a149624d05729b1e9537c6454f);
    }

    function testBytesGas33() public {
        _length(33, 0xfd94274b8659b146fa6700feb743036286e9c1b395f6d90d453befd82cd912c0);
    }

    function testBytesGas63() public {
        _length(63, 0xe1618a77834186c74138c5c00a01989f2005dad18b78f1216816722dce965a0b);
    }

    function testBytesGas64() public {
        _length(64, 0xdfea3ddc725b9faf208d92c178a6d17a7fcbe80f73358c5bd1a86b82d47d4da3);
    }

    function testBytesGas65() public {
        _length(65, 0x7cb865fd101d363effadbed5026db31713bb577f84d210076c5081407ee1d4b8);
    }

    function testBytesGas96() public {
        _length(96, 0xa13cc0e89b4be8f78c5a160b4e20e2cf6171b40d3ecd084d83b0bda63ff9dfdd);
    }

    function testBytesGas128() public {
        _length(128, 0xd424e1784521d175acadaa3dfc5bdad2990cb5896790bc0b925aa0fda5d51918);
    }

    function testBytesGas160() public {
        _length(160, 0x9b3316cd761004bb90debc6bf70d5ab8686b44684f9063d8f677546e3ffa547c);
    }

    function testBytesGas192() public {
        _length(192, 0xc1a1dca9256854e20f965fcda45506a3fdde36628b975ecbecb793be40b43982);
    }

    function testBytesGas224() public {
        _length(224, 0xe1cfd3214eddfac17af562471cfcebaf8b144be6c5900466b8a25df4e30c4ffb);
    }

    function testBytesGas256() public {
        _length(256, 0x169063ca47d4c858d1eda9569a5af135a222395dd3d5ac6ee8ce242f4649021d);
    }

    function testBytesGas1023() public {
        _length(1023, 0xc79763d95341f1c0d8af143929e61e6de9cd2652e2720575d7554b9afdba9405);
    }

    function testBytesGas1024() public {
        _length(1024, 0xf6a27121ebf9d0dacf303114211550542c6c6b6bebb2977407c5399e42810d3f);
    }

    function testBytesGas1025() public {
        _length(1025, 0xd2ddcabe7bd5f51e5cadfb7c4009ea2183f83aef23b839606de108689796e0b1);
    }

    function testBytesGasWords1() public {
        _words(1, 0x55bbfb5b05f80543bd662a7b7a74980a2992612798087fa24e1fc86b8e8508e4);
    }

    function testBytesGasWords2() public {
        _words(2, 0xa1852311a98ff4c66e0642c644a61d02a5ea1a4ab530a19cb83a82e42ff8011f);
    }

    function testBytesGasWords3() public {
        _words(3, 0x5d2c070292048b013937f401e0116af8e6e983057d2b63f922cc910adae9710f);
    }

    function testBytesGasWords4() public {
        _words(4, 0x4a0f1814912f4ce727461aa4fb8786c087b571961dde489e6d4aa794ca9ebff7);
    }

    function testBytesGasWords5() public {
        _words(5, 0x89a4006274bf2e9ac4d29746e1f7795050de0e19dcb8e1a746f858a51aa46f3b);
    }

    function testBytesGasWords6() public {
        _words(6, 0xd33c27aa6c308d1a5ab23fdefe00422b4f72f2493fe0dc9626e57bdc8efc075f);
    }

    function testBytesGasWords7() public {
        _words(7, 0xae756a0c892f6d89c2034c153dd6c5f9199a6de1cce7eee6b2253a18cbc61151);
    }

    function testBytesGasWords8() public {
        _words(8, 0x8252dca7823899ff153ef9b6c909da903f741ee1952858cc690b2efd04fe223d);
    }

    function _length(uint256 n, uint256 expected) private {
        bytes memory data = new bytes(n);
        for (uint256 i; i < n; ++i) {
            data[i] = bytes1(uint8(i + 1));
        }
        _measure(data, string.concat("length", vm.toString(n)), expected);
    }

    function _words(uint256 n, uint256 expected) private {
        uint256[] memory words = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            words[i] = i + 1;
        }
        bytes memory data = abi.encodePacked(words);
        _measure(data, string.concat("words", vm.toString(n)), expected);
    }

    function _measure(bytes memory data, string memory name, uint256 expected) private {
        vm.startSnapshotGas("library_bytes", name);
        uint256 result = BLAKE3Lib.hash(data);
        uint256 used = vm.stopSnapshotGas();
        assertEq(result, expected);
        if (data.length <= 96) assertLt(used, 15000);
        uint256 externalResult = h.hashBytes(data);
        uint256 externalUsed = vm.snapshotGasLastFrame("external_bytes", name);
        assertEq(externalResult, expected);
        if (data.length <= 96) assertLt(externalUsed, 15000);
    }
}
