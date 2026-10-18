"use client";

import { useRouter } from "next/navigation";
import { useState, useSyncExternalStore } from "react";

import { AgentPledges, NO_PLEDGES, allPledged, type PledgeState } from "@/components/AgentPledges";
import { Chip, PrimaryButton, ProgressBar } from "@/components/mobile/primitives";
import {
  AGE_GROUPS,
  AGE_GROUP_LABELS,
  CUSTOMER_TYPES,
  CUSTOMER_TYPE_LABELS,
  GENDERS,
  GENDER_LABELS,
  PREFECTURES,
} from "@/lib/domain/enums";
import type { MyAgentApplication, RegisterMemberResult } from "@/lib/domain/types";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

type FormState = {
  full_name: string;
  full_name_kana: string;
  email: string;
  phone: string;
  age_group: string;
  gender: string;
  prefecture: string;
  customer_type: string;
};

/**
 * ログイン・メール確認のためにページを離れる間だけ、入力内容をこのブラウザに保存する。
 * 確認メールのリンクは別のタブで開かれることが多いため localStorage を使い、24 時間で破棄する。
 * 送信に成功したら消す。規約への同意は保存しない (戻ってから改めてチェックしてもらう)。
 */
type Draft = { form: FormState; agentDisplayName: string };
type StoredDraft = Draft & { savedAt: number };

const DRAFT_TTL_MS = 24 * 60 * 60 * 1000;

const STEPS = ["name", "contact", "age", "gender", "prefecture", "type"] as const;
type Step = (typeof STEPS)[number];

const EMPTY_FORM: FormState = {
  full_name: "",
  full_name_kana: "",
  email: "",
  phone: "",
  age_group: "",
  gender: "",
  prefecture: "",
  customer_type: "individual",
};

const draftKey = (agentPublicId: string) => `treemerce:register-draft:${agentPublicId}`;

function readDraftRaw(agentPublicId: string): string | null {
  try {
    return window.localStorage.getItem(draftKey(agentPublicId));
  } catch {
    return null;
  }
}

function saveDraft(agentPublicId: string, draft: Draft) {
  try {
    const stored: StoredDraft = { ...draft, savedAt: Date.now() };
    window.localStorage.setItem(draftKey(agentPublicId), JSON.stringify(stored));
  } catch {
    // 保存できなくてもログイン後に入力し直せる
  }
}

function clearDraft(agentPublicId: string) {
  try {
    window.localStorage.removeItem(draftKey(agentPublicId));
  } catch {
    // 何もしない
  }
}

function parseDraft(raw: string | null): Draft | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<StoredDraft>;
    if (!value || typeof value !== "object" || !value.form) return null;
    // 古い下書きは使わない (共用の端末に入力内容を長く残さないため)
    if (typeof value.savedAt !== "number" || Date.now() - value.savedAt > DRAFT_TTL_MS) return null;
    const form = { ...EMPTY_FORM };
    for (const key of Object.keys(EMPTY_FORM) as (keyof FormState)[]) {
      const v = (value.form as Record<string, unknown>)[key];
      if (typeof v === "string") form[key] = v;
    }
    return { form, agentDisplayName: typeof value.agentDisplayName === "string" ? value.agentDisplayName : "" };
  } catch {
    return null;
  }
}

const noopSubscribe = () => () => {};

type Props = {
  agentPublicId: string;
  /** 現行の代理店規約。未登録 (準備中) なら null */
  terms: { version: string; title: string } | null;
  /** ログイン中のアカウント。未ログインなら null */
  account: { email: string | null; confirmed: boolean } | null;
  /** 本人の申請状況 (中立的な文面のみ)。未ログインなら null */
  application: MyAgentApplication | null;
  isAgent: boolean;
  /** ログインから戻ってきたとき (?apply=1) は保存した入力内容で再開する */
  resumeApply: boolean;
};

/**
 * 紹介リンクの登録フォーム。サーバー描画では保存した入力内容を読めないため、
 * ブラウザで読めた時点で key を変えて入力内容を復元した状態で描き直す。
 */
