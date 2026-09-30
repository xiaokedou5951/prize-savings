// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TwabERC20 } from "./TwabERC20.sol";
import { ITwabController } from "../interfaces/ITwabController.sol";
import { IPrizeVault } from "../interfaces/IPrizeVault.sol";

/// @notice ERC-4626 收益金库：把用户资产投入底层 yieldVault 赚取收益，
///         份额记入 TwabController；超过「本金 + yield buffer」的收益可被清算者买走。
/// @dev 不变量：totalAssets() >= totalSupply()（零损失）。
contract PrizeVault is TwabERC20, ERC4626, Ownable, IPrizeVault {
    using SafeERC20 for IERC20;

    IERC4626 public immutable yieldVault;
    address public liquidationPair;
    uint256 public yieldBuffer;

    error PrizeVaultOnlyLiquidationPair(address caller);
    error PrizeVaultZeroAddress();

    modifier onlyLiquidationPair() {
        if (msg.sender != liquidationPair) revert PrizeVaultOnlyLiquidationPair(msg.sender);
        _;
    }

    constructor(
        IERC20 asset_,
        IERC4626 yieldVault_,
        ITwabController twabController_,
        string memory name_,
        string memory symbol_,
        address owner_
    ) TwabERC20(twabController_, name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        if (address(yieldVault_) == address(0)) revert PrizeVaultZeroAddress();
        yieldVault = yieldVault_;
    }

    /// @notice 金库总资产 = 底层 yieldVault 份额价值 + 合约持有的 loose 资产。
    function totalAssets() public view override(IERC4626, ERC4626) returns (uint256) {
        return
            yieldVault.convertToAssets(yieldVault.balanceOf(address(this))) + IERC20(asset()).balanceOf(address(this));
    }

    /// @dev 份额与资产 1:1（本金基准）：收益不摊回份额，而是作为超额留在金库待清算。
    ///      因此 convertToShares / convertToAssets 为恒等映射。
    function _convertToShares(uint256 assets, Math.Rounding) internal pure override returns (uint256) {
        return assets;
    }

    function _convertToAssets(uint256 shares, Math.Rounding) internal pure override returns (uint256) {
        return shares;
    }

    /// @notice 可被清算者买走的 yield（超过本金 + buffer 的部分）。
    function liquidatableBalanceOf() public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 supply = totalSupply() + yieldBuffer;
        return assets > supply ? assets - supply : 0;
    }

    /// @notice 仅 LiquidationPair 可调：把 amountOut 底层资产转给 receiver。
    function transferTokensOut(address receiver, uint256 amountOut)
        external
        override
        onlyLiquidationPair
        returns (uint256)
    {
        if (receiver == address(0)) revert PrizeVaultZeroAddress();
        _pullAssets(amountOut);
        IERC20(asset()).safeTransfer(receiver, amountOut);
        return amountOut;
    }

    function setLiquidationPair(address liquidationPair_) external override onlyOwner {
        liquidationPair = liquidationPair_;
    }

    function setYieldBuffer(uint256 yieldBuffer_) external override onlyOwner {
        yieldBuffer = yieldBuffer_;
    }

    // ---- ERC20 多继承消歧（余额/总供应/转账路由到 TwabController） ----

    function balanceOf(address account) public view override(TwabERC20, ERC20, IERC20) returns (uint256) {
        return twabController.balanceOf(account);
    }

    function totalSupply() public view override(TwabERC20, ERC20, IERC20) returns (uint256) {
        return twabController.totalSupply();
    }

    function decimals() public view override(ERC4626, ERC20, IERC20Metadata) returns (uint8) {
        return ERC4626.decimals();
    }

    function _update(address from, address to, uint256 value) internal override(TwabERC20, ERC20) {
        TwabERC20._update(from, to, value);
    }

    // ---- ERC4626 覆写：存取款时把资产投入/取回底层 yieldVault ----

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        IERC20 asset_ = IERC20(asset());
        asset_.safeTransferFrom(caller, address(this), assets);
        asset_.forceApprove(address(yieldVault), assets);
        yieldVault.deposit(assets, address(this));
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        _pullAssets(assets);
        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice 尽量从底层 yieldVault 赎回 target 底层资产（先耗尽 yield，不足则用 loose 余额兜底）。
    function _pullAssets(uint256 target) internal {
        uint256 loose = IERC20(asset()).balanceOf(address(this));
        if (loose >= target) return;

        uint256 need = target - loose;
        uint256 redeemableShares = yieldVault.maxRedeem(address(this));
        if (redeemableShares == 0) return;
        uint256 shares = yieldVault.previewWithdraw(need);
        if (shares > redeemableShares) shares = redeemableShares;
        yieldVault.redeem(shares, address(this), address(this));
    }
}
