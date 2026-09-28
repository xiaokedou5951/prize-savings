import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { chains } from "./chains";

/**
 * wagmi Config（由 RainbowKit 组装：connectors + chains + transports）。
 * projectId 从环境变量读入；未配置时使用占位值以通过构建，
 * 实际连接钱包需在 .env 中填写 WalletConnect Cloud projectId。
 */
export const config = getDefaultConfig({
  appName: "Prize Savings",
  projectId:
    process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ??
    "00000000000000000000000000000000",
  chains,
  ssr: true,
});