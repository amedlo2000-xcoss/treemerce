"use client";

import { useCallback, useMemo, useSyncExternalStore } from "react";

/**
 * 公開ショップのカート。紹介リンク (代理店の公開ID) ごとにブラウザの localStorage に保持する。
 * 価格・在庫はここには持たない (注文時にサーバーが必ず最新の値で再計算する)。
 * localStorage が使えない環境 (プライベートモード等) でも落ちないよう、読み書きは try で包む。
 */
export type CartLine = { product_id: string; quantity: number };

const EVENT = "treemerce:cart";
const keyFor = (publicId: string) => `treemerce:cart:${publicId}`;

function readRaw(publicId: string): string {
  try {
    return window.localStorage.getItem(keyFor(publicId)) ?? "[]";
  } catch {
    return "[]";
  }
}

function parse(raw: string): CartLine[] {
  try {
    const value = JSON.parse(raw) as unknown;
    if (!Array.isArray(value)) return [];
    return value.filter(
      (l): l is CartLine =>
        typeof l === "object" &&
        l !== null &&
        typeof (l as CartLine).product_id === "string" &&
        Number.isInteger((l as CartLine).quantity) &&
        (l as CartLine).quantity > 0,
    );
  } catch {
    return [];
  }
}

function write(publicId: string, lines: CartLine[]) {
  try {
    window.localStorage.setItem(keyFor(publicId), JSON.stringify(lines));
  } catch {
    // 保存できなくても画面上の操作は続けられる
  }
  window.dispatchEvent(new Event(EVENT));
}

function subscribe(callback: () => void) {
  window.addEventListener(EVENT, callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener(EVENT, callback);
    window.removeEventListener("storage", callback);
  };
}

export function useCart(publicId: string) {
  const raw = useSyncExternalStore(
    subscribe,
    () => readRaw(publicId),
    () => "[]",
  );
  const lines = useMemo(() => parse(raw), [raw]);

  const setQuantity = useCallback(
    (productId: string, quantity: number) => {
      const current = parse(readRaw(publicId));
      const next =
        quantity <= 0
          ? current.filter((l) => l.product_id !== productId)
          : current.some((l) => l.product_id === productId)
            ? current.map((l) => (l.product_id === productId ? { ...l, quantity } : l))
            : [...current, { product_id: productId, quantity }];
      write(publicId, next);
    },
    [publicId],
  );

  const add = useCallback(
    (productId: string, quantity: number, max: number) => {
      const current = parse(readRaw(publicId)).find((l) => l.product_id === productId);
      setQuantity(productId, Math.min((current?.quantity ?? 0) + quantity, max));
    },
    [publicId, setQuantity],
  );

  const clear = useCallback(() => write(publicId, []), [publicId]);

  const count = lines.reduce((sum, l) => sum + l.quantity, 0);

  return { lines, count, add, setQuantity, clear };
}
