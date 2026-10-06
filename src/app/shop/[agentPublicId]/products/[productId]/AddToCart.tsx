"use client";

import { Minus, Plus, ShoppingCart } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton } from "@/components/mobile/primitives";
import { useCart } from "@/lib/shop/cart";

export function AddToCart({
  agentPublicId,
  productId,
  maxQuantity,
  disabled,
}: {
  agentPublicId: string;
  productId: string;
  maxQuantity: number;
  disabled: boolean;
}) {
  const router = useRouter();
  const { lines, add } = useCart(agentPublicId);
  const [quantity, setQuantity] = useState(1);
  const [added, setAdded] = useState(false);

  const inCart = lines.find((l) => l.product_id === productId)?.quantity ?? 0;
  const remaining = Math.max(maxQuantity - inCart, 0);
  const canAdd = !disabled && remaining > 0;

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <span className="text-[13px] text-text-secondary">数量</span>
        <div className="flex items-center rounded-2xl border border-border-soft">
          <button
            type="button"
            aria-label="数量を減らす"
            disabled={quantity <= 1}
            onClick={() => setQuantity((q) => Math.max(q - 1, 1))}
            className="flex h-11 w-11 items-center justify-center text-text-primary disabled:opacity-40"
          >
            <Minus size={16} />
          </button>
          <span className="w-10 text-center text-[16px] font-semibold tabular-nums">{quantity}</span>
          <button
            type="button"
            aria-label="数量を増やす"
            disabled={quantity >= remaining}
            onClick={() => setQuantity((q) => Math.min(q + 1, remaining))}
            className="flex h-11 w-11 items-center justify-center text-text-primary disabled:opacity-40"
          >
            <Plus size={16} />
          </button>
        </div>
        {inCart > 0 ? (
          <span className="text-[12px] text-text-secondary">カートに {inCart} 点</span>
        ) : null}
      </div>

      <PrimaryButton
        type="button"
        disabled={!canAdd}
        onClick={() => {
          add(productId, quantity, maxQuantity);
          setAdded(true);
          setQuantity(1);
        }}
      >
        <ShoppingCart size={18} />
        {disabled ? "在庫切れ" : remaining === 0 ? "これ以上追加できません" : "カートに入れる"}
      </PrimaryButton>

      {added ? (
        <PrimaryButton
          type="button"
          variant="secondary"
          onClick={() => router.push(`/shop/${agentPublicId}/checkout`)}
        >
          カートを見て注文手続きへ
        </PrimaryButton>
      ) : null}
    </div>
  );
}
