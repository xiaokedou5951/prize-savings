"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";

const links = [
  { href: "/", label: "首页" },
  { href: "/vault", label: "存款" },
  { href: "/prizes", label: "奖池" },
  { href: "/account", label: "我的账户" },
];

export function Header() {
  const pathname = usePathname();

  return (
    <header className="sticky top-0 z-10 border-b border-zinc-200 bg-white/80 backdrop-blur">
      <div className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between px-4">
        <Link href="/" className="text-lg font-semibold tracking-tight">
          Prize Savings
        </Link>
        <nav className="flex items-center gap-1">
          {links.map((l) => {
            const active = pathname === l.href;
            return (
              <Link
                key={l.href}
                href={l.href}
                className={`rounded-full px-3 py-1.5 text-sm ${
                  active ? "bg-zinc-900 text-white" : "text-zinc-600 hover:bg-zinc-100"
                }`}
              >
                {l.label}
              </Link>
            );
          })}
        </nav>
        <ConnectButton />
      </div>
    </header>
  );
}