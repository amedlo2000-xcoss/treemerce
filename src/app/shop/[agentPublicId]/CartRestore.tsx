"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect } from "react";

import { useCart } from "@/lib/shop/cart";
import { CART_PARAM, decodeCart } from "@/lib/shop/return-to";

/**
 * 会員登録・ログインから戻ってきたとき (?cart=...) に、カートの中身をこのブラウザに戻す。
 * 戻したあとは URL から ?cart= を外す (再読み込みで数量が二重にならないように)。
 */
export function CartRestore({ agentPublicId }: { agentPublicId: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { merge } = useCart(agentPublicId);
  const raw = searchParams.get(CART_PARAM);

  useEffect(() => {
    if (raw === null) return;
    const lines = decodeCart(raw);
    if (lines.length > 0) merge(lines);
    const rest = new URLSearchParams(searchParams.toString());
    rest.delete(CART_PARAM);
    const query = rest.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  }, [raw, merge, pathname, router, searchParams]);

  return null;
}
