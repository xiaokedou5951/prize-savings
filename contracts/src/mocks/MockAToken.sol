// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice 测试用 Aave aToken：与底层 1:1，余额可手动抬升模拟 Aave 利息累积。
/// @dev 铸/销权限仅限构造者（MockAavePool）；UNDERLYING_ASSET_ADDRESS 供
///      AaveYieldVault 构造期校验使用。
contract MockAToken is ERC20 {
    address public immutable pool;
    IERC20 public immutable asset;

    constructor(IERC20 asset_) ERC20("Mock Aave interest USDC", "maUSDC") {
        pool = msg.sender;
        asset = asset_;
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return address(asset);
    }

    /// @notice 仅 pool：supply 时 1:1 铸给存款人（真实 Aave 中 aToken 记在 onBehalfOf 名下）。
    function mint(address to, uint256 amount) external {
        require(msg.sender == pool, "MockAToken: only pool");
        _mint(to, amount);
    }

    /// @notice 仅 pool：withdraw 时 1:1 从 msg.sender（适配器）销毁。
    function burn(address from, uint256 amount) external {
        require(msg.sender == pool, "MockAToken: only pool");
        _burn(from, amount);
    }

    /// @notice 测试工具：无中生有地抬升 holder 余额，模拟 Aave 惰性计息后的余额增长。
    function accrue(address holder, uint256 amount) external {
        _mint(holder, amount);
    }
}
