// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPrizeVault } from "../interfaces/IPrizeVault.sol";
import { ILiquidationPair } from "../interfaces/ILiquidationPair.sol";

/// @notice 清算对：清算者用「奖币」按随时间线性降价的价格买走金库累积的 yield，
///         奖币直接注入奖池。
contract LiquidationPair is ILiquidationPair {
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_SCALE = 1e18;

    IERC20 public immutable override tokenIn; // 奖币
    IERC20 public immutable override tokenOut; // 金库底层资产（yield，USDC）
    IPrizeVault public immutable override source; // PrizeVault
    address public immutable prizePool;

    uint32 public immutable periodLength;
    uint32 public immutable periodOffset;
    uint256 public immutable startPrice;

    error LiquidationPairInvalidConstructor();

    constructor(
        IERC20 tokenIn_,
        IERC20 tokenOut_,
        IPrizeVault source_,
        uint32 periodLength_,
        uint32 periodOffset_,
        uint256 startPrice_,
        address prizePool_
    ) {
        if (
            address(tokenIn_) == address(0) || address(tokenOut_) == address(0) || address(source_) == address(0)
                || prizePool_ == address(0) || periodLength_ == 0
        ) revert LiquidationPairInvalidConstructor();

        tokenIn = tokenIn_;
        tokenOut = tokenOut_;
        source = source_;
        periodLength = periodLength_;
        periodOffset = periodOffset_;
        startPrice = startPrice_;
        prizePool = prizePool_;
    }

    /// @notice 当前时段结束时间（clamp 到下一个周期边界）。
    function _periodEnd(uint32 t) internal view returns (uint32) {
        uint32 delta = t >= periodOffset ? t - periodOffset : 0;
        uint32 elapsed = delta % periodLength;
        return t + (periodLength - elapsed);
    }

    function _price() internal view returns (uint256) {
        uint32 t = uint32(block.timestamp);
        uint32 end = _periodEnd(t);
        return startPrice * uint256(end - t) / uint256(periodLength);
    }

    function liquidatableBalanceOf() external view override returns (uint256) {
        return source.liquidatableBalanceOf();
    }

    function computeExactAmountIn(uint256 amountOut) public view override returns (uint256) {
        return amountOut * _price() / PRICE_SCALE;
    }

    function swapExactAmountOut(uint256 amountOut, address receiver) external override returns (uint256 amountIn) {
        uint256 available = source.liquidatableBalanceOf();
        if (amountOut > available) amountOut = available;
        if (amountOut == 0) return 0;

        amountIn = computeExactAmountIn(amountOut);

        tokenIn.safeTransferFrom(msg.sender, prizePool, amountIn);
        source.transferTokensOut(receiver, amountOut);
    }
}
