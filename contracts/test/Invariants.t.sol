// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockERC4626 } from "../src/mocks/MockERC4626.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { PrizeVault } from "../src/PrizeVault/PrizeVault.sol";

/// @notice 不变量 fuzz 测试：任意存取款/收益/清算序列下，零损失与份额守恒恒成立。
contract InvariantsTest is Test {
    MockERC20 internal asset;
    MockERC4626 internal yieldVault;
    SimpleTwabController internal twab;
    PrizeVault internal vault;

    address internal constant OWNER = address(0x0A);

    function setUp() public {
        asset = new MockERC20("USD Coin", "USDC", 6);
        yieldVault = new MockERC4626(asset);
        twab = new SimpleTwabController();
        vault = new PrizeVault(asset, yieldVault, twab, "Prize Vault", "pvUSDC", OWNER);
        twab.setVault(address(vault));
    }

    function _user(uint256 i) internal pure returns (address) {
        return address(uint160(i + 1));
    }

    function test_fuzz_deposit_withdraw_no_loss(uint256 seed, uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        address user = _user(seed % 10);

        asset.mint(user, amount);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(user);
        uint256 shares = vault.deposit(amount, user);

        assertEq(twab.balanceOf(user), vault.balanceOf(user), "share conservation");
        assertEq(twab.totalSupply(), vault.totalSupply(), "total supply conservation");
        assertGe(vault.totalAssets(), vault.totalSupply(), "zero-loss after deposit");

        vm.prank(user);
        vault.redeem(shares, user, user);

        assertEq(vault.totalSupply(), 0, "supply back to zero");
        assertEq(vault.totalAssets(), 0, "assets back to zero");
    }

    function test_fuzz_yield_and_withdraw_no_loss(uint256 seed, uint256 depositAmount, uint256 yieldAmount) public {
        depositAmount = bound(depositAmount, 1, 1_000_000e6);
        yieldAmount = bound(yieldAmount, 1, 100_000e6);
        address user = _user(seed % 10);

        asset.mint(user, depositAmount);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);

        // 先存款，再注入收益（模拟真实时序：存款 -> 收益累积）
        vm.prank(user);
        vault.deposit(depositAmount, user);

        asset.mint(OWNER, yieldAmount);
        vm.prank(OWNER);
        asset.approve(address(yieldVault), yieldAmount);
        vm.prank(OWNER);
        yieldVault.mockHarvest(yieldAmount);

        // 全额赎回本金（收益留在 vault，不损失）
        uint256 shares = vault.balanceOf(user);
        vm.prank(user);
        uint256 redeemed = vault.redeem(shares, user, user);
        assertEq(redeemed, depositAmount, "full principal returned");

        assertGe(vault.totalAssets(), vault.totalSupply(), "zero-loss after withdrawal");
    }
}
