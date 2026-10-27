# 存款为 0 但当前 TWAB 有值，是否合理？

## 结论

**合理，这是协议设计的核心特性，不是 Bug。**

## 两个数值的含义不同

前端 `account-summary.tsx` 展示的两个字段语义完全不同：

| 字段 | 数据来源 | 含义 |
|------|----------|------|
| **我的存款** | `vault.userShares`（实时 `balanceOf`） | 用户**当前时刻**的份额余额 |
| **当前 TWAB** | `getTwabBetween(user, start, now)` | **当前开奖周期内**的时间加权平均余额 |

全部赎回后，**当前余额**当然为 0；但只要你在**当前开奖周期内**任何一个时刻持有过份额，时间加权平均就会 > 0。

## 合约侧的验证

`use-twab.ts` 中的查询区间是：

```
start = nextDrawStart - drawPeriodSeconds   // = 当前开奖周期的起点
end   = now（当前时间戳）
```

对应合约 `PrizePool.sol` 开奖时也用**完全相同的区间**计算中奖资格：

```solidity
uint256 userTwab = twabController.getTwabBetween(winner, draw.drawStart, draw.drawEnd);
```

`TwabLibSimple.getTwabBetween` 的算法是：

```
TWAB = (cumulativeAt(end) - cumulativeAt(start)) / (end - start)
```

其中 `cumulative` 是「余额 × 时间」的累计值。即使 `end` 时刻余额为 0，只要 `[start, end]` 区间内某段时间余额 > 0，TWAB 就 > 0。

## 为什么要这样设计

TWAB = Time-Weighted Average Balance（时间加权平均余额）。

**解决什么问题**：防止用户在开奖前瞬间大额存款、开奖后立即取出的套利（"闪电存款攻击"）。

举例说明：假设开奖周期 1 天，你在周期开始时存入 1000 USDC，持有 6 小时后全部赎回：

- 当前余额 = 0
- 若此时已过 12 小时，TWAB = 1000 × 6h / 12h = **500**

你在本次开奖中仍然有中奖资格（权重 500），直到当前周期结束开奖。下个周期若不再存款，TWAB 才会归零。

## 可选的展示优化（非必须）

这个展示容易让用户困惑，建议把"当前 TWAB"改得更语义化，例如：

- 标签改为 **"本期 TWAB"** 或 **"本周期平均存款"**
- 或在下方加一行小字说明："当前开奖周期内的时间加权平均余额，决定本次中奖概率"
