"use client";

import { AccountSummary } from "@/components/account-summary";
import { ClaimPrizes } from "@/components/claim-prizes";

export default function AccountPage() {
  return (
    <div className="flex flex-col gap-8">
      <AccountSummary />
      <ClaimPrizes />
    </div>
  );
}