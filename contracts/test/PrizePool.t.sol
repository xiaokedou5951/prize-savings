// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { PrizePool } from "../src/PrizePool/PrizePool.sol";

contract PrizePoolTest is Test {
    MockERC20 internal prizeToken;
    SimpleTwabController internal twab;
    PrizePool internal pool;

    address internal constant KEEPER = address(0xEAD);
    address internal constant OWNER = address(0x0A);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant ATTACKER = address(0xBAD);

    uint32 internal constant PERIOD = 1 days;
    uint32 internal constant OFFSET = 1_000_000;

    function setUp() public {
        prizeToken = new MockERC20("Prize Token", "PRIZE", 18);
        twab = new SimpleTwabController();
        pool = new PrizePool(prizeToken, twab, PERIOD, OFFSET, KEEPER);

        prizeToken.mint(address(pool), 1_000_000e18);
    }

    function _fundAndHoldTwab(address user, uint256 amount, uint32 start, uint32 end) internal {
        vm.warp(start);
        twab.mint(user, amount);
        vm.warp(end);
    }

    function test_award_draw_only_keeper() public {
        vm.warp(OFFSET + PERIOD);
        vm.prank(ATTACKER);
        vm.expectRevert();
        pool.awardDraw(123);
    }

    function test_award_draw_not_ready_reverts() public {
        vm.warp(OFFSET); // 尚未到 offset + period
        vm.prank(KEEPER);
        vm.expectRevert();
        pool.awardDraw(123);
    }

    function test_prize_structure() public {
        assertEq(pool.prizeCount(0), 1);
        assertEq(pool.prizeCount(1), 4);
        assertEq(pool.prizeCount(2), 100);
        assertEq(pool.tierFraction(0), 6e17);
        assertEq(pool.tierFraction(1), 25e16);
        assertEq(pool.tierFraction(2), 15e16);
    }

    function test_prize_size_distribution() public {
        vm.warp(OFFSET);
        _fundAndHoldTwab(ALICE, 100, OFFSET, OFFSET + PERIOD);

        vm.warp(OFFSET + PERIOD);
        vm.prank(KEEPER);
        uint32 drawId = pool.awardDraw(777);
        assertEq(drawId, 1);

        uint256 drawAmount = prizeToken.balanceOf(address(pool));
        // Grand Prize 单项 = drawAmount * 0.6 / 1
        uint256 grand = pool.getClaimableAmount(ALICE, 0, 1);
        // ALICE 是唯一持有者，占全部 TWAB，应命中大奖全量
        assertEq(grand, drawAmount * 6e17 / 1e18, "grand prize = 60% of pool");
    }

    function test_single_user_wins_all_tiers() public {
        vm.warp(OFFSET);
        twab.mint(ALICE, 100);
        vm.warp(OFFSET + PERIOD);

        vm.prank(KEEPER);
        pool.awardDraw(1);

        // Alice 是唯一 TWAB 持有者，应能领满三档
        assertGt(pool.getClaimableAmount(ALICE, 0, 1), 0);
        assertGt(pool.getClaimableAmount(ALICE, 1, 1), 0);
        assertGt(pool.getClaimableAmount(ALICE, 2, 1), 0);
    }

    function test_claim_then_cannot_reclaim() public {
        vm.warp(OFFSET);
        twab.mint(ALICE, 100);
        vm.warp(OFFSET + PERIOD);
        vm.prank(KEEPER);
        pool.awardDraw(1);

        uint256 before = prizeToken.balanceOf(ALICE);
        uint256 amount = pool.claimPrize(ALICE, 0, 1);
        assertGt(amount, 0);
        assertEq(prizeToken.balanceOf(ALICE), before + amount);

        // 重复领取应 revert
        vm.expectRevert();
        pool.claimPrize(ALICE, 0, 1);
    }

    function test_non_winner_claims_nothing() public {
        vm.warp(OFFSET);
        twab.mint(ALICE, 100);
        vm.warp(OFFSET + PERIOD);
        vm.prank(KEEPER);
        pool.awardDraw(1);

        // BOB 无 TWAB，无奖金
        assertEq(pool.isWinner(BOB, 0, 1), false);
        vm.expectRevert();
        pool.claimPrize(BOB, 0, 1);
    }

    function test_zero_supply_award_zero() public {
        // 无人存款时开奖，任何查询均为 0
        vm.warp(OFFSET + PERIOD);
        vm.prank(KEEPER);
        pool.awardDraw(1);

        assertEq(pool.getClaimableAmount(ALICE, 0, 1), 0);
    }

    function test_set_draw_manager_only_owner() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        pool.setDrawManager(ATTACKER);
    }
}
