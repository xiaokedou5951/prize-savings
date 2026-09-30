// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 忠实环形缓冲区 Observation 库（实现 B 的底层）。
/// @dev 固定容量环形缓冲区，每回写入覆盖最旧记录，二分查找任意时间点的余额/累计值，
///      回溯最长约 1 年（取决于写入频率）。相较 PoolTogether 的 2 字段 Observation，
///      这里每条额外存储 balance，取值免去对相邻两条的反推，算法语义等价。
library ObservationLib {
    uint256 internal constant MAX_CARDINALITY = 2 ** 16;

    struct Observation {
        uint32 timestamp; // 余额变动时的区块时间
        uint256 balance; // 在 [timestamp, next.timestamp) 内生效的余额
        uint256 cumulativeBalance; // 到 timestamp 为止的「余额 × 时间」累计值
    }

    struct Account {
        uint256 balance; // 当前余额
        uint32 nextIndex; // 累计写入次数（物理槽 = nextIndex % MAX_CARDINALITY）
        uint32 cardinality; // 当前有效 observation 数量（<= MAX_CARDINALITY）
        mapping(uint32 => Observation) ring;
    }

    /// @notice 记录一次余额变动（或同区块内覆盖余额），更新当前余额。
    function checkpoint(Account storage self, uint256 newBalance, uint32 current) internal {
        if (self.cardinality == 0) {
            _write(self, Observation(current, newBalance, 0));
            self.balance = newBalance;
            return;
        }

        Observation storage latest = _latest(self);
        if (latest.timestamp == current) {
            // 同区块多次变动：仅更新余额，累计值不变（无时间流逝）
            latest.balance = newBalance;
            self.balance = newBalance;
            return;
        }

        uint256 cumulative = latest.cumulativeBalance + latest.balance * uint256(current - latest.timestamp);
        _write(self, Observation(current, newBalance, cumulative));
        self.balance = newBalance;
    }

    /// @notice 某时间点的余额（时间 < 最早记录时返回 0）。
    function getBalanceAt(Account storage self, uint32 timestamp) internal view returns (uint256) {
        return _atOrBefore(self, timestamp).balance;
    }

    /// @notice 「余额 × 时间」累计在 timestamp 处的值（分段线性）。
    function getCumulativeAt(Account storage self, uint32 timestamp) internal view returns (uint256) {
        if (self.cardinality == 0) return 0;
        Observation memory obs = _atOrBefore(self, timestamp);
        return obs.cumulativeBalance + obs.balance * uint256(timestamp - obs.timestamp);
    }

    /// @notice [start, end) 之间的时间加权平均余额。
    function getTwabBetween(Account storage self, uint32 start, uint32 end) internal view returns (uint256) {
        if (start >= end) return 0;
        return (getCumulativeAt(self, end) - getCumulativeAt(self, start)) / uint256(end - start);
    }

    function _write(Account storage self, Observation memory obs) private {
        self.ring[uint32(self.nextIndex % MAX_CARDINALITY)] = obs;
        self.nextIndex++;
        if (self.cardinality < MAX_CARDINALITY) {
            self.cardinality++;
        }
    }

    function _latest(Account storage self) private view returns (Observation storage) {
        return self.ring[uint32((uint256(self.nextIndex) - 1) % MAX_CARDINALITY)];
    }

    function _read(Account storage self, uint256 logicalIndex) private view returns (Observation memory) {
        return self.ring[uint32(logicalIndex % MAX_CARDINALITY)];
    }

    /// @notice 二分查找「时间 <= target 的最新 observation」。
    function _atOrBefore(Account storage self, uint32 target) private view returns (Observation memory) {
        if (self.cardinality == 0) return Observation(0, 0, 0);

        uint256 newest = uint256(self.nextIndex) - 1;
        Observation memory obsNewest = _read(self, newest);
        if (target >= obsNewest.timestamp) return obsNewest;

        uint256 oldest = uint256(self.nextIndex) - uint256(self.cardinality);
        Observation memory obsOldest = _read(self, oldest);
        if (target < obsOldest.timestamp) return Observation(0, 0, 0);

        uint256 lo = oldest;
        uint256 hi = newest;
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) / 2;
            if (_read(self, mid).timestamp <= target) lo = mid;
            else hi = mid - 1;
        }
        return _read(self, lo);
    }
}
