"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";

import {
  AGE_GROUP_LABELS,
  AGE_GROUPS,
  CUSTOMER_TYPE_LABELS,
  CUSTOMER_TYPES,
  GENDER_LABELS,
  GENDERS,
  PREFECTURES,
} from "@/lib/domain/enums";
import type { CustomerRow } from "@/lib/domain/types";

export function CustomerEditForm({ customer }: { customer: CustomerRow }) {
  const router = useRouter();
  const [form, setForm] = useState({
    full_name: customer.full_name,
    full_name_kana: customer.full_name_kana ?? "",
    email: customer.email ?? "",
    phone: customer.phone ?? "",
    postal_code: customer.postal_code ?? "",
    address_line: customer.address_line ?? "",
    prefecture: customer.prefecture ?? "",
    age_group: customer.age_group ?? "",
    gender: customer.gender ?? "",
    customer_type: customer.customer_type,
    note: customer.note ?? "",
  });
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  function set<K extends keyof typeof form>(key: K, value: (typeof form)[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setDone(null);

    const response = await fetch(`/api/admin/customers/${customer.id}`, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ patch: form, reason }),
    });

    const body = await response.json().catch(() => null);

    if (!response.ok) {
      setError(body?.error?.message ?? "更新に失敗しました。");
      setPending(false);
      return;
    }

    setDone("購入者情報を更新しました。監査ログに記録されています。");
    setReason("");
    setPending(false);
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="氏名">
          <input
            required
            value={form.full_name}
            onChange={(e) => set("full_name", e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <Field label="フリガナ">
          <input
            value={form.full_name_kana}
            onChange={(e) => set("full_name_kana", e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <Field label="メール">
          <input
            type="email"
            value={form.email}
            onChange={(e) => set("email", e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <Field label="電話番号">
          <input
            value={form.phone}
            onChange={(e) => set("phone", e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <Field label="郵便番号">
          <input
            value={form.postal_code}
            onChange={(e) => set("postal_code", e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <Field label="都道府県">
          <select
            value={form.prefecture}
            onChange={(e) => set("prefecture", e.target.value)}
            className={FIELD_CLASS}
          >
            <option value="">未回答</option>
            {PREFECTURES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
        </Field>
        <Field label="住所" className="sm:col-span-2">
          <input
            value={form.address_line}
            onChange={(e) => set("address_line", e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
        <Field label="年代">
          <select
            value={form.age_group}
            onChange={(e) => set("age_group", e.target.value)}
            className={FIELD_CLASS}
          >
            <option value="">未回答</option>
            {AGE_GROUPS.map((g) => (
              <option key={g} value={g}>
                {AGE_GROUP_LABELS[g]}
              </option>
            ))}
          </select>
        </Field>
        <Field label="性別">
          <select
            value={form.gender}
            onChange={(e) => set("gender", e.target.value)}
            className={FIELD_CLASS}
          >
            <option value="">未回答</option>
            {GENDERS.map((g) => (
              <option key={g} value={g}>
                {GENDER_LABELS[g]}
              </option>
            ))}
          </select>
        </Field>
        <Field label="顧客タイプ">
          <select
            value={form.customer_type}
            onChange={(e) =>
              set("customer_type", e.target.value as (typeof CUSTOMER_TYPES)[number])
            }
            className={FIELD_CLASS}
          >
            {CUSTOMER_TYPES.map((t) => (
              <option key={t} value={t}>
                {CUSTOMER_TYPE_LABELS[t]}
              </option>
            ))}
          </select>
        </Field>
        <Field label="備考" className="sm:col-span-2">
          <textarea
            rows={3}
            value={form.note}
            onChange={(e) => set("note", e.target.value)}
            className={FIELD_CLASS}
          />
        </Field>
      </div>

      <Field label="変更理由 (必須・監査ログに記録されます)">
        <textarea
          required
          rows={2}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className={FIELD_CLASS}
        />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {done ? <FormMessage tone="success">{done}</FormMessage> : null}

      <button type="submit" disabled={pending} className={BUTTON_CLASS}>
        {pending ? "更新中…" : "更新する"}
      </button>
    </form>
  );
}
