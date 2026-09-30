// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockERC4626 } from "../src/mocks/MockERC4626.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { PrizeVault } from "../src/PrizeVault/PrizeVault.sol";

contract PrizeVaultTest is Test {
    MockERC20 internal asset;
    MockERC4626 internal yieldVault;
    SimpleTwabController internal twab;
    PrizeVault internal vault;

    address internal constant USER = address(0xA11CE);
    address internal constant OWNER = address(0x0A);
    address internal constant ATTACKER = address(0xBAD);

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC", 6);
        yieldVault = new MockERC4626(asset);
        twab = new SimpleTwabController();
        vault = new PrizeVault(asset, yieldVault, twab, "Prize Vault USDC", "pvUSDC", OWNER);
        twab.setVault(address(vault));

        asset.mint(USER, 1_000_000e6);
        vm.prank(USER);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_deposit_withdraw_full_roundtrip() public {
        uint256 amount = 1000e6;
        vm.prank(USER);
        uint256 shares = vault.deposit(amount, USER);

        assertGt(shares, 0, "shares should be minted");
        assertEq(vault.balanceOf(USER), shares, "vault share balance");
        assertEq(twab.balanceOf(USER), shares, "twab share balance == totalSupply");
        assertEq(vault.totalAssets(), amount, "assets fully invested");

        vm.prank(USER);
        uint256 redeemed = vault.redeem(shares, USER, USER);
        assertEq(redeemed, amount, "full principal returned");
        assertEq(asset.balanceOf(USER), 1_000_000e6, "principal returned to user");
    }

    function test_liquidatable_balance_after_harvest() public {
        vm.prank(USER);
        vault.deposit(1000e6, USER);

        assertEq(vault.liquidatableBalanceOf(), 0, "no yield yet");

        // 注入收益：把收益资产捐赠给底层 yieldVault，抬升单价
        asset.mint(OWNER, 100e6);
        vm.prank(OWNER);
        asset.approve(address(yieldVault), 100e6);
        vm.prank(OWNER);
        yieldVault.mockHarvest(100e6);

        assertGt(vault.totalAssets(), vault.totalSupply(), "assets > supply after yield");
        assertGt(vault.liquidatableBalanceOf(), 0, "yield is liquidatable");
    }

    function test_no_loss_invariant() public {
        vm.prank(USER);
        vault.deposit(1000e6, USER);

        asset.mint(OWNER, 123e6);
        vm.prank(OWNER);
        asset.approve(address(yieldVault), 123e6);
        vm.prank(OWNER);
        yieldVault.mockHarvest(123e6);

        // 部分赎回后仍满足 totalAssets >= totalSupply
        uint256 shares = vault.balanceOf(USER);
        vm.prank(USER);
        vault.redeem(shares / 2, USER, USER);

        assertGe(vault.totalAssets(), vault.totalSupply(), "zero-loss invariant");
    }

    function test_transferTokensOut_only_liquidation_pair() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        vault.transferTokensOut(ATTACKER, 1);
    }

    function test_setLiquidationPair_only_owner() public {
        vm.prank(ATTACKER);
        vm.expectRevert();
        vault.setLiquidationPair(ATTACKER);
    }
}
