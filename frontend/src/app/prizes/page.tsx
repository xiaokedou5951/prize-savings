"use client";

import { DrawList } from "@/components/draw-list";
import { PrizePoolCard } from "@/components/prize-pool-card";
import { PrizeTiers } from "@/components/prize-tiers";

export default function PrizesPage() {
  return (
    <div className="flex flex-col gap-8">
      <PrizePoolCard />
      <section>
        <h2 className="mb-4 text-lg font-semibold">奖金分级</h2>
        <PrizeTiers />
      </section>
      <section>
        <h2 className="mb-4 text-lg font-semibold">历史开奖</h2>
        <DrawList />
      </section>
    </div>
  );
}