"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton } from "@/components/mobile/primitives";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-2.5 text-[15px] text-text-primary outline-none focus:border-brand";

/** 取り下げ (本人の下書き・差し戻しのみ)。申請は削除されず「取り下げ」として残る。 */
export function WithdrawButton({ submissionId }: { submissionId: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleWithdraw() {
    setPending(true);
    setError(null);
    const response = await fetch(`/api/agent/submissions/${submissionId}/withdraw`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ reason: reason || null }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);
    if (!response.ok) {
      setError(body?.error?.message ?? "取り下げに失敗しました。");
      return;
    }
    router.refresh();
  }

  if (!open) {
    return (
      <PrimaryButton variant="ghost" onClick={() => setOpen(true)}>
        この申請を取り下げる
      </PrimaryButton>
    );
  }

  return (
    <div className="space-y-3 rounded-2xl border border-border-soft p-4">
      <p className="text-[13px] leading-5 text-text-primary">
        取り下げると、この申請は編集・再申請できなくなります (記録は残ります)。
      </p>
      <label className="block space-y-1.5">
        <span className="text-[13px] font-medium text-text-secondary">理由 (任意)</span>
        <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} className={INPUT} />
      </label>
      {error ? <p role="alert" className="text-[13px] text-danger">{error}</p> : null}
      <div className="flex gap-2">
        <PrimaryButton variant="secondary" onClick={() => setOpen(false)} disabled={pending}>
          やめる
        </PrimaryButton>
        <PrimaryButton onClick={handleWithdraw} disabled={pending}>
          {pending ? "処理中…" : "取り下げる"}
        </PrimaryButton>
      </div>
    </div>
  );
}
