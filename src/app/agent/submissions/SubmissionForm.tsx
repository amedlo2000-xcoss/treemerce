"use client";

import { Lock } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { PrimaryButton } from "@/components/mobile/primitives";
import { SUBMISSION_LIMITS } from "@/lib/api/submission-input";
import { PREFECTURES, PRODUCT_CATEGORIES, PRODUCT_CATEGORY_LABELS } from "@/lib/domain/enums";
import type { SubmissionContent } from "@/lib/domain/types";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-2.5 text-[15px] text-text-primary outline-none focus:border-brand";

type FormState = {
  name: string;
  category: string;
  description: string;
  desired_price: string;
  expected_wholesale_price: string;
  content_volume: string;
  ingredients: string;
  best_before_note: string;
  producer_name: string;
  producer_origin: string;
  producer_ship_from_prefecture: string;
  producer_ship_lead_time: string;
  producer_contact_name: string;
  producer_contact_phone: string;
  producer_contact_email: string;
};

function initialState(s?: SubmissionContent): FormState {
  return {
    name: s?.name ?? "",
    category: s?.category ?? "food",
    description: s?.description ?? "",
    desired_price: s?.desired_price != null ? String(Number(s.desired_price)) : "",
    expected_wholesale_price: s?.expected_wholesale_price != null ? String(Number(s.expected_wholesale_price)) : "",
    content_volume: s?.content_volume ?? "",
    ingredients: s?.ingredients ?? "",
    best_before_note: s?.best_before_note ?? "",
    producer_name: s?.producer_name ?? "",
    producer_origin: s?.producer_origin ?? "",
    producer_ship_from_prefecture: s?.producer_ship_from_prefecture ?? "",
    producer_ship_lead_time: s?.producer_ship_lead_time ?? "",
    producer_contact_name: s?.producer_contact_name ?? "",
    producer_contact_phone: s?.producer_contact_phone ?? "",
    producer_contact_email: s?.producer_contact_email ?? "",
  };
}

function Label({ text, required, hint }: { text: string; required?: boolean; hint?: string }) {
  return (
    <span className="block text-[13px] font-medium text-text-secondary">
      {text}
      {required ? <span className="ml-1 text-[11px] font-semibold text-danger">申請時に必須</span> : null}
      {hint ? <span className="ml-1 text-[12px] font-normal">{hint}</span> : null}
    </span>
  );
}

/**
 * 持込み申請の入力フォーム (本人の下書き・差し戻しのみ)。
 *   新規     : 「下書き保存」→ 詳細ページへ (画像は下書き保存後に追加)
 *   既存     : 「下書き保存」/「保存して申請する」(保存してから申請 RPC を呼ぶ)
 * 必須項目は申請時に DB 側で確認する。入力値は API と DB でも再検証される。
 */
