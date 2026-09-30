// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ITwabController } from "../src/interfaces/ITwabController.sol";
import { ObservationTwabController } from "../src/TwabController/ObservationTwabController.sol";
import { TwabControllerBehavior } from "./TwabControllerBehavior.t.sol";

contract ObservationTwabControllerTest is TwabControllerBehavior {
    function _deployTwab() internal override returns (ITwabController) {
        return new ObservationTwabController();
    }

    function test_ring_many_checkpoints_binary_search() public {
        // 写入较多不同时间点的 checkpoint，验证二分查找取值正确。
        vm.warp(0);
        twab.mint(ALICE, 100);

        for (uint32 t = 1; t <= 200; t++) {
            vm.warp(t);
            twab.mint(BOB, t); // 每次给 BOB 增加不同金额，产生新 observation
        }

        vm.warp(250);
        // 在每个整点，BOB 的余额应为该时刻前累计已铸入的部分
        assertEq(twab.getBalanceAt(BOB, 100), 5050); // sum(1..100)
        assertEq(twab.getBalanceAt(BOB, 200), 20100); // sum(1..200)
        // 远早于首条记录的时间应返回 0
        assertEq(twab.getBalanceAt(ALICE, 0), 100);
    }
}
