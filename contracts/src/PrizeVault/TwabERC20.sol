// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ITwabController } from "../interfaces/ITwabController.sol";

/// @notice 份额 ERC20：把余额/总供应/转账路由到 TwabController，
///         使 PrizeVault 的份额具有时间加权可追溯能力。
abstract contract TwabERC20 is ERC20 {
    ITwabController public immutable twabController;

    constructor(ITwabController twabController_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        twabController = twabController_;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return twabController.balanceOf(account);
    }

    function totalSupply() public view virtual override returns (uint256) {
        return twabController.totalSupply();
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0)) {
            twabController.mint(to, value);
        } else if (to == address(0)) {
            twabController.burn(from, value);
        } else {
            twabController.transfer(from, to, value);
        }
        emit Transfer(from, to, value);
    }
}
