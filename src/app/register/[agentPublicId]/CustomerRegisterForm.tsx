"use client";

import { useState } from "react";

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
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 outline-none focus:border-zinc-500 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100";

type Result =
  | { status: "registered"; message: null }
  | { status: "duplicate"; message: string }
  | null;

export function CustomerRegisterForm({ agentPublicId }: { agentPublicId: string }) {
  const [form, setForm] = useState({
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

  const set = (key: keyof typeof form) => (event: { target: { value: string } }) =>
    setForm((prev) => ({ ...prev, [key]: event.target.value }));

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
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
      <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-4 text-sm leading-6 text-emerald-900 dark:border-emerald-900 dark:bg-emerald-950/40 dark:text-emerald-200">
        ご登録ありがとうございました。担当代理店より追ってご連絡いたします。
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {/* 絶対原則6: 重複時は中立メッセージのみ。担当代理店が誰かは表示しない。 */}
      {result?.status === "duplicate" ? (
        <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-xs leading-6 text-amber-900 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-200">
          {result.message}
        </div>
      ) : null}

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">お名前</span>
        <input required value={form.full_name} onChange={set("full_name")} className={`mt-1 ${INPUT}`} />
      </label>

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">
          フリガナ (任意)
        </span>
        <input
          value={form.full_name_kana}
          onChange={set("full_name_kana")}
          className={`mt-1 ${INPUT}`}
        />
      </label>

      <p className="text-xs leading-5 text-zinc-500 dark:text-zinc-400">
        メールアドレスまたは電話番号のいずれかは必ずご入力ください。
      </p>

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">
          メールアドレス
        </span>
        <input type="email" value={form.email} onChange={set("email")} className={`mt-1 ${INPUT}`} />
      </label>

      <label className="block">
        <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">電話番号</span>
        <input value={form.phone} onChange={set("phone")} className={`mt-1 ${INPUT}`} />
      </label>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">年代</span>
          <select value={form.age_group} onChange={set("age_group")} className={`mt-1 ${INPUT}`}>
            <option value="">未回答</option>
            {AGE_GROUPS.filter((g) => g !== "unknown").map((g) => (
              <option key={g} value={g}>
                {AGE_GROUP_LABELS[g]}
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">性別</span>
          <select value={form.gender} onChange={set("gender")} className={`mt-1 ${INPUT}`}>
            <option value="">未回答</option>
            {GENDERS.filter((g) => g !== "prefer_not_to_say").map((g) => (
              <option key={g} value={g}>
                {GENDER_LABELS[g]}
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">都道府県</span>
          <select value={form.prefecture} onChange={set("prefecture")} className={`mt-1 ${INPUT}`}>
            <option value="">未回答</option>
            {PREFECTURES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="text-xs font-medium text-zinc-700 dark:text-zinc-300">区分</span>
          <select
            value={form.customer_type}
            onChange={set("customer_type")}
            className={`mt-1 ${INPUT}`}
          >
            {CUSTOMER_TYPES.map((t) => (
              <option key={t} value={t}>
                {CUSTOMER_TYPE_LABELS[t]}
              </option>
            ))}
          </select>
        </label>
      </div>

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
        {pending ? "送信中…" : "登録する"}
      </button>
    </form>
  );
}