export function CustomerRegisterForm(props: Props) {
  const draftRaw = useSyncExternalStore(
    noopSubscribe,
    () => (props.resumeApply ? readDraftRaw(props.agentPublicId) : null),
    () => null,
  );
  const draft = parseDraft(draftRaw);
  return <RegisterFormInner key={draft ? "resume" : "fresh"} {...props} draft={draft} />;
}

function StepShell({
  step,
  title,
  description,
  children,
  canNext,
  onBack,
  onNext,
  nextLabel = "次へ",
}: {
  step: number;
  title: string;
  description?: string;
  children: React.ReactNode;
  canNext: boolean;
  onBack?: () => void;
  onNext: () => void;
  nextLabel?: string;
}) {
  return (
    <div className="space-y-6">
      <ProgressBar step={step + 1} total={STEPS.length} />
      <div>
        <h2 className="text-[22px] font-bold text-text-primary">{title}</h2>
        {description ? (
          <p className="mt-1.5 text-[14px] leading-6 text-text-secondary">{description}</p>
        ) : null}
      </div>
      <div>{children}</div>
      <div className="flex gap-2">
        {onBack ? (
          <PrimaryButton type="button" variant="secondary" onClick={onBack}>
            戻る
          </PrimaryButton>
        ) : null}
        <PrimaryButton type="button" onClick={onNext} disabled={!canNext}>
          {nextLabel}
        </PrimaryButton>
      </div>
    </div>
  );
}

