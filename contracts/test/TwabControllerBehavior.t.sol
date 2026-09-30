// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ITwabController } from "../src/interfaces/ITwabController.sol";

/// @notice TWAB 控制器共享行为测试：两种实现各跑一遍同一套断言。
abstract contract TwabControllerBehavior is Test {
    ITwabController internal twab;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant ATTACKER = address(0xBAD);

    function _deployTwab() internal virtual returns (ITwabController);

    function setUp() public virtual {
        twab = _deployTwab();
    }

    function test_mint_burn_balance() public {
        twab.mint(ALICE, 100);
        assertEq(twab.balanceOf(ALICE), 100);
        assertEq(twab.totalSupply(), 100);

        twab.burn(ALICE, 40);
        assertEq(twab.balanceOf(ALICE), 60);
        assertEq(twab.totalSupply(), 60);
    }

    function test_transfer() public {
        twab.mint(ALICE, 100);
        twab.transfer(ALICE, BOB, 30);
        assertEq(twab.balanceOf(ALICE), 70);
        assertEq(twab.balanceOf(BOB), 30);
        assertEq(twab.totalSupply(), 100);
    }

    function test_twab_time_weighted() public {
        vm.warp(100);
        twab.mint(ALICE, 100); // 从 t=100 起余额 100

        vm.warp(200);
        twab.burn(ALICE, 50); // 从 t=200 起余额 50

        vm.warp(300);
        // [100,300) 内 TWAB = (100*100 + 50*100)/200 = 75
        assertEq(twab.getTwabBetween(ALICE, 100, 300), 75);
    }

    function test_getBalanceAt() public {
        vm.warp(100);
        twab.mint(ALICE, 100);
        vm.warp(200);
        twab.burn(ALICE, 50);

        assertEq(twab.getBalanceAt(ALICE, 150), 100);
        assertEq(twab.getBalanceAt(ALICE, 250), 50);
        assertEq(twab.getBalanceAt(ALICE, 99), 0);
    }

    function test_totalSupply_at_and_average() public {
        vm.warp(100);
        twab.mint(ALICE, 100); // totalSupply 100 from t=100
        vm.warp(200);
        twab.mint(BOB, 100); // totalSupply 200 from t=200
        vm.warp(300);

        assertEq(twab.getTotalSupplyAt(150), 100);
        assertEq(twab.getTotalSupplyAt(250), 200);
        // 平均总供应 [100,300) = (100*100 + 200*100)/200 = 150
        assertEq(twab.getAverageTotalSupplyBetween(100, 300), 150);
    }

    function test_only_vault_can_mutate() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        twab.mint(ALICE, 1);
    }

    function test_mint_zero_address_reverts() public {
        vm.expectRevert();
        twab.mint(address(0), 1);
    }

    function test_invalid_timestamp_reverts() public {
        vm.expectRevert();
        twab.getTwabBetween(ALICE, 200, 100);
    }
}
