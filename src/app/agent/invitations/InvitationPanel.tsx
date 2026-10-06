"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton } from "@/components/mobile/primitives";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-2.5 text-[15px] text-text-primary outline-none focus:border-brand";

export function InvitationPanel({ origin }: { origin: string }) {
  const router = useRouter();
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function create() {
    setPending(true);
    setError(null);

    const response = await fetch("/api/agents/invitations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ note: note || null }),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      setError(body?.error?.message ?? "招待URLの発行に失敗しました。");
      setPending(false);
      return;
    }

    setNote("");
    setPending(false);
    router.refresh();
  }

  return (
    <div className="space-y-3">
      <p className="text-[13px] leading-5 text-text-secondary">
        発行した招待URLから登録した代理店は、あなたを招待元として記録されます。
        招待元は1代理店につき1つで、登録時に一度だけ確定します。
        {origin ? null : ""}
      </p>
      <div className="flex flex-wrap gap-2">
        <input
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="メモ (任意)"
          className={`flex-1 ${INPUT}`}
        />
        <PrimaryButton type="button" onClick={create} disabled={pending} className="!w-auto px-5">
          {pending ? "発行中…" : "招待URLを発行"}
        </PrimaryButton>
      </div>
      {error ? <p className="text-[13px] text-danger">{error}</p> : null}
    </div>
  );
}

export function CopyField({ label, value }: { label: string; value: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <div className="flex flex-wrap items-center gap-2">
      {label ? <span className="w-16 shrink-0 text-[13px] text-text-secondary">{label}</span> : null}
      <code className="flex-1 truncate rounded-lg bg-surface-muted px-2.5 py-1.5 font-mono text-[12px] text-text-primary">
        {value}
      </code>
      <button
        type="button"
        onClick={async () => {
          await navigator.clipboard.writeText(value);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        }}
        className="shrink-0 rounded-lg border border-border-soft px-2.5 py-1.5 text-[12px] font-medium text-text-primary transition-colors hover:bg-surface-muted"
      >
        {copied ? "コピー済" : "コピー"}
      </button>
    </div>
  );
}
