// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @notice 测试用收益金库：普通 ERC4626，可通过 mockHarvest 捐赠资产模拟收益累积。
contract MockERC4626 is ERC4626 {
    constructor(IERC20 asset_) ERC20("Mock Yield Vault", "MYV") ERC4626(asset_) { }

    /// @notice 向金库捐赠 amount 底层资产，抬升份额单价，模拟 Aave/Compound 收益。
    function mockHarvest(uint256 amount) external {
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);
    }
}
