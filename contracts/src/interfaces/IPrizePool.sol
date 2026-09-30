// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPrizePool {
    /// @notice 由 keeper 注入随机数完成一期开奖。
    function awardDraw(uint256 winningRandomNumber) external returns (uint32 drawId);

    /// @notice 领取某期中奖奖金（任意人可代 winner 领取，奖金发给 winner）。
    function claimPrize(address winner, uint8 tier, uint32 drawId) external returns (uint256 amount);

    function isWinner(address winner, uint8 tier, uint32 drawId) external view returns (bool);
    function getClaimableAmount(address winner, uint8 tier, uint32 drawId) external view returns (uint256);

    function prizeToken() external view returns (IERC20);
    function drawPeriodSeconds() external view returns (uint32);
}
