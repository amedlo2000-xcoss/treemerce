"use client";

import { useRouter } from "next/navigation";
import { useState, useSyncExternalStore } from "react";

import { AgentPledges, NO_PLEDGES, allPledged, type PledgeState } from "@/components/AgentPledges";
import { PrimaryButton } from "@/components/mobile/primitives";
import type { MyAgentApplication } from "@/lib/domain/types";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

/**
 * ログイン・メール確認のためにページを離れる間だけ、入力内容をこのブラウザに保存する
 * (紹介リンクのフォームと同じ扱い: localStorage・24 時間で破棄・送信に成功したら消す・同意は保存しない)。
 */
type Draft = { agentDisplayName: string; phone: string };
const DRAFT_KEY = "treemerce:join-draft";
const DRAFT_TTL_MS = 24 * 60 * 60 * 1000;

function readDraftRaw(): string | null {
  try {
    return window.localStorage.getItem(DRAFT_KEY);
  } catch {
    return null;
  }
}

function saveDraft(draft: Draft) {
  try {
    window.localStorage.setItem(DRAFT_KEY, JSON.stringify({ ...draft, savedAt: Date.now() }));
  } catch {
    // 保存できなくてもログイン後に入力し直せる
  }
}

function clearDraft() {
  try {
    window.localStorage.removeItem(DRAFT_KEY);
  } catch {
    // 何もしない
  }
}

function parseDraft(raw: string | null): Draft | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<Draft & { savedAt: number }>;
    if (typeof value.savedAt !== "number" || Date.now() - value.savedAt > DRAFT_TTL_MS) return null;
    return {
      agentDisplayName: typeof value.agentDisplayName === "string" ? value.agentDisplayName : "",
      phone: typeof value.phone === "string" ? value.phone : "",
    };
  } catch {
    return null;
  }
}

const noopSubscribe = () => () => {};

type Props = {
  token: string;
  /** 現行の代理店規約。未登録 (準備中) なら null */
  terms: { version: string; title: string } | null;
  /** ログイン中のアカウント。未ログインなら null */
  account: { email: string | null; confirmed: boolean } | null;
  /** 本人の申請状況 (中立的な文面のみ) */
  application: MyAgentApplication | null;
  isAgent: boolean;
};

/** サーバー描画では保存した入力内容を読めないため、ブラウザで読めた時点で key を変えて描き直す */
export function JoinForm(props: Props) {
  const draftRaw = useSyncExternalStore(noopSubscribe, readDraftRaw, () => null);
  const draft = parseDraft(draftRaw);
  return <JoinFormInner key={draft ? "resume" : "fresh"} {...props} draft={draft} />;
}

function JoinFormInner({ token, terms, account, application, isAgent, draft }: Props & { draft: Draft | null }) {
  const router = useRouter();
  const [agentDisplayName, setAgentDisplayName] = useState(draft?.agentDisplayName ?? "");
  const [phone, setPhone] = useState(draft?.phone ?? "");
  const [pledges, setPledges] = useState<PledgeState>(NO_PLEDGES);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const accountReady = Boolean(account?.email && account.confirmed);
  const canSubmit = !pending && accountReady && allPledged(pledges) && agentDisplayName.trim().length > 0;

  function goToLogin() {
    saveDraft({ agentDisplayName, phone });
    const next = `/join/${encodeURIComponent(token)}`;
    router.push(`/login?next=${encodeURIComponent(next)}`);
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!terms || !account?.email) return;
    setPending(true);
    setError(null);

    const response = await fetch("/api/public/agent-applications/via-link", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        token,
        agent_display_name: agentDisplayName,
        email: account.email,
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

    clearDraft();
    setMessage((body as { application_message?: string } | null)?.application_message ?? null);
    setPending(false);
  }

  if (message) {
    return (
      <div className="rounded-2xl border border-success-soft bg-success-soft px-4 py-5 text-[15px] leading-6 text-text-primary">
        {message}
      </div>
    );
  }

  if (terms === null) {
    return <p className="text-[14px] leading-6 text-text-secondary">代理店登録のお申し込みは現在準備中です。</p>;
  }
  if (isAgent) {
    return (
      <p className="text-[14px] leading-6 text-text-secondary">
        代理店としてログインしています。代理店登録のお申し込みは不要です。
      </p>
    );
  }
  if (application?.state === "received") {
    return <p className="text-[14px] leading-6 text-text-secondary">{application.message}</p>;
  }

  if (!account) {
    return (
      <div className="space-y-4">
        <p className="text-[14px] leading-6 text-text-primary">
          運営事務局からご案内した代理店登録のお申し込みフォームです。
          お申し込みには、メールアドレスを確認済みのアカウントでのログインが必要です。
        </p>
        <p className="text-[13px] leading-6 text-text-secondary">
          新しくアカウントを作った場合は、確認メールのリンクを開くとこのフォームに戻ります。
        </p>
        <PrimaryButton type="button" onClick={goToLogin}>
          ログイン / アカウント作成へ進む
        </PrimaryButton>
      </div>
    );
  }
  if (!accountReady) {
    return (
      <p className="text-[14px] leading-6 text-warning">
        メールアドレスの確認が済んでいません。確認メールのリンクを開くと、このフォームに戻ります。
      </p>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <p className="text-[13px] leading-6 text-text-secondary">
        運営が確認したうえで、代理店としてご利用いただけるようになります。
        このフォームでは会員 (購入者) の登録は行いません。
      </p>

      <div className="space-y-1">
        <span className="text-[13px] font-medium text-text-secondary">メールアドレス (ログイン中のアカウント)</span>
        <p className="rounded-2xl bg-surface-muted px-3.5 py-3 text-[15px] text-text-primary">{account.email}</p>
      </div>

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
        <span className="text-[13px] font-medium text-text-secondary">電話番号 (任意)</span>
        <input value={phone} onChange={(e) => setPhone(e.target.value)} className={INPUT} />
      </label>

      <AgentPledges terms={terms} value={pledges} onChange={setPledges} />

      {error ? <p className="text-[13px] text-danger">{error}</p> : null}

      <PrimaryButton type="submit" disabled={!canSubmit}>
        {pending ? "送信中…" : "同意して代理店登録を申し込む"}
      </PrimaryButton>
    </form>
  );
}
