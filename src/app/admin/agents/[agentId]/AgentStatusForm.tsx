"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

import { AGENT_STATUSES, AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { AgentStatus } from "@/lib/domain/enums";

export function AgentStatusForm({
  agentId,
  currentStatus,
}: {
  agentId: string;
  currentStatus: AgentStatus;
}) {
  const router = useRouter();
  const [status, setStatus] = useState<AgentStatus>(currentStatus);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setDone(null);

    const response = await fetch("/api/admin/agents/status", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ agent_id: agentId, status, reason }),
    });

    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "ステータス変更に失敗しました。");
      setPending(false);
      return;
    }

    setDone("ステータスを変更しました。監査ログに記録されています。");
    setReason("");
    setPending(false);
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <Field label="状態">
        <select
          value={status}
          onChange={(e) => setStatus(e.target.value as AgentStatus)}
          className={FIELD_CLASS}
        >
          {AGENT_STATUSES.map((s) => (
            <option key={s} value={s}>
              {AGENT_STATUS_LABELS[s]}
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

      <button type="submit" disabled={pending || status === currentStatus} className={BUTTON_CLASS}>
        {pending ? "変更中…" : "ステータスを変更する"}
      </button>
    </form>
  );
}
