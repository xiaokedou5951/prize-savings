// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPrizeVault } from "./IPrizeVault.sol";

interface ILiquidationPair {
    function tokenIn() external view returns (IERC20); // 奖币
    function tokenOut() external view returns (IERC20); // 金库底层资产（yield）
    function source() external view returns (IPrizeVault); // PrizeVault

    function liquidatableBalanceOf() external view returns (uint256);

    /// @notice 清算 amountOut 个 yield 所需的奖币数量（按当前线性降价价格）。
    function computeExactAmountIn(uint256 amountOut) external view returns (uint256);

    /// @notice 用奖币买走 amountOut 个 yield，奖币注入奖池，yield 给 receiver。
    function swapExactAmountOut(uint256 amountOut, address receiver) external returns (uint256 amountIn);
}
