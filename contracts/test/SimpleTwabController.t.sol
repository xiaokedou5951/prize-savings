// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ITwabController } from "../src/interfaces/ITwabController.sol";
import { SimpleTwabController } from "../src/TwabController/SimpleTwabController.sol";
import { TwabControllerBehavior } from "./TwabControllerBehavior.t.sol";

contract SimpleTwabControllerTest is TwabControllerBehavior {
    function _deployTwab() internal override returns (ITwabController) {
        return new SimpleTwabController();
    }
}
