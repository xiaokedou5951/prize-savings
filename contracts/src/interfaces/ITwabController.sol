// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 时间加权平均余额（TWAB）控制器的统一接口。
/// @dev PrizeVault / PrizePool 只依赖此接口，不感知具体实现
///      （SimpleTwabController 或 ObservationTwabController），从而可配置切换。
interface ITwabController {
    // 仅 PrizeVault 可调的余额变更
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function transfer(address from, address to, uint256 amount) external;

    // 当前余额 / 总供应
    function balanceOf(address user) external view returns (uint256);
    function totalSupply() external view returns (uint256);

    // 时间加权
    function getBalanceAt(address user, uint32 timestamp) external view returns (uint256);
    function getTwabBetween(address user, uint32 start, uint32 end) external view returns (uint256);
    function getTotalSupplyAt(uint32 timestamp) external view returns (uint256);
    function getAverageTotalSupplyBetween(uint32 start, uint32 end) external view returns (uint256);
}
