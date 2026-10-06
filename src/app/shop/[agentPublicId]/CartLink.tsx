"use client";

import { ShoppingCart } from "lucide-react";
import Link from "next/link";

import { useCart } from "@/lib/shop/cart";

export function CartLink({ agentPublicId }: { agentPublicId: string }) {
  const { count } = useCart(agentPublicId);

  return (
    <Link
      href={`/shop/${agentPublicId}/checkout`}
      aria-label={`カート (${count}点)`}
      className="relative flex h-10 w-10 items-center justify-center rounded-full border border-border-soft bg-surface text-text-primary transition-colors hover:bg-surface-muted"
    >
      <ShoppingCart size={18} />
      {count > 0 ? (
        <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-brand px-1 text-[11px] font-bold tabular-nums text-brand-foreground">
          {count > 99 ? "99+" : count}
        </span>
      ) : null}
    </Link>
  );
}
