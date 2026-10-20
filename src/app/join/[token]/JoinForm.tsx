"use client";

import Link from "next/link";
import { useState } from "react";

import { AgentPledges, NO_PLEDGES, allPledged, type PledgeState } from "@/components/AgentPledges";
import { PrimaryButton } from "@/components/mobile/primitives";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

type Props = {
  token: string;
  /** 現行の代理店規約。未登録 (準備中) なら null */
  terms: { version: string; title: string } | null;
};

/**
 * 代理店登録リンクの申し込みフォーム (運営・代理店のリンク共通)。
 * 1回の送信でアカウント (メール確認済み) の作成と申し込みを行う。ログイン画面へは移動しない。
 * 紹介者はリンクから決まるため、このフォームでは送らない (サーバー側で確定する)。
 */
export function JoinForm({ token, terms }: Props) {
  const [agentDisplayName, setAgentDisplayName] = useState("");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [phone, setPhone] = useState("");
  const [pledges, setPledges] = useState<PledgeState>(NO_PLEDGES);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const canSubmit =
    !pending &&
    allPledged(pledges) &&
    agentDisplayName.trim().length > 0 &&
    fullName.trim().length > 0 &&
    email.trim().length > 0 &&
    password.length >= 8;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!terms) return;
    setPending(true);
    setError(null);

    const response = await fetch("/api/public/agent-applications/via-link", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        token,
        agent_display_name: agentDisplayName,
        full_name: fullName,
        email,
        password,
        phone: phone || null,
        accept_agent_terms: allPledged(pledges),
        agent_terms_version: terms.version,
      }),
    });
    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "お申し込みに失敗しました。");
      setPending(false);
      return;
    }

    setPassword("");
    setMessage((body as { application_message?: string } | null)?.application_message ?? null);
    setPending(false);
  }

  if (message) {
    return (
      <div className="space-y-4">
        <div className="rounded-2xl border border-success-soft bg-success-soft px-4 py-5 text-[15px] leading-6 text-text-primary">
          {message}
        </div>
        <p className="text-[13px] leading-6 text-text-secondary">
          運営の承認後、ご入力のメールアドレスとパスワードで
          <Link href="/login?next=/agent" className="font-medium text-brand underline-offset-2 hover:underline">
            ログイン
          </Link>
          すると、代理店のマイページをご利用いただけます。
        </p>
      </div>
    );
  }

  if (terms === null) {
    return <p className="text-[14px] leading-6 text-text-secondary">代理店登録のお申し込みは現在準備中です。</p>;
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <p className="text-[13px] leading-6 text-text-secondary">
        送信するとアカウントが作成され、お申し込みが運営に届きます。運営が確認・承認したあと、
        ここで設定したメールアドレスとパスワードでログインして代理店としてご利用いただけます。
        このフォームでは会員 (購入者) の登録は行いません。
      </p>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">代理店名</span>
        <input
          required
          value={agentDisplayName}
          onChange={(e) => setAgentDisplayName(e.target.value)}
          maxLength={100}
          className={INPUT}
        />
      </label>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">氏名</span>
        <input
          required
          autoComplete="name"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          maxLength={100}
          className={INPUT}
        />
      </label>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">メールアドレス (ログインに使います)</span>
        <input
          required
          type="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          maxLength={254}
          className={INPUT}
        />
      </label>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">パスワード (8 文字以上)</span>
        <input
          required
          type="password"
          autoComplete="new-password"
          minLength={8}
          maxLength={72}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className={INPUT}
        />
      </label>

      <label className="block space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">電話番号 (任意)</span>
        <input
          type="tel"
          autoComplete="tel"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          maxLength={30}
          className={INPUT}
        />
      </label>

      <AgentPledges terms={terms} value={pledges} onChange={setPledges} />

      {error ? <p className="text-[13px] text-danger">{error}</p> : null}

      <PrimaryButton type="submit" disabled={!canSubmit}>
        {pending ? "送信中…" : "同意して代理店登録を申し込む"}
      </PrimaryButton>
    </form>
  );
}