function RegisterFormInner({
  agentPublicId,
  terms,
  account,
  application,
  isAgent,
  draft,
}: Props & { draft: Draft | null }) {
  const router = useRouter();
  const [stepIndex, setStepIndex] = useState(draft ? STEPS.length - 1 : 0);
  const [form, setForm] = useState<FormState>(draft?.form ?? EMPTY_FORM);
  // ログインから戻ってきた場合は「申し込む」を選んだ状態で再開する。規約への同意は改めてチェックしてもらう
  const [applyAgent, setApplyAgent] = useState(Boolean(draft));
  const [pledges, setPledges] = useState<PledgeState>(NO_PLEDGES);
  const acceptTerms = allPledged(pledges);
  const [agentDisplayName, setAgentDisplayName] = useState(draft?.agentDisplayName ?? "");
  const [result, setResult] = useState<RegisterMemberResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const set = <K extends keyof FormState>(key: K, value: FormState[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  const step: Step = STEPS[stepIndex];

  // 申し込めるのは、規約があり、まだ代理店でも承認待ちでもないとき
  const canOfferApplication = terms !== null && !isAgent && application?.state !== "received";
  const applying = canOfferApplication && applyAgent;
  const accountReady = Boolean(account?.email && account.confirmed);
  const emailMatches =
    Boolean(account?.email) && form.email.trim().toLowerCase() === account?.email?.trim().toLowerCase();
  const canSubmit =
    !pending &&
    (!applying || (accountReady && emailMatches && acceptTerms && agentDisplayName.trim().length > 0));

  function goToLogin() {
    saveDraft(agentPublicId, { form, agentDisplayName });
    const next = `/register/${encodeURIComponent(agentPublicId)}?apply=1`;
    router.push(`/login?next=${encodeURIComponent(next)}`);
  }

  async function handleSubmit() {
    setPending(true);
    setError(null);
    setResult(null);

    const response = await fetch("/api/public/members/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        agent_public_id: agentPublicId,
        full_name: form.full_name,
        full_name_kana: form.full_name_kana || null,
        email: form.email || null,
        phone: form.phone || null,
        age_group: form.age_group || null,
        gender: form.gender || null,
        prefecture: form.prefecture || null,
        customer_type: form.customer_type,
        apply_agent: applying,
        accept_agent_terms: applying && acceptTerms,
        agent_terms_version: applying ? terms?.version : null,
        agent_display_name: applying ? agentDisplayName : null,
      }),
    });

    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "登録に失敗しました。");
      setPending(false);
      return;
    }

    clearDraft(agentPublicId);
    setResult(body as RegisterMemberResult);
    setPending(false);
  }

  // 完了: 会員登録できた場合、または代理店のお申し込みを受け付けた場合
  if (result && (result.member_status === "registered" || result.application_status)) {
    return (
      <div className="space-y-3">
        <div className="rounded-2xl border border-success-soft bg-success-soft px-4 py-5 text-[15px] leading-6 text-text-primary">
          {result.member_status === "registered"
            ? "ご登録ありがとうございました。担当窓口より追ってご連絡いたします。"
            : result.member_message}
        </div>
        {result.application_message ? (
          <div className="rounded-2xl border border-brand/30 bg-brand-soft px-4 py-4 text-[14px] leading-6 text-text-primary">
            {result.application_message}
          </div>
        ) : null}
      </div>
    );
  }

  const goNext = () => setStepIndex((i) => Math.min(STEPS.length - 1, i + 1));
  const goBack = () => setStepIndex((i) => Math.max(0, i - 1));

  if (step === "name") {
    return (
      <StepShell
        step={stepIndex}
        title="お名前を教えてください"
        canNext={form.full_name.trim().length > 0}
        onNext={goNext}
      >
        <div className="space-y-3">
          <label className="block space-y-1">
            <span className="text-[13px] font-medium text-text-secondary">お名前</span>
            <input
              autoFocus
              required
              value={form.full_name}
              onChange={(e) => set("full_name", e.target.value)}
              className={INPUT}
            />
          </label>
          <label className="block space-y-1">
            <span className="text-[13px] font-medium text-text-secondary">フリガナ (任意)</span>
            <input
              value={form.full_name_kana}
              onChange={(e) => set("full_name_kana", e.target.value)}
              className={INPUT}
            />
          </label>
        </div>
      </StepShell>
    );
  }

  if (step === "contact") {
    return (
      <StepShell
        step={stepIndex}
        title="連絡先を教えてください"
        description="メールアドレスまたは電話番号のいずれかは必ずご入力ください。"
        canNext={form.email.trim().length > 0 || form.phone.trim().length > 0}
        onBack={goBack}
        onNext={goNext}
      >
        <div className="space-y-3">
          <label className="block space-y-1">
            <span className="text-[13px] font-medium text-text-secondary">メールアドレス</span>
            <input
              type="email"
              value={form.email}
              onChange={(e) => set("email", e.target.value)}
              className={INPUT}
            />
          </label>
          <label className="block space-y-1">
            <span className="text-[13px] font-medium text-text-secondary">電話番号</span>
            <input value={form.phone} onChange={(e) => set("phone", e.target.value)} className={INPUT} />
          </label>
        </div>
      </StepShell>
    );
  }

  if (step === "age") {
    return (
      <StepShell step={stepIndex} title="年代を選んでください" canNext onBack={goBack} onNext={goNext}>
        <div className="flex flex-wrap gap-2">
          {AGE_GROUPS.filter((g) => g !== "unknown").map((g) => (
            <Chip key={g} selected={form.age_group === g} onClick={() => set("age_group", g)}>
              {AGE_GROUP_LABELS[g]}
            </Chip>
          ))}
        </div>
      </StepShell>
    );
  }

  if (step === "gender") {
    return (
      <StepShell step={stepIndex} title="性別を選んでください" canNext onBack={goBack} onNext={goNext}>
        <div className="flex flex-wrap gap-2">
          {GENDERS.filter((g) => g !== "prefer_not_to_say").map((g) => (
            <Chip key={g} selected={form.gender === g} onClick={() => set("gender", g)}>
              {GENDER_LABELS[g]}
            </Chip>
          ))}
        </div>
      </StepShell>
    );
  }

  if (step === "prefecture") {
    return (
      <StepShell
        step={stepIndex}
        title="お住まいの都道府県は？"
        canNext
        onBack={goBack}
        onNext={goNext}
      >
        <select
          value={form.prefecture}
          onChange={(e) => set("prefecture", e.target.value)}
          className={INPUT}
        >
          <option value="">未回答</option>
          {PREFECTURES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </StepShell>
    );
  }

  // step === "type" (最後のステップ: 区分 + 代理店登録のお申し込み)
  return (
    <StepShell
      step={stepIndex}
      title="区分を選んでください"
      canNext={canSubmit}
      onBack={goBack}
      onNext={handleSubmit}
      nextLabel={pending ? "送信中…" : applying ? "同意して代理店登録を申し込む" : "登録する"}
    >
      <div className="space-y-5">
        <div className="flex flex-wrap gap-2">
          {CUSTOMER_TYPES.map((t) => (
            <Chip key={t} selected={form.customer_type === t} onClick={() => set("customer_type", t)}>
              {CUSTOMER_TYPE_LABELS[t]}
            </Chip>
          ))}
        </div>

        <section className="space-y-3 rounded-2xl border border-border-soft px-4 py-4">
          <h3 className="text-[15px] font-semibold text-text-primary">代理店登録</h3>

          {terms === null ? (
            <p className="text-[13px] leading-6 text-text-secondary">
              代理店登録のお申し込みは現在準備中です。
            </p>
          ) : isAgent ? (
            <p className="text-[13px] leading-6 text-text-secondary">
              代理店としてログインしています。代理店登録のお申し込みは不要です。
            </p>
          ) : application?.state === "received" ? (
            <p className="text-[13px] leading-6 text-text-secondary">{application.message}</p>
          ) : (
            <>
              <label className="flex cursor-pointer items-start gap-3">
                <input
                  type="checkbox"
                  checked={applyAgent}
                  onChange={(e) => setApplyAgent(e.target.checked)}
                  className="mt-1 h-4 w-4 accent-[var(--brand)]"
                />
                <span className="text-[14px] leading-6 text-text-primary">
                  代理店登録も申し込みますか？
                  <span className="block text-[12px] text-text-secondary">
                    運営が確認したうえで、代理店としてご利用いただけるようになります。
                  </span>
                </span>
              </label>

              {applyAgent ? (
                !account ? (
                  <div className="space-y-3">
                    <p className="text-[13px] leading-6 text-text-secondary">
                      代理店登録のお申し込みには、メールアドレスを確認済みのアカウントでのログインが必要です。
                      新しくアカウントを作った場合は、確認メールのリンクを開くとこの登録フォームに戻ります。
                      入力した内容は、このブラウザで 24 時間以内に戻ったときに引き継がれます。
                    </p>
                    <PrimaryButton type="button" variant="secondary" onClick={goToLogin}>
                      ログイン / アカウント作成へ進む
                    </PrimaryButton>
                  </div>
                ) : !accountReady ? (
                  <p className="text-[13px] leading-6 text-warning">
                    メールアドレスの確認が済んでいません。確認メールのリンクを開くと、この登録フォームに戻ります。
                  </p>
                ) : (
                  <div className="space-y-3">
                    {!emailMatches ? (
                      <div className="space-y-2 rounded-xl border border-warning-soft bg-warning-soft px-3 py-2.5 text-[13px] leading-5 text-text-primary">
                        <p>
                          お申し込みには、連絡先のメールアドレスをログイン中のアカウント ({account.email})
                          と同じにしてください。
                        </p>
                        <button
                          type="button"
                          onClick={() => set("email", account.email ?? "")}
                          className="font-semibold text-brand underline"
                        >
                          このメールアドレスにする
                        </button>
                      </div>
                    ) : null}

                    <label className="block space-y-1">
                      <span className="text-[13px] font-medium text-text-secondary">代理店名</span>
                      <input
                        value={agentDisplayName}
                        onChange={(e) => setAgentDisplayName(e.target.value)}
                        maxLength={100}
                        className={INPUT}
                      />
                    </label>

                    <AgentPledges terms={terms} value={pledges} onChange={setPledges} />
                  </div>
                )
              ) : null}
            </>
          )}
        </section>

        {result?.member_status === "duplicate" && result.member_message ? (
          <div className="rounded-2xl border border-warning-soft bg-warning-soft px-4 py-3 text-[13px] leading-6 text-text-primary">
            {result.member_message}
          </div>
        ) : null}
        {error ? <p className="text-[13px] text-danger">{error}</p> : null}
      </div>
    </StepShell>
  );
}
