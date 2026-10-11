"use client";

import Link from "next/link";
import { PrizePoolCard } from "@/components/prize-pool-card";

export default function Home() {
  return (
    <div className="flex flex-col gap-12">
      <section className="py-16 text-center">
        <h1 className="text-4xl font-bold leading-tight tracking-tight sm:text-5xl">
          存钱，抽奖，本金零损失
        </h1>
        <p className="mx-auto mt-4 max-w-xl text-lg text-zinc-600">
          存入 USDC 参与每日抽奖。奖金来自存款收益，本金随时全额可取。
        </p>
        <Link
          href="/vault"
          className="mt-8 inline-block rounded-full bg-zinc-900 px-8 py-3 text-white transition hover:bg-zinc-700"
        >
          开始存款
        </Link>
      </section>

      <PrizePoolCard />

      <div className="text-center text-sm text-zinc-500">
        <Link href="/prizes" className="hover:underline">
          查看历史开奖与中奖记录 →
        </Link>
      </div>
    </div>
  );
}