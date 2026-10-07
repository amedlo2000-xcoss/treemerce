"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";
import { PREFECTURES } from "@/lib/domain/enums";
import type { ProducerAdminRow } from "@/lib/domain/types";

/**
 * 生産者の登録・編集フォーム (super_admin 専用ページから使う)。
 * 公開項目 (商品ページに表示) と非公開項目 (super_admin のみ) を分けて表示する。
 */
export function ProducerForm({ producer }: { producer?: ProducerAdminRow }) {
  const router = useRouter();
  const [form, setForm] = useState({
    name: producer?.name ?? "",
    origin: producer?.origin ?? "",
    ship_from_prefecture: producer?.ship_from_prefecture ?? "",
    ship_lead_time: producer?.ship_lead_time ?? "入金確認後3営業日以内",
    notify_email: producer?.notify_email ?? "",
    contact_name: producer?.contact_name ?? "",
    contact_phone: producer?.contact_phone ?? "",
    contact_email: producer?.contact_email ?? "",
    note: producer?.note ?? "",
    is_active: producer?.is_active ?? true,
  });
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  const deactivating = producer?.is_active && !form.is_active;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setDone(null);

    const response = await fetch(producer ? `/api/admin/producers/${producer.id}` : "/api/admin/producers", {
      method: producer ? "PATCH" : "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...form, reason: reason || null }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "保存に失敗しました。");
      return;
    }

    if (!producer) {
      router.push(`/admin/producers/${body.id}?created=1`);
      return;
    }
    const open = Number(body?.open_shipments ?? 0);
    setDone(
      !body?.is_active && open > 0
        ? `保存しました。この生産者には未発送の発送記録が ${open} 件残っています。発送の手配を続けてください。`
        : "保存しました。変更内容は監査ログに記録されています (連絡先の値は記録されません)。",
    );
    setReason("");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <fieldset className="space-y-4">
        <legend className="mb-1 text-[14px] font-semibold text-text-primary">
          公開項目 <span className="text-[12px] font-normal text-text-secondary">(商品ページに表示されます)</span>
        </legend>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="生産者名" className="sm:col-span-2">
            <input required value={form.name} onChange={(e) => set("name", e.target.value)} className={FIELD_CLASS} />
          </Field>
          <Field label="産地">
            <input
              required
              value={form.origin}
              onChange={(e) => set("origin", e.target.value)}
              className={FIELD_CLASS}
              placeholder="例: 静岡県 牧之原市"
            />
          </Field>
          <Field label="発送元 (都道府県)">
            <select
              required
              value={form.ship_from_prefecture}
              onChange={(e) => set("ship_from_prefecture", e.target.value)}
              className={FIELD_CLASS}
            >
              <option value="">選択してください</option>
              {PREFECTURES.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
          </Field>
          <Field label="発送目安" className="sm:col-span-2">
            <input
              required
              value={form.ship_lead_time}
              onChange={(e) => set("ship_lead_time", e.target.value)}
              className={FIELD_CLASS}
              placeholder="例: 入金確認後3営業日以内"
            />
          </Field>
        </div>
      </fieldset>

      <fieldset className="space-y-4">
        <legend className="mb-1 text-[14px] font-semibold text-text-primary">
          非公開項目 <span className="text-[12px] font-normal text-text-secondary">(super_admin のみ閲覧。商品ページ・代理店には表示されません)</span>
        </legend>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="発送依頼の送り先メール (未設定なら発送依頼書をコピーして手動で依頼)" className="sm:col-span-2">
            <input
              type="email"
              value={form.notify_email}
              onChange={(e) => set("notify_email", e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>
          <Field label="担当者名">
            <input value={form.contact_name} onChange={(e) => set("contact_name", e.target.value)} className={FIELD_CLASS} />
          </Field>
          <Field label="電話番号">
            <input
              type="tel"
              value={form.contact_phone}
              onChange={(e) => set("contact_phone", e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>
          <Field label="連絡先メール" className="sm:col-span-2">
            <input
              type="email"
              value={form.contact_email}
              onChange={(e) => set("contact_email", e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>
          <Field label="運営メモ" className="sm:col-span-2">
            <textarea rows={3} value={form.note} onChange={(e) => set("note", e.target.value)} className={FIELD_CLASS} />
          </Field>
        </div>
      </fieldset>

      <label className="flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-border-soft px-3 py-2.5">
        <span className="text-[14px] font-medium text-text-primary">{form.is_active ? "有効" : "無効"}</span>
        <input
          type="checkbox"
          checked={form.is_active}
          onChange={(e) => set("is_active", e.target.checked)}
          className="h-5 w-5 accent-[var(--brand)]"
        />
      </label>
      {deactivating ? (
        <p className="rounded-xl border border-warning/30 bg-warning-soft px-3 py-2.5 text-[13px] leading-5 text-text-primary">
          無効にすると、この生産者の商品はショップに表示されなくなり、新しい注文もできなくなります。
          入金済みで未発送の注文は残るため、発送の手配は続けてください。
        </p>
      ) : null}

      <Field label={producer ? "変更理由 (必須・監査ログに記録されます)" : "登録理由 (任意・監査ログに記録されます)"}>
        <input
          required={Boolean(producer)}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className={FIELD_CLASS}
        />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {done ? <FormMessage tone="success">{done}</FormMessage> : null}

      <button type="submit" disabled={pending || (Boolean(producer) && !reason.trim())} className={BUTTON_CLASS}>
        {pending ? "保存中…" : producer ? "変更を保存" : "生産者を登録"}
      </button>
    </form>
  );
}
