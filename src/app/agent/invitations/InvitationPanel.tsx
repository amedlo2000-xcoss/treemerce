"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

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
      <p className="text-xs leading-5 text-zinc-500 dark:text-zinc-400">
        発行した招待URLから登録した代理店は、あなたを招待元として記録されます。
        招待元は1代理店につき1つで、登録時に一度だけ確定します。
        {origin ? null : ""}
      </p>
      <div className="flex flex-wrap gap-2">
        <input
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="メモ (任意)"
          className="flex-1 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-zinc-500 dark:border-zinc-700 dark:bg-zinc-900"
        />
        <button
          type="button"
          onClick={create}
          disabled={pending}
          className="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
        >
          {pending ? "発行中…" : "招待URLを発行"}
        </button>
      </div>
      {error ? <p className="text-xs text-red-700 dark:text-red-400">{error}</p> : null}
    </div>
  );
}

export function CopyField({ label, value }: { label: string; value: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="w-24 shrink-0 text-xs text-zinc-500 dark:text-zinc-400">{label}</span>
      <code className="flex-1 truncate rounded-md bg-zinc-100 px-2 py-1 font-mono text-xs text-zinc-800 dark:bg-zinc-800 dark:text-zinc-200">
        {value}
      </code>
      <button
        type="button"
        onClick={async () => {
          await navigator.clipboard.writeText(value);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        }}
        className="rounded-md border border-zinc-300 px-2 py-1 text-xs text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
      >
        {copied ? "コピー済" : "コピー"}
      </button>
    </div>
  );
}