export function SubmissionForm({ submission }: { submission?: SubmissionContent }) {
  const router = useRouter();
  const [form, setForm] = useState<FormState>(() => initialState(submission));
  const [pending, setPending] = useState<"save" | "submit" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const set = <K extends keyof FormState>(key: K, value: FormState[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  async function save(): Promise<{ id: string } | null> {
    const response = await fetch(
      submission ? `/api/agent/submissions/${submission.id}` : "/api/agent/submissions",
      {
        method: submission ? "PUT" : "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(form),
      },
    );
    const body = await response.json().catch(() => null);
    if (!response.ok) {
      setError(body?.error?.message ?? "保存に失敗しました。");
      return null;
    }
    return body as { id: string };
  }

  async function handleSave(event: React.FormEvent) {
    event.preventDefault();
    setPending("save");
    setError(null);
    setDone(null);
    const saved = await save();
    setPending(null);
    if (!saved) return;
    if (!submission) {
      router.push(`/agent/submissions/${saved.id}?created=1`);
      return;
    }
    setDone("下書きを保存しました。");
    router.refresh();
  }

  async function handleSubmit() {
    if (!submission) return;
    if (!window.confirm("この内容で申請します。申請中は内容を編集できません。よろしいですか？")) return;
    setPending("submit");
    setError(null);
    setDone(null);
    const saved = await save();
    if (!saved) {
      setPending(null);
      return;
    }
    const response = await fetch(`/api/agent/submissions/${submission.id}/submit`, { method: "POST" });
    const body = await response.json().catch(() => null);
    setPending(null);
    if (!response.ok) {
      setError(body?.error?.message ?? "申請に失敗しました。");
      router.refresh();
      return;
    }
    router.push(`/agent/submissions/${submission.id}?submitted=1`);
    router.refresh();
  }

  const text = (key: keyof FormState, label: string, opts: { required?: boolean; placeholder?: string; hint?: string } = {}) => (
    <label className="block space-y-1.5">
      <Label text={label} required={opts.required} hint={opts.hint} />
      <input
        value={form[key]}
        onChange={(e) => set(key, e.target.value)}
        maxLength={SUBMISSION_LIMITS[key as keyof typeof SUBMISSION_LIMITS]}
        className={INPUT}
        placeholder={opts.placeholder}
      />
    </label>
  );

  return (
    <form onSubmit={handleSave} className="space-y-6">
      <fieldset className="space-y-4">
        <legend className="mb-1 text-[15px] font-semibold text-text-primary">商品</legend>
        <label className="block space-y-1.5">
          <Label text="商品名" hint="(下書きでも必須)" />
          <input
            required
            value={form.name}
            onChange={(e) => set("name", e.target.value)}
            maxLength={SUBMISSION_LIMITS.name}
            className={INPUT}
          />
        </label>
        <label className="block space-y-1.5">
          <Label text="カテゴリ" />
          <select value={form.category} onChange={(e) => set("category", e.target.value)} className={INPUT}>
            {PRODUCT_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {PRODUCT_CATEGORY_LABELS[c]}
              </option>
            ))}
          </select>
        </label>
        <label className="block space-y-1.5">
          <Label text="説明" required />
          <textarea
            rows={5}
            value={form.description}
            onChange={(e) => set("description", e.target.value)}
            maxLength={SUBMISSION_LIMITS.description}
            className={INPUT}
            placeholder="特徴・おすすめの食べ方・こだわりなど"
          />
        </label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block space-y-1.5">
            <Label text="希望販売価格 (円・税込)" required />
            <input
              type="number"
              min={0}
              step={1}
              inputMode="numeric"
              value={form.desired_price}
              onChange={(e) => set("desired_price", e.target.value)}
              className={INPUT}
            />
          </label>
          <label className="block space-y-1.5">
            <Label text="想定卸値 (円)" hint="(任意)" />
            <input
              type="number"
              min={0}
              step={1}
              inputMode="numeric"
              value={form.expected_wholesale_price}
              onChange={(e) => set("expected_wholesale_price", e.target.value)}
              className={INPUT}
            />
          </label>
        </div>
        {text("content_volume", "内容量", { required: true, placeholder: "例: 100g×2袋" })}
        <label className="block space-y-1.5">
          <Label text="原材料" hint="(任意)" />
          <textarea
            rows={3}
            value={form.ingredients}
            onChange={(e) => set("ingredients", e.target.value)}
            maxLength={SUBMISSION_LIMITS.ingredients}
            className={INPUT}
          />
        </label>
        {text("best_before_note", "期限の目安", { hint: "(任意)", placeholder: "例: 製造から12か月" })}
      </fieldset>

      <fieldset className="space-y-4">
        <legend className="mb-1 text-[15px] font-semibold text-text-primary">生産者</legend>
        {text("producer_name", "生産者名", { required: true })}
        {text("producer_origin", "産地", { required: true, placeholder: "例: 静岡県 牧之原市" })}
        <label className="block space-y-1.5">
          <Label text="発送元 (都道府県)" required />
          <select
            value={form.producer_ship_from_prefecture}
            onChange={(e) => set("producer_ship_from_prefecture", e.target.value)}
            className={INPUT}
          >
            <option value="">選択してください</option>
            {PREFECTURES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
        </label>
        {text("producer_ship_lead_time", "発送目安", { required: true, placeholder: "例: 入金確認後3営業日以内" })}
      </fieldset>

      <fieldset className="space-y-4">
        <legend className="mb-1 text-[15px] font-semibold text-text-primary">生産者の連絡先</legend>
        <div className="flex items-start gap-2.5 rounded-2xl bg-surface-muted px-3 py-2.5">
          <Lock size={14} className="mt-0.5 shrink-0 text-text-secondary" />
          <p className="text-[12px] leading-5 text-text-secondary">
            連絡先は、あなたと運営 (super_admin) だけが見られます。ほかの代理店や商品ページには表示されません。
            電話番号かメールのどちらかが申請時に必須です。
          </p>
        </div>
        {text("producer_contact_name", "担当者名", { hint: "(任意)" })}
        <label className="block space-y-1.5">
          <Label text="電話番号" />
          <input
            type="tel"
            value={form.producer_contact_phone}
            onChange={(e) => set("producer_contact_phone", e.target.value)}
            maxLength={SUBMISSION_LIMITS.producer_contact_phone}
            className={INPUT}
          />
        </label>
        <label className="block space-y-1.5">
          <Label text="メール" />
          <input
            type="email"
            value={form.producer_contact_email}
            onChange={(e) => set("producer_contact_email", e.target.value)}
            className={INPUT}
          />
        </label>
      </fieldset>

      {error ? <p role="alert" className="rounded-2xl bg-danger-soft px-3.5 py-2.5 text-[13px] text-danger">{error}</p> : null}
      {done ? <p role="status" className="rounded-2xl bg-success-soft px-3.5 py-2.5 text-[13px] text-success">{done}</p> : null}

      <div className="space-y-2">
        <PrimaryButton type="submit" variant={submission ? "secondary" : "primary"} disabled={pending !== null}>
          {pending === "save" ? "保存中…" : "下書き保存"}
        </PrimaryButton>
        {submission ? (
          <PrimaryButton onClick={handleSubmit} disabled={pending !== null}>
            {pending === "submit" ? "申請中…" : "保存して申請する"}
          </PrimaryButton>
        ) : (
          <p className="text-center text-[12px] text-text-secondary">画像は下書き保存のあとに追加できます。</p>
        )}
      </div>
    </form>
  );
}
