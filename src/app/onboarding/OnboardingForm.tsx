"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

const INPUT =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 outline-none focus:border-zinc-500 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100";

export function OnboardingForm({
  defaultEmail,
  invitationCode,
  inviterName,
  lockedInviter,
}: {
  defaultEmail: string;
  invitationCode: string | null;
  inviterName: string | null;
  /** 既に招待元が確定している場合は招待コードを送らない (絶対原則2) */
  lockedInviter: boolean;
}) {
  const router = useRouter();
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState(defaultEmail);
  const [phone, setPhone] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const response = await fetch("/api/agents/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        display_name: displayName,
        email,
        phone: phone || null,
        invitation_code: lockedInviter ? null : invitationCode,
      }),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      setError(body?.error?.message ?? "登録に失敗しました。");
      setPending(false);
      return;
    }

    router.replace("/agent");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {inviterName && !lockedInviter ? (
        <p className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs leading-5 text-blue-900 dark:border-blue-900 dark:bg-blue-950/40 dark:text-blue-200">
          招待元: <strong>{inviterName}</strong>
          <br />
          この招待元は登録時に一度だけ確定し、以後は変更できません。
        </p>
      ) : null}

      {lockedInviter ? (
        <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs leading-5 text-amber-900 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-200">
          このアカウントの招待元は既に確定しています。別の招待URLを使っても登録経路は変わりません。
        </p>
      ) : null}

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">代理店名</span>
        <input
          required
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          className={`mt-1 ${INPUT}`}
        />
      </label>

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">
          メールアドレス
        </span>
        <input
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className={`mt-1 ${INPUT}`}
        />
      </label>

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">
          電話番号 (任意)
        </span>
        <input value={phone} onChange={(e) => setPhone(e.target.value)} className={`mt-1 ${INPUT}`} />
      </label>

      {error ? (
        <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-800 dark:border-red-900 dark:bg-red-950/40 dark:text-red-200">
          {error}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-lg bg-zinc-900 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
      >
        {pending ? "登録中…" : "代理店として登録する"}
      </button>
    </form>
  );
}
