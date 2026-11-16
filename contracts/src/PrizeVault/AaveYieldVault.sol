// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Aave V3 Pool 最小接口：适配器只依赖 supply / withdraw 两个动作。
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/// @notice Aave V3 aToken 最小接口：构造期校验 aToken 与底层资产一致。
interface IAaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

/// @title AaveYieldVault：把 Aave V3 供应头寸包装成 ERC-4626 的收益金库适配器。
/// @notice 回退路径：仅当目标市场没有官方 StataToken（StaticAToken，本身就是合规
///         ERC-4626）时才需要本合约；能用 StataToken 时应直接使用它
///         （决策记录见 docs/decisions/ADR-0005-yield-source-stata-first.md）。
/// @dev 关键假设与语义：
///      - Aave v3 aToken 与底层 1:1 计息，利息体现为 aToken 余额增长，因此
///        `totalAssets() = aToken.balanceOf(this)` 即含息总资产；若改接 Compound
///        cToken 等显式汇率代币，必须改为按 exchangeRate 换算，本合约不适用。
///      - 舍入方向沿用 OZ v5.0.0 默认：convertToShares/convertToAssets 向下取整、
///        previewWithdraw/previewMint 向上取整，多出的粉尘留在金库，对零损失方向有利。
///      - maxWithdraw/maxRedeem 不查询 Aave 底层流动性：Aave 流动性枯竭时 redeem
///        直接 revert（与 PRD 10.2 收益源风险一致，属已接受风险）。
///      - OZ v5.0.0 的虚拟份额偏移（+1）只能挡粉尘级攻击，本合约另加 `shares == 0`
///        revert，防止受害者在汇率被抬升后存入资产却换不到份额（变相捐赠）。
///        真正的通胀攻击防护依赖部署时首充 seed：见 Deploy.s.sol（份额发往死地址）。
contract AaveYieldVault is ERC4626 {
    using SafeERC20 for IERC20;

    IAavePool public immutable pool;
    IAaveToken public immutable aToken;

    error AaveYieldVaultAssetMismatch(address aToken, address asset);
    error AaveYieldVaultZeroShares(address receiver, uint256 assets);

    constructor(IERC20 asset_, IAavePool pool_, IAaveToken aToken_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        // 防接线错误：aToken 的底层必须等于金库资产，否则记账与赎回口径错乱。
        if (aToken_.UNDERLYING_ASSET_ADDRESS() != address(asset_)) {
            revert AaveYieldVaultAssetMismatch(address(aToken_), address(asset_));
        }
        pool = pool_;
        aToken = aToken_;
    }

    /// @notice 金库总资产 = 持有的 aToken 余额（含息）。
    function totalAssets() public view override returns (uint256) {
        return IERC20(address(aToken)).balanceOf(address(this));
    }

    /// @dev 存款：拉入底层资产 -> supply 给 Aave（aToken 记在金库名下）-> 铸份额。
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        // 汇率被抬升后 1 单位资产换不到任何份额：宁可拒绝，也不让存款变成捐赠。
        if (shares == 0) revert AaveYieldVaultZeroShares(receiver, assets);
        IERC20 asset_ = IERC20(asset());
        asset_.safeTransferFrom(caller, address(this), assets);
        asset_.forceApprove(address(pool), assets);
        pool.supply(asset(), assets, address(this), 0);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    /// @dev 赎回：销毁份额 -> Aave 把底层资产直接发给 receiver。
    ///      授权语义与 PrizeVault 一致：caller != owner 时按份额扣减 allowance。
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        pool.withdraw(asset(), assets, receiver);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
