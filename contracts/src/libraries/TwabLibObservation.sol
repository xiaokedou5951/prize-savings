// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ObservationLib } from "./ObservationLib.sol";

/// @notice 忠实环形缓冲区账户层的余额语义（实现 B 用），封装加减/转账。
library TwabLibObservation {
    function increaseBalance(ObservationLib.Account storage self, uint256 amount, uint32 current) internal {
        ObservationLib.checkpoint(self, self.balance + amount, current);
    }

    function decreaseBalance(ObservationLib.Account storage self, uint256 amount, uint32 current) internal {
        ObservationLib.checkpoint(self, self.balance - amount, current);
    }

    function transfer(
        ObservationLib.Account storage from,
        ObservationLib.Account storage to,
        uint256 amount,
        uint32 current
    ) internal {
        ObservationLib.checkpoint(from, from.balance - amount, current);
        ObservationLib.checkpoint(to, to.balance + amount, current);
    }
}
