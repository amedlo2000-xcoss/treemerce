"use client";

import { CheckCircle2, Minus, Plus, Printer, Trash2 } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";

import { Notice, formatYen } from "@/components/ui";
import {
  Chip,
  EmptyState,
  MobilePageHeader,
  PrimaryButton,
  ProgressBar,
  SectionLabel,
  Surface,
} from "@/components/mobile/primitives";
import {
  AGE_GROUPS,
  AGE_GROUP_LABELS,
  BANK_ACCOUNT_TYPE_LABELS,
  GENDERS,
  GENDER_LABELS,
  PREFECTURES,
} from "@/lib/domain/enums";
import type { PlaceOrderResult, ShopProduct } from "@/lib/domain/types";
import { useCart } from "@/lib/shop/cart";

import { ProductImage } from "../ShopParts";

const INPUT =
  "w-full rounded-2xl border border-border-soft bg-surface px-3.5 py-3 text-[16px] text-text-primary outline-none focus:border-brand";

const STEPS = ["cart", "customer", "shipping", "confirm"] as const;
type Step = (typeof STEPS)[number];

type FormState = {
  full_name: string;
  full_name_kana: string;
  email: string;
  phone: string;
  age_group: string;
  gender: string;
  postal_code: string;
  prefecture: string;
  address: string;
  note: string;
};

function formatDueDate(value: string) {
  const d = new Date(`${value}T00:00:00+09:00`);
  return new Intl.DateTimeFormat("ja-JP", {
    year: "numeric",
    month: "long",
    day: "numeric",
    weekday: "short",
    timeZone: "Asia/Tokyo",
  }).format(d);
}

function TextField({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block space-y-1.5">
      <span className="text-[13px] font-semibold text-text-secondary">{label}</span>
      {children}
      {hint ? <span className="block text-[12px] text-text-secondary">{hint}</span> : null}
    </label>
  );
}

