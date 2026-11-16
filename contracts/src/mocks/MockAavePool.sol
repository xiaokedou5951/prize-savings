// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { MockAToken } from "./MockAToken.sol";

/// @notice 测试用 Aave Pool：构造时部署配套 MockAToken；supply/withdraw 的资金流
///         与真实 Aave 一致（底层进 pool、aToken 记在 onBehalfOf 名下），但不模拟
///         利率曲线与惰性计息——计息用 MockAToken.accrue 手动触发。
contract MockAavePool {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    MockAToken public immutable aToken;

    constructor(IERC20 asset_) {
        asset = asset_;
        aToken = new MockAToken(asset_); // MockAToken 以构造者（本 pool）为铸/销权限
    }

    function supply(address, uint256 amount, address onBehalfOf, uint16) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address, uint256 amount, address to) external returns (uint256) {
        aToken.burn(msg.sender, amount);
        asset.safeTransfer(to, amount);
        return amount;
    }
}
