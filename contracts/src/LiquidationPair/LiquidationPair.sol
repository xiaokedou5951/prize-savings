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

    /// @notice 计算当前荷兰拍瞬时价格（以 1e18 为定点精度）。
    /// @dev 价格在每个周期开始时为 startPrice，随周期内剩余时间线性衰减，
    ///      周期结束时降为 0：price = startPrice * (end - now) / periodLength。
    ///      价格递减保证周期内 yield 迟早会被清算者买走。
    /// @return 当前每单位 yield 的奖币价格（PRICE_SCALE = 1e18）
    function _price() internal view returns (uint256) {
        uint32 t = uint32(block.timestamp);
        uint32 end = _periodEnd(t);
        return startPrice * uint256(end - t) / uint256(periodLength);
    }

    /// @notice 当前可供清算的 yield 数量，直接查询 PrizeVault。
    function liquidatableBalanceOf() external view override returns (uint256) {
        return source.liquidatableBalanceOf();
    }

    /// @notice 给定买入数量 amountOut，按当前荷兰拍价格计算需支付的奖币数量 amountIn。
    /// @dev 价格随周期内剩余时间线性衰减（见 _price），以 1e18 为定点精度：
    ///      amountIn = amountOut * price / PRICE_SCALE。
    ///      价格为当前区块的瞬时值，实际成交以 swap 交易所在区块的价格为准。
    /// @param amountOut 想买走的 yield（底层资产）数量
    /// @return 需支付的奖币数量
    function computeExactAmountIn(uint256 amountOut) public view override returns (uint256) {
        return amountOut * _price() / PRICE_SCALE;
    }

    /// @notice 按当前价格买入可清算的 yield：奖币注入奖池，yield 转给 receiver。
    /// @dev 若 amountOut 超过可清算余额则截断为全部可用余额；余额为 0 时直接返回 0。
    /// @param amountOut 想买走的 yield 数量（可能被截断）
    /// @param receiver yield 的接收地址
    /// @return amountIn 实际支付的奖币数量
    function swapExactAmountOut(uint256 amountOut, address receiver) external override returns (uint256 amountIn) {
        uint256 available = source.liquidatableBalanceOf();
        if (amountOut > available) amountOut = available;
        if (amountOut == 0) return 0;

        amountIn = computeExactAmountIn(amountOut);

        tokenIn.safeTransferFrom(msg.sender, prizePool, amountIn);
        source.transferTokensOut(receiver, amountOut);

        emit Liquidation(msg.sender, receiver, amountIn, amountOut);
    }
}
