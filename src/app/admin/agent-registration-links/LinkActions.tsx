"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { CopyField } from "@/app/agent/invitations/InvitationPanel";
import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

/** 代理店登録リンクの発行。発行した URL はこの画面でだけ表示する (再表示はできない)。 */
export function IssueLinkForm() {
  const router = useRouter();
  const [note, setNote] = useState("");
  const [maxUses, setMaxUses] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [issuedUrl, setIssuedUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setIssuedUrl(null);

    const response = await fetch("/api/admin/agent-registration-links", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        note: note || null,
        max_uses: maxUses ? Number(maxUses) : null,
        // datetime-local の値はブラウザのタイムゾーンの日時として扱う
        expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
      }),
    });
    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "リンクを発行できませんでした。");
      setPending(false);
      return;
    }

    setIssuedUrl(`${window.location.origin}/join/${(body as { token: string }).token}`);
    setNote("");
    setMaxUses("");
    setExpiresAt("");
    setPending(false);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <form onSubmit={handleSubmit} className="grid gap-4 sm:grid-cols-3">
        <Field label="メモ (任意・誰に渡すか等)" className="sm:col-span-3">
          <input value={note} onChange={(e) => setNote(e.target.value)} maxLength={200} className={FIELD_CLASS} />
        </Field>
        <Field label="使用回数の上限 (任意)">
          <input
            type="number"
            min={1}
            step={1}
            inputMode="numeric"
            value={maxUses}
            onChange={(e) => setMaxUses(e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <Field label="有効期限 (任意)">
          <input
            type="datetime-local"
            value={expiresAt}
            onChange={(e) => setExpiresAt(e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <div className="flex items-end">
          <button type="submit" disabled={pending} className={BUTTON_CLASS}>
            {pending ? "発行中…" : "リンクを発行する"}
          </button>
        </div>
      </form>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}

      {issuedUrl ? (
        <div className="space-y-2 rounded-xl border border-warning/30 bg-warning-soft px-3 py-3">
          <p className="text-[13px] font-semibold leading-5 text-text-primary">
            発行したリンクです。この画面を離れると再表示できません。今のうちにコピーしてください。
          </p>
          <CopyField label="URL" value={issuedUrl} />
        </div>
      ) : null}
    </div>
  );
}

/** 代理店登録リンクの無効化 (理由必須)。以後の申し込みを受け付けない。 */
export function RevokeLinkButton({ linkId }: { linkId: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleRevoke(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const response = await fetch(`/api/admin/agent-registration-links/${linkId}/revoke`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ reason }),
    });
    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "無効化できませんでした。");
      setPending(false);
      return;
    }

    setPending(false);
    setOpen(false);
    router.refresh();
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="whitespace-nowrap rounded-xl border border-border-soft px-3 py-1.5 text-[13px] font-medium text-danger hover:bg-surface-muted"
      >
        無効化
      </button>
    );
  }

  return (
    <form onSubmit={handleRevoke} className="min-w-[14rem] space-y-2">
      <textarea
        required
        rows={2}
        maxLength={1000}
        placeholder="無効化の理由 (監査ログに記録)"
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        className={FIELD_CLASS}
      />
      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={pending || !reason.trim()} className={BUTTON_CLASS}>
          {pending ? "処理中…" : "無効化する"}
        </button>
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="rounded-xl border border-border-soft px-3 py-2 text-[13px] font-medium text-text-secondary"
        >
          やめる
        </button>
      </div>
    </form>
  );
}
