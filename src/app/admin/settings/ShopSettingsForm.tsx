"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";
import { BANK_ACCOUNT_TYPES, BANK_ACCOUNT_TYPE_LABELS } from "@/lib/domain/enums";
import type { ShopSettingsRow } from "@/lib/domain/types";

const TEXT_FIELDS = [
  "seller_name",
  "seller_representative",
  "seller_address",
  "seller_phone",
  "seller_email",
  "business_hours",
  "price_note",
  "additional_fees",
  "payment_method_note",
  "delivery_time",
  "return_policy",
  "extra_notes",
  "bank_name",
  "bank_branch",
  "bank_account_number",
  "bank_account_holder",
] as const;
type TextKey = (typeof TEXT_FIELDS)[number];

function Section({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <fieldset className="space-y-4 rounded-[20px] border border-border-soft p-4 md:p-5">
      <legend className="px-1 text-[15px] font-semibold text-text-primary">{title}</legend>
      {description ? <p className="-mt-2 text-[12px] leading-5 text-text-secondary">{description}</p> : null}
      {children}
    </fieldset>
  );
}

/**
 * ショップ設定フォーム (super_admin)。振込先は「運営の口座」であり、
 * 代理店の報酬受取口座 (bank_accounts) とは別物。
 */
export function ShopSettingsForm({ settings }: { settings: ShopSettingsRow }) {
  const router = useRouter();
  const [text, setText] = useState<Record<TextKey, string>>(
    Object.fromEntries(TEXT_FIELDS.map((k) => [k, settings[k] ?? ""])) as Record<TextKey, string>,
  );
  const [accountType, setAccountType] = useState(settings.bank_account_type ?? "");
  const [shippingFee, setShippingFee] = useState(String(settings.shipping_fee ?? 0));
  const [dueDays, setDueDays] = useState(String(settings.payment_due_days ?? 7));
  const [accepting, setAccepting] = useState(settings.is_accepting_orders);
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const input = (key: TextKey, opts: { multiline?: boolean; placeholder?: string } = {}) =>
    opts.multiline ? (
      <textarea
        rows={3}
        value={text[key]}
        placeholder={opts.placeholder}
        onChange={(e) => setText((prev) => ({ ...prev, [key]: e.target.value }))}
        className={FIELD_CLASS}
      />
    ) : (
      <input
        value={text[key]}
        placeholder={opts.placeholder}
        onChange={(e) => setText((prev) => ({ ...prev, [key]: e.target.value }))}
        className={FIELD_CLASS}
      />
    );

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    setDone(null);

    const response = await fetch("/api/admin/shop-settings", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        patch: {
          ...text,
          bank_account_type: accountType || null,
          shipping_fee: Number(shippingFee || 0),
          payment_due_days: Number(dueDays || 7),
          is_accepting_orders: accepting,
        },
        reason,
      }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "保存に失敗しました。");
      return;
    }
    setDone("保存しました。変更内容は監査ログに記録されています。");
    setReason("");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <Section title="注文受付" description="受付を開始するには、振込先と販売事業者 (名称・所在地・電話番号) の登録が必要です。">
        <label className="flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-border-soft px-4 py-3">
          <span>
            <span className="block text-[15px] font-semibold text-text-primary">
              {accepting ? "注文を受け付けています" : "注文受付を停止しています"}
            </span>
            <span className="block text-[12px] text-text-secondary">停止中もショップの閲覧はできます。</span>
          </span>
          <input
            type="checkbox"
            checked={accepting}
            onChange={(e) => setAccepting(e.target.checked)}
            className="h-5 w-5 accent-[var(--brand)]"
          />
        </label>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="送料 (円・1注文あたり)">
            <input type="number" min={0} step={1} value={shippingFee} onChange={(e) => setShippingFee(e.target.value)} className={FIELD_CLASS} />
          </Field>
          <Field label="支払期限 (注文日からの日数・1〜60)">
            <input type="number" min={1} max={60} step={1} value={dueDays} onChange={(e) => setDueDays(e.target.value)} className={FIELD_CLASS} />
          </Field>
        </div>
        <p className="text-[12px] leading-5 text-text-secondary">
          支払期限を過ぎた未入金の注文は自動でキャンセルされ、在庫が戻ります。日数を変更しても、受付済みの注文の期限は変わりません。
        </p>
      </Section>

      <Section title="お振込先 (運営の口座)" description="注文完了画面でお客様に表示されます。代理店の報酬受取口座とは別です。">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="金融機関名">{input("bank_name", { placeholder: "例: ○○銀行" })}</Field>
          <Field label="支店名">{input("bank_branch")}</Field>
          <Field label="口座種別">
            <select value={accountType} onChange={(e) => setAccountType(e.target.value as typeof accountType)} className={FIELD_CLASS}>
              <option value="">選択してください</option>
              {BANK_ACCOUNT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {BANK_ACCOUNT_TYPE_LABELS[t]}
                </option>
              ))}
            </select>
          </Field>
          <Field label="口座番号">{input("bank_account_number")}</Field>
          <Field label="口座名義 (カナ)" className="sm:col-span-2">
            {input("bank_account_holder")}
          </Field>
        </div>
      </Section>

      <Section title="特定商取引法に基づく表記" description="公開ページ「特定商取引法に基づく表記」に表示されます。内容は必ず事業者ご自身でご確認ください。">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="販売事業者 (必須)">{input("seller_name")}</Field>
          <Field label="運営責任者">{input("seller_representative")}</Field>
          <Field label="所在地 (必須)" className="sm:col-span-2">
            {input("seller_address")}
          </Field>
          <Field label="電話番号 (必須)">{input("seller_phone")}</Field>
          <Field label="メールアドレス">{input("seller_email")}</Field>
          <Field label="営業時間" className="sm:col-span-2">
            {input("business_hours", { placeholder: "例: 平日 10:00〜17:00" })}
          </Field>
          <Field label="販売価格について" className="sm:col-span-2">
            {input("price_note", { multiline: true, placeholder: "空欄の場合「各商品ページに税込価格で表示しています。」と表示" })}
          </Field>
          <Field label="商品代金以外の必要料金 (送料・振込手数料以外)" className="sm:col-span-2">
            {input("additional_fees", { multiline: true })}
          </Field>
          <Field label="お支払いについての補足" className="sm:col-span-2">
            {input("payment_method_note", { multiline: true })}
          </Field>
          <Field label="商品の引渡時期" className="sm:col-span-2">
            {input("delivery_time", { multiline: true, placeholder: "例: ご入金確認後、3営業日以内に発送します。" })}
          </Field>
          <Field label="返品・交換・キャンセル" className="sm:col-span-2">
            {input("return_policy", { multiline: true })}
          </Field>
          <Field label="その他" className="sm:col-span-2">
            {input("extra_notes", { multiline: true })}
          </Field>
        </div>
      </Section>

      <Field label="変更理由 (必須・監査ログに記録されます)">
        <input required value={reason} onChange={(e) => setReason(e.target.value)} className={FIELD_CLASS} />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {done ? <FormMessage tone="success">{done}</FormMessage> : null}

      <button type="submit" disabled={pending || !reason.trim()} className={BUTTON_CLASS}>
        {pending ? "保存中…" : "設定を保存"}
      </button>
    </form>
  );
}
