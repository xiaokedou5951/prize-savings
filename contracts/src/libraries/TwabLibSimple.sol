// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 简化时间加权累加器（实现 A）。
/// @dev 与忠实环形缓冲区（ObservationLib）算法结果一致，但采用「追加式 checkpoint + 线性扫描」：
///      - 每次余额变动追加一条 checkpoint（时间、余额、累计值），不做覆盖、不做二分；
///      - 查询时自新向旧线性扫描（近期查询通常在数条内命中）。
///      实现更简单、易审计；代价是最坏情况回溯为 O(历史长度)，适合 MVP/低活跃度场景。
///      生产环境请切换 ObservationTwabController（环形缓冲 + 二分，回溯 1 年）。
library TwabLibSimple {
    struct Checkpoint {
        uint32 timestamp;
        uint256 balance; // 在 [timestamp, next.timestamp) 内生效的余额
        uint256 cumulative; // 到 timestamp 为止的「余额 × 时间」累计值
    }

    struct Account {
        uint256 balance; // 当前余额
        uint256 length; // checkpoint 数量
        mapping(uint256 => Checkpoint) checkpoints; // 0 .. length-1
    }

    function checkpoint(Account storage self, uint256 newBalance, uint32 current) internal {
        if (self.length == 0) {
            self.checkpoints[0] = Checkpoint(current, newBalance, 0);
            self.length = 1;
            self.balance = newBalance;
            return;
        }

        Checkpoint storage last = self.checkpoints[self.length - 1];
        if (last.timestamp == current) {
            last.balance = newBalance;
            self.balance = newBalance;
            return;
        }

        uint256 cumulative = last.cumulative + last.balance * uint256(current - last.timestamp);
        self.checkpoints[self.length] = Checkpoint(current, newBalance, cumulative);
        self.length++;
        self.balance = newBalance;
    }

    function increaseBalance(Account storage self, uint256 amount, uint32 current) internal {
        checkpoint(self, self.balance + amount, current);
    }

    function decreaseBalance(Account storage self, uint256 amount, uint32 current) internal {
        checkpoint(self, self.balance - amount, current);
    }

    function transfer(Account storage from, Account storage to, uint256 amount, uint32 current) internal {
        checkpoint(from, from.balance - amount, current);
        checkpoint(to, to.balance + amount, current);
    }

    function getBalanceAt(Account storage self, uint32 timestamp) internal view returns (uint256) {
        return _atOrBefore(self, timestamp).balance;
    }

    function getCumulativeAt(Account storage self, uint32 timestamp) internal view returns (uint256) {
        if (self.length == 0) return 0;
        Checkpoint memory cp = _atOrBefore(self, timestamp);
        return cp.cumulative + cp.balance * uint256(timestamp - cp.timestamp);
    }

    function getTwabBetween(Account storage self, uint32 start, uint32 end) internal view returns (uint256) {
        if (start >= end) return 0;
        return (getCumulativeAt(self, end) - getCumulativeAt(self, start)) / uint256(end - start);
    }

    function _atOrBefore(Account storage self, uint32 target) private view returns (Checkpoint memory) {
        uint256 i = self.length;
        while (i > 0) {
            i--;
            Checkpoint memory cp = self.checkpoints[i];
            if (cp.timestamp <= target) return cp;
        }
        return Checkpoint(0, 0, 0);
    }
}
