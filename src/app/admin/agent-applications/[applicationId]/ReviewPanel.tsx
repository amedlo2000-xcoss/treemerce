"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

type Action = "approve" | "reject";

const TABS: { key: Action; label: string }[] = [
  { key: "approve", label: "承認" },
  { key: "reject", label: "却下" },
];

/**
 * 代理店申請の承認・却下 (super_admin 専用ページから使う。API と DB でも super_admin を再判定)。
 *   承認 : 申請に固定された招待元で代理店を作る。招待元はここでは選べない。
 *   却下 : 代理店は作らない (会員のまま)。理由は監査ログにのみ残る。
 */
export function ReviewPanel({ applicationId }: { applicationId: string }) {
  const router = useRouter();
  const [action, setAction] = useState<Action>("approve");
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const response = await fetch(`/api/admin/agent-applications/${applicationId}/${action}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ reason }),
    });
    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "処理に失敗しました。");
      setPending(false);
      return;
    }

    setPending(false);
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div role="tablist" className="grid grid-cols-2 gap-1 rounded-xl bg-surface-muted p-1">
        {TABS.map((tab) => (
          <button
            key={tab.key}
            type="button"
            role="tab"
            aria-selected={action === tab.key}
            onClick={() => {
              setAction(tab.key);
              setError(null);
            }}
            className={`rounded-lg px-3 py-2 text-[14px] font-semibold transition-colors ${
              action === tab.key ? "bg-surface text-text-primary shadow" : "text-text-secondary"
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <p className="text-[13px] leading-6 text-text-secondary">
        {action === "approve"
          ? "承認すると、申請に固定された招待元で代理店が作られ、すぐに利用できるようになります。"
          : "却下すると代理店は作られず、会員のままです。却下後に本人が改めて申し込んだ場合は、新しい申請として届きます。"}
      </p>

      <Field
        label={action === "approve" ? "承認の理由 (監査ログに記録)" : "却下の理由 (監査ログに記録・本人には表示しない)"}
      >
        <textarea
          required
          rows={3}
          maxLength={1000}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className={FIELD_CLASS}
        />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}

      <button type="submit" disabled={pending || reason.trim().length === 0} className={BUTTON_CLASS}>
        {pending ? "処理中…" : action === "approve" ? "承認する" : "却下する"}
      </button>
    </form>
  );
}
