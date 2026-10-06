"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

type FixedCustomer = { id: string; label: string; currentAgentId: string | null };

export function TransferForm({
  customers,
  agents,
  fixedCustomer,
}: {
  customers?: { id: string; label: string; currentAgentId: string | null }[];
  agents: { id: string; label: string }[];
  /** 顧客詳細ページから呼ぶ場合: 対象顧客を固定し、顧客セレクトを省略する。 */
  fixedCustomer?: FixedCustomer;
}) {
  const router = useRouter();
  const [customerId, setCustomerId] = useState(fixedCustomer?.id ?? "");
  const [newAgentId, setNewAgentId] = useState("");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const current = fixedCustomer ?? (customers ?? []).find((c) => c.id === customerId);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setDone(null);

    const response = await fetch("/api/admin/assignments/transfer", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        customer_id: customerId,
        new_agent_id: newAgentId,
        reason,
      }),
    });

    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "担当変更に失敗しました。");
      setPending(false);
      return;
    }

    setDone("担当を変更しました。履歴と監査ログに記録されています。");
    setReason("");
    setNewAgentId("");
    setPending(false);
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {fixedCustomer ? (
        <div className="rounded-xl bg-surface-muted px-3 py-2.5">
          <span className="block text-[12px] font-semibold text-text-secondary">対象の購入者</span>
          <p className="mt-0.5 text-[14px] font-semibold text-text-primary">{fixedCustomer.label}</p>
        </div>
      ) : (
        <Field label="対象の購入者">
          <select
            required
            value={customerId}
            onChange={(e) => setCustomerId(e.target.value)}
            className={FIELD_CLASS}
          >
            <option value="">選択してください</option>
            {(customers ?? []).map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </select>
        </Field>
      )}

      <Field label="変更先の代理店">
        <select
          required
          value={newAgentId}
          onChange={(e) => setNewAgentId(e.target.value)}
          className={FIELD_CLASS}
        >
          <option value="">選択してください</option>
          {agents
            .filter((a) => a.id !== current?.currentAgentId)
            .map((a) => (
              <option key={a.id} value={a.id}>
                {a.label}
              </option>
            ))}
        </select>
      </Field>

      <Field label="変更理由 (監査ログに記録されます)">
        <textarea
          required
          rows={3}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className={FIELD_CLASS}
        />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {done ? <FormMessage tone="success">{done}</FormMessage> : null}

      <button type="submit" disabled={pending} className={BUTTON_CLASS}>
        {pending ? "変更中…" : "担当を変更する"}
      </button>
    </form>
  );
}
