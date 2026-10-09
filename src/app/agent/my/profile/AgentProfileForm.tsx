"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { Chip, PrimaryButton } from "@/components/mobile/primitives";
import { AGENT_INDUSTRIES, AGENT_INDUSTRY_LABELS, PREFECTURES } from "@/lib/domain/enums";
import type { AgentProfile } from "@/lib/domain/types";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-2.5 text-[15px] text-text-primary outline-none focus:border-brand";

const MAX_SNS = 5;

function Label({ text, hint, count }: { text: string; hint?: string; count?: [number, number] }) {
  return (
    <span className="flex items-baseline justify-between gap-2">
      <span className="text-[13px] font-medium text-text-secondary">
        {text}
        {hint ? <span className="ml-1 text-[12px] font-normal">{hint}</span> : null}
      </span>
      {count ? (
        <span
          className={`text-[12px] tabular-nums ${count[0] > count[1] ? "text-danger" : "text-text-secondary"}`}
        >
          {count[0]} / {count[1]}
        </span>
      ) : null}
    </span>
  );
}

/**
 * 事業プロフィールの編集フォーム (本人のみ)。保存は /api/agent/profile 経由で
 * treemerce_update_my_agent_profile を呼ぶ。入力値の検証は API と DB でも再度行う。
 */
export function AgentProfileForm({ profile }: { profile: AgentProfile }) {
  const router = useRouter();
  const [form, setForm] = useState({
    industry: profile.industry ?? "",
    business_description: profile.business_description ?? "",
    offerings: profile.offerings ?? "",
    target_customers: profile.target_customers ?? "",
    activity_prefectures: profile.activity_prefectures,
    website_url: profile.website_url ?? "",
    self_introduction: profile.self_introduction ?? "",
  });
  const [sns, setSns] = useState<string[]>(profile.sns_urls.length > 0 ? profile.sns_urls : [""]);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  function togglePrefecture(pref: string) {
    set(
      "activity_prefectures",
      form.activity_prefectures.includes(pref)
        ? form.activity_prefectures.filter((p) => p !== pref)
        : PREFECTURES.filter((p) => p === pref || form.activity_prefectures.includes(p)),
    );
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);

    const response = await fetch("/api/agent/profile", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...form, industry: form.industry || null, sns_urls: sns }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "保存に失敗しました。");
      return;
    }
    router.push("/agent/my?profile=saved");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <div className="space-y-1.5">
        <Label text="業種" />
        <select value={form.industry} onChange={(e) => set("industry", e.target.value)} className={INPUT}>
          <option value="">選択してください</option>
          {AGENT_INDUSTRIES.map((i) => (
            <option key={i} value={i}>
              {AGENT_INDUSTRY_LABELS[i]}
            </option>
          ))}
        </select>
      </div>

      <label className="block space-y-1.5">
        <Label text="事業内容" count={[form.business_description.trim().length, 2000]} />
        <textarea
          rows={4}
          value={form.business_description}
          onChange={(e) => set("business_description", e.target.value)}
          className={INPUT}
          placeholder="例: 静岡で茶葉の生産と、地元の農産物の直売所を運営しています。"
        />
      </label>

      <label className="block space-y-1.5">
        <Label text="取扱商品・サービス" hint="(売りたい物)" count={[form.offerings.trim().length, 2000]} />
        <textarea
          rows={4}
          value={form.offerings}
          onChange={(e) => set("offerings", e.target.value)}
          className={INPUT}
          placeholder="例: 深蒸し煎茶、季節の野菜セット、手作りジャム"
        />
      </label>

      <label className="block space-y-1.5">
        <Label text="得意な客層・地域" count={[form.target_customers.trim().length, 1000]} />
        <textarea
          rows={3}
          value={form.target_customers}
          onChange={(e) => set("target_customers", e.target.value)}
          className={INPUT}
          placeholder="例: 40〜60代の健康志向の方、首都圏の飲食店"
        />
      </label>

      <div className="space-y-1.5">
        <Label text="活動エリア" hint={`(${form.activity_prefectures.length} 件選択中)`} />
        <p className="text-[14px] text-text-primary">
          {form.activity_prefectures.length > 0 ? form.activity_prefectures.join("、") : "未選択"}
        </p>
        <details className="rounded-2xl border border-border-soft px-3.5 py-2.5">
          <summary className="cursor-pointer text-[14px] font-medium text-brand">都道府県を選ぶ</summary>
          <div className="mt-3 flex flex-wrap gap-1.5">
            {PREFECTURES.map((pref) => (
              <Chip
                key={pref}
                type="button"
                selected={form.activity_prefectures.includes(pref)}
                onClick={() => togglePrefecture(pref)}
              >
                {pref}
              </Chip>
            ))}
          </div>
        </details>
      </div>

      <label className="block space-y-1.5">
        <Label text="Web サイト" hint="(http:// または https:// で始まる URL)" />
        <input
          type="url"
          inputMode="url"
          value={form.website_url}
          onChange={(e) => set("website_url", e.target.value)}
          className={INPUT}
          placeholder="https://"
        />
      </label>

      <div className="space-y-1.5">
        <Label text="SNS" hint={`(${MAX_SNS} 件まで)`} />
        <div className="space-y-2">
          {sns.map((url, index) => (
            <div key={index} className="flex gap-2">
              <input
                type="url"
                inputMode="url"
                value={url}
                onChange={(e) => setSns((prev) => prev.map((u, i) => (i === index ? e.target.value : u)))}
                className={INPUT}
                placeholder="https://"
                aria-label={`SNS の URL ${index + 1}`}
              />
              <button
                type="button"
                onClick={() => setSns((prev) => (prev.length > 1 ? prev.filter((_, i) => i !== index) : [""]))}
                className="shrink-0 rounded-2xl border border-border-soft px-3 text-[13px] text-text-secondary hover:bg-surface-muted"
              >
                削除
              </button>
            </div>
          ))}
        </div>
        {sns.length < MAX_SNS ? (
          <button
            type="button"
            onClick={() => setSns((prev) => [...prev, ""])}
            className="text-[13px] font-medium text-brand hover:underline"
          >
            + SNS を追加
          </button>
        ) : null}
      </div>

      <label className="block space-y-1.5">
        <Label text="自己紹介" count={[form.self_introduction.trim().length, 2000]} />
        <textarea
          rows={5}
          value={form.self_introduction}
          onChange={(e) => set("self_introduction", e.target.value)}
          className={INPUT}
        />
      </label>

      {error ? <p role="alert" className="text-[13px] text-danger">{error}</p> : null}

      <div className="flex gap-2">
        <PrimaryButton type="submit" disabled={pending}>
          {pending ? "保存中…" : "保存する"}
        </PrimaryButton>
        <PrimaryButton type="button" variant="secondary" onClick={() => router.push("/agent/my")}>
          キャンセル
        </PrimaryButton>
      </div>
    </form>
  );
}
