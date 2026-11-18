// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { PrizePool } from "../src/PrizePool/PrizePool.sol";
import { RngRelay } from "../src/RngRelay/RngRelay.sol";
import { IRngRelay } from "../src/interfaces/IRngRelay.sol";
import { VRFCoordinatorV2_5Mock } from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RngRelayTest is Test {
    MockERC20 internal prizeToken;
    SimpleTwabController internal twab;
    PrizePool internal pool;
    VRFCoordinatorV2_5Mock internal vrfCoordinator;
    RngRelay internal rngRelay;

    address internal constant OWNER = address(0x0A);
    address internal constant ALICE = address(0xA11CE);

    uint32 internal constant PERIOD = 1 days;
    uint32 internal constant OFFSET = 1_000_000;
    bytes32 internal constant KEY_HASH = keccak256("keyHash");
    uint16 internal constant REQUEST_CONFIRMATIONS = 3;
    uint32 internal constant CALLBACK_GAS_LIMIT = 500_000;

    uint256 internal subId;

    function setUp() public {
        prizeToken = new MockERC20("Prize Token", "PRIZE", 18);
        twab = new SimpleTwabController();
        pool = new PrizePool(prizeToken, twab, PERIOD, OFFSET, address(0)); // drawManager 稍后设为 rngRelay

        vrfCoordinator = new VRFCoordinatorV2_5Mock(0, 1e9, 1e18);
        subId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscriptionWithNative{ value: 10 ether }(subId);

        rngRelay =
            new RngRelay(address(vrfCoordinator), pool, KEY_HASH, subId, REQUEST_CONFIRMATIONS, CALLBACK_GAS_LIMIT);
        vrfCoordinator.addConsumer(subId, address(rngRelay));

        // RngRelay 作为 PrizePool 的 drawManager
        pool.setDrawManager(address(rngRelay));

        prizeToken.mint(address(pool), 1_000_000e18);
    }

    function test_request_and_fulfill_opens_draw() public {
        // 在 draw 窗口开始时 mint TWAB，使 ALICE 在整个窗口内有余额
        vm.warp(OFFSET);
        twab.mint(ALICE, 100);
        vm.warp(OFFSET + PERIOD);

        uint256 requestId = rngRelay.requestDraw();
        assertGt(requestId, 0);
        assertEq(rngRelay.pendingRequestId(), requestId);

        vm.expectEmit(true, true, false, false);
        emit IRngRelay.DrawFulfilled(requestId, 1, 0);
        vrfCoordinator.fulfillRandomWords(requestId, address(rngRelay));

        assertEq(rngRelay.pendingRequestId(), 0);
        // ALICE 是唯一 TWAB 持有者，应命中大奖
        assertGt(pool.getClaimableAmount(ALICE, 0, 1), 0);
    }

    function test_request_in_flight_reverts() public {
        vm.warp(OFFSET + PERIOD);
        rngRelay.requestDraw();

        vm.expectRevert(RngRelay.RngRelayRequestInFlight.selector);
        rngRelay.requestDraw();
    }

    function test_request_before_draw_time_reverts() public {
        vm.warp(OFFSET); // 尚未到开奖时间
        vm.expectRevert(abi.encodeWithSelector(RngRelay.RngRelayDrawNotReady.selector, OFFSET + PERIOD, OFFSET));
        rngRelay.requestDraw();
    }

    function test_non_coordinator_cannot_fulfill() public {
        vm.warp(OFFSET + PERIOD);
        uint256 requestId = rngRelay.requestDraw();

        vm.prank(address(0xBAD));
        vm.expectRevert();
        rngRelay.rawFulfillRandomWords(requestId, new uint256[](1));
    }

    function test_award_draw_revert_emits_draw_failed_and_clears_pending() public {
        vm.warp(OFFSET + PERIOD);
        uint256 requestId = rngRelay.requestDraw();

        // 回拨时间使 awardDraw 因时间未到而 revert
        vm.warp(OFFSET);

        vm.expectEmit(true, false, false, false);
        emit IRngRelay.DrawFailed(requestId, 0);
        vrfCoordinator.fulfillRandomWords(requestId, address(rngRelay));

        // pendingRequestId 被清零，不会卡死
        assertEq(rngRelay.pendingRequestId(), 0);
    }

    function test_reset_pending_request_allows_new_request() public {
        vm.warp(OFFSET + PERIOD);
        rngRelay.requestDraw();
        assertGt(rngRelay.pendingRequestId(), 0);

        // address(this) 是 RngRelay 的 owner（部署者）
        rngRelay.resetPendingRequest();
        assertEq(rngRelay.pendingRequestId(), 0);

        // 可再次请求
        vm.warp(OFFSET + PERIOD);
        uint256 newRequestId = rngRelay.requestDraw();
        assertGt(newRequestId, 0);
    }

    function test_reset_pending_request_only_owner() public {
        vm.warp(OFFSET + PERIOD);
        rngRelay.requestDraw();

        vm.prank(address(0xBAD));
        vm.expectRevert();
        rngRelay.resetPendingRequest();
    }
}
