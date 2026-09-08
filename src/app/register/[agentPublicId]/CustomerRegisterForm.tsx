"use client";

import { useState } from "react";

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

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

type Result =
  | { status: "registered"; message: null }
  | { status: "duplicate"; message: string }
  | null;

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

const STEPS = ["name", "contact", "age", "gender", "prefecture", "type"] as const;
type Step = (typeof STEPS)[number];

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

export function CustomerRegisterForm({ agentPublicId }: { agentPublicId: string }) {
  const [stepIndex, setStepIndex] = useState(0);
  const [form, setForm] = useState<FormState>({
    full_name: "",
    full_name_kana: "",
    email: "",
    phone: "",
    age_group: "",
    gender: "",
    prefecture: "",
    customer_type: "individual",
  });
  const [result, setResult] = useState<Result>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const set = <K extends keyof FormState>(key: K, value: FormState[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  const step: Step = STEPS[stepIndex];

  async function handleSubmit() {
    setPending(true);
    setError(null);
    setResult(null);

    const response = await fetch("/api/public/customers/register", {
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
      }),
    });

    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "登録に失敗しました。");
      setPending(false);
      return;
    }

    setResult(body as Result);
    setPending(false);
  }

  if (result?.status === "registered") {
    return (
      <div className="rounded-2xl border border-success-soft bg-success-soft px-4 py-5 text-[15px] leading-6 text-text-primary">
        ご登録ありがとうございました。担当窓口より追ってご連絡いたします。
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

  // step === "type"
  return (
    <StepShell
      step={stepIndex}
      title="区分を選んでください"
      canNext={!pending}
      onBack={goBack}
      onNext={handleSubmit}
      nextLabel={pending ? "送信中…" : "登録する"}
    >
      <div className="space-y-4">
        <div className="flex flex-wrap gap-2">
          {CUSTOMER_TYPES.map((t) => (
            <Chip key={t} selected={form.customer_type === t} onClick={() => set("customer_type", t)}>
              {CUSTOMER_TYPE_LABELS[t]}
            </Chip>
          ))}
        </div>

        {result?.status === "duplicate" ? (
          <div className="rounded-2xl border border-warning-soft bg-warning-soft px-4 py-3 text-[13px] leading-6 text-text-primary">
            {result.message}
          </div>
        ) : null}
        {error ? <p className="text-[13px] text-danger">{error}</p> : null}
      </div>
    </StepShell>
  );
}
