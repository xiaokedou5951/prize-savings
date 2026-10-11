/** 零地址占位：用于未部署/未连接时填充读取参数（查询被 enabled 关闭，不会真正发出请求）。 */
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as const;

/** 奖金分级名称（对应 PrizePool 硬编码 3 档）。 */
export const TIER_NAMES = ["Grand Prize", "次级奖", "Canary 奖"] as const;

/** 奖金分级档数（PrizePool.TIER_COUNT）。 */
export const TIER_COUNT = 3;