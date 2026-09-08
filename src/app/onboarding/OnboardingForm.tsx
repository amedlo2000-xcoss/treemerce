"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton } from "@/components/mobile/primitives";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

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
        <p className="rounded-2xl border border-brand/30 bg-brand-soft px-3.5 py-3 text-[13px] leading-6 text-text-primary">
          招待元: <strong>{inviterName}</strong>
          <br />
          この招待元は登録時に一度だけ確定し、以後は変更できません。
        </p>
      ) : null}

      {lockedInviter ? (
        <p className="rounded-2xl border border-warning-soft bg-warning-soft px-3.5 py-3 text-[13px] leading-6 text-text-primary">
          このアカウントの招待元は既に確定しています。別の招待URLを使っても登録経路は変わりません。
        </p>
      ) : null}

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">代理店名</span>
        <input
          required
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          className={INPUT}
        />
      </label>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">メールアドレス</span>
        <input
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className={INPUT}
        />
      </label>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">電話番号 (任意)</span>
        <input value={phone} onChange={(e) => setPhone(e.target.value)} className={INPUT} />
      </label>

      {error ? <p className="text-[13px] text-danger">{error}</p> : null}

      <PrimaryButton type="submit" disabled={pending}>
        {pending ? "登録中…" : "代理店として登録する"}
      </PrimaryButton>
    </form>
  );
}
