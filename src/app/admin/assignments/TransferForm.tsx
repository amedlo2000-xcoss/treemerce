"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

const INPUT =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-500 dark:border-zinc-700 dark:bg-zinc-900";

export function TransferForm({
  customers,
  agents,
}: {
  customers: { id: string; label: string; currentAgentId: string | null }[];
  agents: { id: string; label: string }[];
}) {
  const router = useRouter();
  const [customerId, setCustomerId] = useState("");
  const [newAgentId, setNewAgentId] = useState("");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const current = customers.find((c) => c.id === customerId);

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
      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">対象の購入者</span>
        <select
          required
          value={customerId}
          onChange={(e) => setCustomerId(e.target.value)}
          className={`mt-1 ${INPUT}`}
        >
          <option value="">選択してください</option>
          {customers.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">
          変更先の代理店
        </span>
        <select
          required
          value={newAgentId}
          onChange={(e) => setNewAgentId(e.target.value)}
          className={`mt-1 ${INPUT}`}
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
      </label>

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">
          変更理由 (監査ログに記録されます)
        </span>
        <textarea
          required
          rows={3}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className={`mt-1 ${INPUT}`}
        />
      </label>

      {error ? (
        <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-800 dark:border-red-900 dark:bg-red-950/40 dark:text-red-200">
          {error}
        </p>
      ) : null}
      {done ? (
        <p className="rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs text-emerald-800 dark:border-emerald-900 dark:bg-emerald-950/40 dark:text-emerald-200">
          {done}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className="rounded-lg bg-zinc-900 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
      >
        {pending ? "変更中…" : "担当を変更する"}
      </button>
    </form>
  );
}
