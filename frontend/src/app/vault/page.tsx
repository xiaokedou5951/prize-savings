"use client";

import { AccountSummary } from "@/components/account-summary";
import { DepositForm } from "@/components/deposit-form";
import { WithdrawForm } from "@/components/withdraw-form";

export default function VaultPage() {
  return (
    <div className="flex flex-col gap-8">
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <DepositForm />
        <WithdrawForm />
      </div>
      <AccountSummary />
    </div>
  );
}