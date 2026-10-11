"use client";

import type { ReactNode } from "react";
import { Header } from "./header";

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8">{children}</main>
    </>
  );
}