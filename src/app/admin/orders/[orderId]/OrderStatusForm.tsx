"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";
import { ORDER_NEXT_STATUSES, ORDER_STATUS_LABELS, type OrderStatus } from "@/lib/domain/enums";

/**
 * 注文ステータスの変更 (super_admin)。選べるのは DB の遷移表と同じ次の状態のみ。
 * 発送済みからのキャンセルでは「在庫を戻すか」を必ず選ばせる (0013 の p_restock)。
 */
export function OrderStatusForm({ orderId, current }: { orderId: string; current: OrderStatus }) {
  const router = useRouter();
  const options = ORDER_NEXT_STATUSES[current];
  const [status, setStatus] = useState<OrderStatus | "">(options[0] ?? "");
  const [reason, setReason] = useState("");
  const [restock, setRestock] = useState<"" | "yes" | "no">("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  if (options.length === 0) {
    return (
      <p className="text-[13px] text-text-secondary">
        この注文は「{ORDER_STATUS_LABELS[current]}」のため、これ以上ステータスを変更できません。
      </p>
    );
  }

  const needsRestockChoice = current === "shipped" && status === "cancelled";

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setDone(null);

    const response = await fetch(`/api/admin/orders/${orderId}/status`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        status,
        reason,
        restock: needsRestockChoice ? restock === "yes" : null,
      }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "ステータスの変更に失敗しました。");
      return;
    }
    setDone("ステータスを変更しました。履歴と監査ログに記録されています。");
    setReason("");
    setRestock("");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {options.map((s) => (
          <button
            key={s}
            type="button"
            aria-pressed={status === s}
            onClick={() => setStatus(s)}
            className={`rounded-xl border px-4 py-2.5 text-[14px] font-semibold transition-colors ${
              status === s
                ? s === "cancelled"
                  ? "border-danger bg-danger-soft text-danger"
                  : "border-brand bg-brand-soft text-brand"
                : "border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
            }`}
          >
            {ORDER_STATUS_LABELS[s]}にする
          </button>
        ))}
      </div>

      {status === "cancelled" && current !== "shipped" ? (
        <p className="text-[12px] text-text-secondary">未発送の注文をキャンセルすると、在庫は自動で戻ります。</p>
      ) : null}

      {needsRestockChoice ? (
        <fieldset className="space-y-2 rounded-xl border border-warning/30 bg-warning-soft p-3">
          <legend className="px-1 text-[12px] font-semibold text-text-primary">
            発送済みのため、在庫を戻すかを選んでください (必須)
          </legend>
          {[
            ["yes", "在庫を戻す (返品された商品を再販売できる)"],
            ["no", "在庫を戻さない (返品なし・破損など)"],
          ].map(([value, label]) => (
            <label key={value} className="flex cursor-pointer items-center gap-2 text-[14px] text-text-primary">
              <input
                type="radio"
                name="restock"
                value={value}
                checked={restock === value}
                onChange={() => setRestock(value as "yes" | "no")}
                className="accent-[var(--brand)]"
              />
              {label}
            </label>
          ))}
        </fieldset>
      ) : null}

      <Field label="変更理由 (必須・履歴と監査ログに記録されます)">
        <textarea
          required
          rows={2}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className={FIELD_CLASS}
          placeholder="例: 10/6 入金を確認"
        />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {done ? <FormMessage tone="success">{done}</FormMessage> : null}

      <button
        type="submit"
        disabled={pending || !status || !reason.trim() || (needsRestockChoice && !restock)}
        className={BUTTON_CLASS}
      >
        {pending ? "変更中…" : "ステータスを変更する"}
      </button>
    </form>
  );
}