export function CheckoutFlow({
  agentPublicId,
  products,
  shippingFee,
  acceptingOrders,
}: {
  agentPublicId: string;
  products: ShopProduct[];
  shippingFee: number;
  acceptingOrders: boolean;
}) {
  const { lines, setQuantity, clear } = useCart(agentPublicId);
  const [step, setStep] = useState<Step>("cart");
  const [form, setForm] = useState<FormState>({
    full_name: "",
    full_name_kana: "",
    email: "",
    phone: "",
    age_group: "",
    gender: "",
    postal_code: "",
    prefecture: "",
    address: "",
    note: "",
  });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<PlaceOrderResult | null>(null);

  const set = <K extends keyof FormState>(key: K, value: FormState[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  const byId = useMemo(() => new Map(products.map((p) => [p.id, p])), [products]);

  // カート内で現在も購入できる商品だけを明細にする
  const items = lines
    .map((l) => ({ line: l, product: byId.get(l.product_id) }))
    .filter((x): x is { line: typeof x.line; product: ShopProduct } => Boolean(x.product));
  const unavailableCount = lines.length - items.length;
  const subtotal = items.reduce((sum, x) => sum + Number(x.product.price) * x.line.quantity, 0);
  const overStock = items.some((x) => !x.product.in_stock || x.line.quantity > x.product.max_quantity);
  // 発送元の数 (生産者ごと。生産者情報の無い商品は運営からの 1 口にまとめる)
  const shipFromCount = new Set(items.map((x) => x.product.producer?.id ?? "operator")).size;

  const contactOk = form.email.trim() !== "" || form.phone.trim() !== "";
  const customerOk = form.full_name.trim() !== "" && contactOk;
  const shippingOk = form.prefecture !== "" && form.address.trim() !== "";

  async function submit() {
    setPending(true);
    setError(null);

    const response = await fetch("/api/public/orders", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        agent_public_id: agentPublicId,
        items: items.map((x) => ({ product_id: x.product.id, quantity: x.line.quantity })),
        full_name: form.full_name,
        full_name_kana: form.full_name_kana || null,
        email: form.email || null,
        phone: form.phone || null,
        age_group: form.age_group || null,
        gender: form.gender || null,
        postal_code: form.postal_code || null,
        prefecture: form.prefecture,
        address: form.address,
        note: form.note || null,
      }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "ご注文を受け付けられませんでした。時間をおいて再度お試しください。");
      return;
    }

    setResult(body as PlaceOrderResult);
    clear();
    window.scrollTo({ top: 0 });
  }

  /* ----------------------------------------------------------- 注文完了 */
  if (result) {
    const p = result.payment;
    return (
      <div className="mx-auto max-w-xl space-y-5">
        <Surface className="text-center">
          <CheckCircle2 size={44} className="mx-auto text-success" />
          <h1 className="mt-3 text-[22px] font-bold text-text-primary">ご注文を受け付けました</h1>
          <p className="mt-1 text-[14px] text-text-secondary">
            注文番号 <span className="font-mono font-semibold text-text-primary">{result.order_no}</span>
          </p>
        </Surface>

        <Notice tone="warning">
          お支払いは銀行振込です。下記の口座へ <strong>{formatDueDate(p.due_date)}</strong>{" "}
          までにお振込みください。期限を過ぎると、ご注文は自動的にキャンセルされます。
          この画面は再表示できませんので、振込先と注文番号を控えてください。
        </Notice>

        <div className="space-y-2">
          <SectionLabel>お振込先</SectionLabel>
          <Surface className="!py-2">
            <dl className="divide-y divide-border-soft">
              {[
                ["金融機関", p.bank_name],
                ["支店", p.bank_branch],
                ["口座種別", p.bank_account_type ? BANK_ACCOUNT_TYPE_LABELS[p.bank_account_type] : null],
                ["口座番号", p.bank_account_number],
                ["口座名義", p.bank_account_holder],
                ["お振込金額", formatYen(Number(result.total))],
                ["お振込期限", formatDueDate(p.due_date)],
              ].map(([label, value]) => (
                <div key={label} className="flex items-start justify-between gap-4 py-3">
                  <dt className="shrink-0 text-[13px] text-text-secondary">{label}</dt>
                  <dd className="text-right text-[15px] font-semibold text-text-primary">{value ?? "—"}</dd>
                </div>
              ))}
            </dl>
          </Surface>
          <p className="px-1 text-[12px] leading-5 text-text-secondary">
            振込名義の前に注文番号の数字をご記入いただくと、確認がスムーズです。振込手数料はお客様のご負担となります。
          </p>
        </div>

        <div className="space-y-2">
          <SectionLabel>ご注文内容</SectionLabel>
          <Surface padded={false} className="divide-y divide-border-soft">
            {result.items.map((item) => (
              <div key={item.product_name} className="flex items-center justify-between gap-3 px-4 py-3">
                <div className="min-w-0">
                  <p className="truncate text-[14px] font-medium text-text-primary">{item.product_name}</p>
                  <p className="text-[12px] text-text-secondary">
                    {formatYen(Number(item.unit_price))} × {item.quantity}
                  </p>
                </div>
                <p className="shrink-0 text-[14px] font-semibold tabular-nums">{formatYen(Number(item.amount))}</p>
              </div>
            ))}
            <div className="space-y-1 px-4 py-3 text-[14px]">
              <div className="flex justify-between text-text-secondary">
                <span>小計</span>
                <span className="tabular-nums">{formatYen(Number(result.subtotal))}</span>
              </div>
              <div className="flex justify-between text-text-secondary">
                <span>送料</span>
                <span className="tabular-nums">{formatYen(Number(result.shipping_fee))}</span>
              </div>
              <div className="flex justify-between pt-1 text-[16px] font-bold text-text-primary">
                <span>合計</span>
                <span className="tabular-nums">{formatYen(Number(result.total))}</span>
              </div>
            </div>
          </Surface>
        </div>

        <div className="grid gap-2 sm:grid-cols-2">
          <PrimaryButton type="button" variant="secondary" onClick={() => window.print()}>
            <Printer size={18} />
            この画面を印刷
          </PrimaryButton>
          <PrimaryButton href={`/shop/${agentPublicId}`}>商品一覧へ戻る</PrimaryButton>
        </div>
      </div>
    );
  }

  /* ----------------------------------------------------------- 手続き */
  const stepIndex = STEPS.indexOf(step);

  if (lines.length === 0) {
    return (
      <div className="mx-auto max-w-xl space-y-5">
        <MobilePageHeader title="カート" />
        <EmptyState title="カートに商品がありません" />
        <PrimaryButton href={`/shop/${agentPublicId}`} variant="secondary">
          商品を見る
        </PrimaryButton>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-xl space-y-5">
      <ProgressBar step={stepIndex + 1} total={STEPS.length} />

      {!acceptingOrders ? (
        <Notice tone="warning">現在ご注文の受付を停止しております。</Notice>
      ) : null}

      {step === "cart" ? (
        <>
          <MobilePageHeader title="カート" />
          {unavailableCount > 0 ? (
            <Notice tone="warning">
              お取り扱いを終了した商品が {unavailableCount} 点あったため、カートから除いて表示しています。
            </Notice>
          ) : null}
          <Surface padded={false} className="divide-y divide-border-soft">
            {items.map(({ line, product }) => (
              <div key={product.id} className="flex gap-3 p-4">
                <ProductImage path={product.image_path} className="h-16 w-16 shrink-0 rounded-xl" />
                <div className="min-w-0 flex-1 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="text-[14px] font-semibold leading-5 text-text-primary">{product.name}</p>
                      {product.producer ? (
                        <p className="text-[12px] text-text-secondary">
                          {product.producer.name} ・ {product.producer.ship_from_prefecture}から発送
                        </p>
                      ) : null}
                    </div>
                    <button
                      type="button"
                      aria-label="カートから削除"
                      onClick={() => setQuantity(product.id, 0)}
                      className="shrink-0 text-text-secondary hover:text-danger"
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center rounded-xl border border-border-soft">
                      <button
                        type="button"
                        aria-label="数量を減らす"
                        disabled={line.quantity <= 1}
                        onClick={() => setQuantity(product.id, line.quantity - 1)}
                        className="flex h-9 w-9 items-center justify-center disabled:opacity-40"
                      >
                        <Minus size={14} />
                      </button>
                      <span className="w-8 text-center text-[14px] font-semibold tabular-nums">
                        {line.quantity}
                      </span>
                      <button
                        type="button"
                        aria-label="数量を増やす"
                        disabled={line.quantity >= product.max_quantity}
                        onClick={() => setQuantity(product.id, line.quantity + 1)}
                        className="flex h-9 w-9 items-center justify-center disabled:opacity-40"
                      >
                        <Plus size={14} />
                      </button>
                    </div>
                    <span className="text-[15px] font-bold tabular-nums text-text-primary">
                      {formatYen(Number(product.price) * line.quantity)}
                    </span>
                  </div>
                  {!product.in_stock || line.quantity > product.max_quantity ? (
                    <p className="text-[12px] font-medium text-danger">
                      在庫が不足しています。数量を減らしてください。
                    </p>
                  ) : null}
                </div>
              </div>
            ))}
            <div className="space-y-1 p-4 text-[14px]">
              <div className="flex justify-between text-text-secondary">
                <span>小計</span>
                <span className="tabular-nums">{formatYen(subtotal)}</span>
              </div>
              <div className="flex justify-between text-text-secondary">
                <span>送料</span>
                <span className="tabular-nums">{formatYen(shippingFee)}</span>
              </div>
              <div className="flex justify-between pt-1 text-[16px] font-bold text-text-primary">
                <span>合計 (税込)</span>
                <span className="tabular-nums">{formatYen(subtotal + shippingFee)}</span>
              </div>
            </div>
          </Surface>
          {shipFromCount > 1 ? (
            <p className="px-1 text-[12px] leading-5 text-text-secondary">
              ご注文の商品は生産者ごとに産地から直接お届けするため、{shipFromCount} 個に分かれて届きます。
              送料は 1 回のご注文につき {formatYen(shippingFee)} のままです。
            </p>
          ) : null}
          <PrimaryButton
            type="button"
            disabled={!acceptingOrders || items.length === 0 || overStock}
            onClick={() => setStep("customer")}
          >
            ご注文手続きへ
          </PrimaryButton>
          <PrimaryButton href={`/shop/${agentPublicId}`} variant="ghost">
            買い物を続ける
          </PrimaryButton>
        </>
      ) : null}

      {step === "customer" ? (
        <>
          <MobilePageHeader title="お客様情報" description="ご連絡先はメールアドレスか電話番号のどちらか一方が必須です。" />
          <Surface className="space-y-4">
            <TextField label="お名前 (必須)">
              <input value={form.full_name} onChange={(e) => set("full_name", e.target.value)} className={INPUT} autoComplete="name" />
            </TextField>
            <TextField label="フリガナ">
              <input value={form.full_name_kana} onChange={(e) => set("full_name_kana", e.target.value)} className={INPUT} />
            </TextField>
            <TextField label="メールアドレス">
              <input type="email" value={form.email} onChange={(e) => set("email", e.target.value)} className={INPUT} autoComplete="email" inputMode="email" />
            </TextField>
            <TextField label="電話番号">
              <input type="tel" value={form.phone} onChange={(e) => set("phone", e.target.value)} className={INPUT} autoComplete="tel" inputMode="tel" />
            </TextField>
            {!contactOk ? (
              <p className="text-[12px] text-text-secondary">メールアドレスか電話番号を入力してください。</p>
            ) : null}
          </Surface>

          <div className="space-y-2">
            <SectionLabel>アンケート (任意)</SectionLabel>
            <Surface className="space-y-4">
              <div className="space-y-2">
                <p className="text-[13px] font-semibold text-text-secondary">年代</p>
                <div className="flex flex-wrap gap-2">
                  {AGE_GROUPS.filter((g) => g !== "unknown").map((g) => (
                    <Chip key={g} selected={form.age_group === g} onClick={() => set("age_group", form.age_group === g ? "" : g)}>
                      {AGE_GROUP_LABELS[g]}
                    </Chip>
                  ))}
                </div>
              </div>
              <div className="space-y-2">
                <p className="text-[13px] font-semibold text-text-secondary">性別</p>
                <div className="flex flex-wrap gap-2">
                  {GENDERS.map((g) => (
                    <Chip key={g} selected={form.gender === g} onClick={() => set("gender", form.gender === g ? "" : g)}>
                      {GENDER_LABELS[g]}
                    </Chip>
                  ))}
                </div>
              </div>
            </Surface>
          </div>

          <div className="flex gap-2">
            <PrimaryButton type="button" variant="secondary" onClick={() => setStep("cart")}>
              戻る
            </PrimaryButton>
            <PrimaryButton type="button" disabled={!customerOk} onClick={() => setStep("shipping")}>
              次へ
            </PrimaryButton>
          </div>
        </>
      ) : null}

      {step === "shipping" ? (
        <>
          <MobilePageHeader title="お届け先" />
          <Surface className="space-y-4">
            <TextField label="郵便番号">
              <input value={form.postal_code} onChange={(e) => set("postal_code", e.target.value)} className={INPUT} autoComplete="postal-code" inputMode="numeric" placeholder="例: 100-0001" />
            </TextField>
            <TextField label="都道府県 (必須)">
              <select value={form.prefecture} onChange={(e) => set("prefecture", e.target.value)} className={INPUT}>
                <option value="">選択してください</option>
                {PREFECTURES.map((p) => (
                  <option key={p} value={p}>
                    {p}
                  </option>
                ))}
              </select>
            </TextField>
            <TextField label="市区町村・番地・建物名 (必須)">
              <input value={form.address} onChange={(e) => set("address", e.target.value)} className={INPUT} autoComplete="street-address" />
            </TextField>
            <TextField label="備考" hint="配達のご希望などがあればご記入ください。">
              <textarea rows={3} value={form.note} onChange={(e) => set("note", e.target.value)} className={INPUT} />
            </TextField>
          </Surface>
          <div className="flex gap-2">
            <PrimaryButton type="button" variant="secondary" onClick={() => setStep("customer")}>
              戻る
            </PrimaryButton>
            <PrimaryButton type="button" disabled={!shippingOk} onClick={() => setStep("confirm")}>
              確認へ
            </PrimaryButton>
          </div>
        </>
      ) : null}

      {step === "confirm" ? (
        <>
          <MobilePageHeader title="ご注文内容の確認" />
          <Surface padded={false} className="divide-y divide-border-soft">
            {items.map(({ line, product }) => (
              <div key={product.id} className="flex items-center justify-between gap-3 px-4 py-3">
                <p className="min-w-0 truncate text-[14px] text-text-primary">
                  {product.name} × {line.quantity}
                </p>
                <p className="shrink-0 text-[14px] font-semibold tabular-nums">
                  {formatYen(Number(product.price) * line.quantity)}
                </p>
              </div>
            ))}
            <div className="flex justify-between px-4 py-3 text-[16px] font-bold">
              <span>合計 (送料込み)</span>
              <span className="tabular-nums">{formatYen(subtotal + shippingFee)}</span>
            </div>
          </Surface>

          <Surface className="space-y-1 text-[14px]">
            <p className="font-semibold text-text-primary">{form.full_name} 様</p>
            <p className="text-text-secondary">{[form.email, form.phone].filter(Boolean).join(" / ")}</p>
            <p className="text-text-secondary">
              {form.postal_code ? `〒${form.postal_code} ` : ""}
              {form.prefecture}
              {form.address}
            </p>
          </Surface>

          <Notice tone="info">
            お支払いは銀行振込 (前払い) です。ご注文後に表示される口座へお振込みください。
            お支払い条件・返品については
            <Link href="/legal/tokushoho" target="_blank" className="mx-1 font-semibold text-brand underline">
              特定商取引法に基づく表記
            </Link>
            をご確認ください。
          </Notice>

          {error ? <Notice tone="danger">{error}</Notice> : null}

          <div className="flex gap-2">
            <PrimaryButton type="button" variant="secondary" onClick={() => setStep("shipping")} disabled={pending}>
              戻る
            </PrimaryButton>
            <PrimaryButton type="button" onClick={submit} disabled={pending || !acceptingOrders || overStock}>
              {pending ? "送信中…" : "注文を確定する"}
            </PrimaryButton>
          </div>
        </>
      ) : null}
    </div>
  );
}
