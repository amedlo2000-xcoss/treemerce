"use client";

import { Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { PLACEHOLDER_OPTIONS, ProductPlaceholder } from "@/components/ProductPlaceholder";
import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";
import { PLACEHOLDER_PRODUCER_ID } from "@/lib/domain/enums";
import {
  ITEM_KIND_LABELS,
  SALES_STATUSES,
  SALES_STATUS_LABELS,
  productFieldLabels,
} from "@/lib/domain/product-labels";
import type {
  AdminCategoryRow,
  ProducerPublicRow,
  ProductItemKind,
  ProductRow,
  ProductSalesStatus,
} from "@/lib/domain/types";
import { PRODUCT_IMAGE_BUCKET, productImageUrl } from "@/lib/storage";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

const STATUS_HINTS: Record<ProductSalesStatus, string> = {
  unpublished: "ショップ・一覧ページに表示しません。",
  preparing: "価格を「未定」と表示し、注文はできません (ショップ・オブザーバー特典付き製品一覧に表示)。",
  on_sale: "ショップで注文できます。販売価格が必要です。",
};

/**
 * 商品の登録・編集フォーム (super_admin 専用ページから使う。保存は treemerce_admin_save_product, 0023)。
 * 画像は Storage (product-images) にランダム名で直接アップロードし、パスだけを RPC に渡す。
 * 画像がない商品は、選んだイラスト (「イメージ」表示付き) をショップ・一覧ページで表示する。
 *
 *   * 販売状態: 非公開 / 準備中 (価格未定・注文不可) / 公開中 (注文可)
 *   * 準備中の価格は「予定価格」として任意入力 (運営だけが見られ、ショップ・公開ページには出ない)
 *   * サービスは予約の仕組みができるまで公開中にできない (DB でも拒否)
 *   * カテゴリは有効なものだけを選べる (無効なカテゴリは現在のカテゴリのままの場合のみ表示)
 */
export function ProductForm({
  product,
  producers,
  categories,
}: {
  product?: ProductRow;
  /** 選択肢。有効な生産者と仮の生産者 (+ 現在の生産者が無効ならそれも) */
  producers: ProducerPublicRow[];
  /** 全カテゴリ (無効を含む)。選択肢には有効なものと現在のカテゴリだけを出す */
  categories: AdminCategoryRow[];
}) {
  const router = useRouter();
  const [form, setForm] = useState({
    name: product?.name ?? "",
    name_kana: product?.name_kana ?? "",
    product_type_label: product?.product_type_label ?? "",
    sku: product?.sku ?? "",
    category_id: product?.category_id ?? "",
    item_kind: (product?.item_kind ?? "goods") as ProductItemKind,
    sales_status: (product?.sales_status ?? "unpublished") as ProductSalesStatus,
    has_observer_benefit: product?.has_observer_benefit ?? false,
    price: product?.price != null ? String(Number(product.price)) : "",
    stock: product ? String(product.stock) : "0",
    sort_order: product ? String(product.sort_order) : "0",
    description: product?.description ?? "",
    producer_id: product?.producer_id ?? PLACEHOLDER_PRODUCER_ID,
    content_volume: product?.content_volume ?? "",
    ingredients: product?.ingredients ?? "",
    best_before_note: product?.best_before_note ?? "",
    placeholder_key: product?.placeholder_key ?? "",
  });
  const [imagePath, setImagePath] = useState<string | null>(product?.image_path ?? null);
  const [reason, setReason] = useState("");
  const [uploading, setUploading] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  const categoryOptions = categories.filter((c) => c.is_active || c.id === product?.category_id);
  const labels = productFieldLabels(form.item_kind);
  const isService = form.item_kind === "service";

  async function handleImage(file: File | undefined) {
    if (!file) return;
    setError(null);
    const ext = IMAGE_TYPES[file.type];
    if (!ext) {
      setError("画像は JPEG / PNG / WebP のみアップロードできます。");
      return;
    }
    if (file.size > MAX_IMAGE_BYTES) {
      setError("画像は 5MB 以下にしてください。");
      return;
    }

    setUploading(true);
    // 推測できないファイル名にする (非公開商品の画像 URL を当てられないように)
    const path = `products/${crypto.randomUUID()}.${ext}`;
    const { error: uploadError } = await getSupabaseBrowserClient()
      .storage.from(PRODUCT_IMAGE_BUCKET)
      .upload(path, file, { contentType: file.type, upsert: false });
    setUploading(false);

    if (uploadError) {
      setError("画像のアップロードに失敗しました。権限またはファイル形式を確認してください。");
      return;
    }
    setImagePath(path);
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    setDone(null);
    if (!form.category_id) {
      setError("カテゴリを選択してください。");
      return;
    }
    if (isService && form.sales_status === "on_sale") {
      setError("サービスは予約の仕組みができるまで公開 (注文可能) にできません。「準備中」にしてください。");
      return;
    }
    if (form.sales_status === "on_sale" && form.price.trim() === "") {
      setError("公開中にするには販売価格が必要です (価格が未定なら「準備中」にしてください)。");
      return;
    }
    setPending(true);

    const response = await fetch(product ? `/api/admin/products/${product.id}` : "/api/admin/products", {
      method: product ? "PATCH" : "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...form,
        price: form.price.trim() === "" ? null : Number(form.price),
        stock: Number(form.stock || 0),
        sort_order: Number(form.sort_order || 0),
        image_path: imagePath,
        placeholder_key: form.placeholder_key || null,
        reason: reason || null,
      }),
    });
    const body = await response.json().catch(() => null);
    setPending(false);

    if (!response.ok) {
      setError(body?.error?.message ?? "保存に失敗しました。");
      return;
    }

    if (!product) {
      router.push(`/admin/products/${body.id}?created=1`);
      return;
    }
    setDone(
      unsetProducerOnPublish
        ? "保存しました (生産者は「未設定（運営）」のまま公開中です)。変更内容は監査ログに記録されています。"
        : "保存しました。変更内容は監査ログに記録されています。",
    );
    setReason("");
    router.refresh();
  }

  const preview = productImageUrl(imagePath);
  const unsetProducerOnPublish = form.sales_status === "on_sale" && form.producer_id === PLACEHOLDER_PRODUCER_ID;
  const selectedProducer = producers.find((p) => p.id === form.producer_id);

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <div className="grid gap-5 md:grid-cols-[14rem_minmax(0,1fr)]">
        <div className="space-y-2">
          <span className="block text-[12px] font-semibold text-text-secondary">商品画像</span>
          <div className="relative aspect-square overflow-hidden rounded-2xl border border-dashed border-border-soft bg-surface-muted">
            {preview ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={preview} alt="" className="h-full w-full object-cover" />
            ) : (
              <ProductPlaceholder
                placeholderKey={form.placeholder_key || null}
                itemKind={form.item_kind}
                className="h-full w-full"
              />
            )}
          </div>
          <div className="flex gap-2">
            <label className="flex-1 cursor-pointer rounded-xl border border-border-soft px-3 py-2 text-center text-[13px] font-medium text-text-primary transition-colors hover:bg-surface-muted">
              {uploading ? "アップロード中…" : preview ? "画像を変更" : "画像を選択"}
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="sr-only"
                disabled={uploading}
                onChange={(e) => handleImage(e.target.files?.[0])}
              />
            </label>
            {preview ? (
              <button
                type="button"
                onClick={() => setImagePath(null)}
                aria-label="画像を外す"
                className="rounded-xl border border-border-soft px-3 text-text-secondary transition-colors hover:bg-surface-muted"
              >
                <Trash2 size={16} />
              </button>
            ) : null}
          </div>
          <p className="text-[11px] leading-4 text-text-secondary">JPEG / PNG / WebP、5MB まで</p>
          <Field label="画像がないときのイラスト">
            <select
              value={form.placeholder_key}
              onChange={(e) => set("placeholder_key", e.target.value)}
              className={FIELD_CLASS}
            >
              <option value="">標準 (物品 / サービスの汎用)</option>
              {PLACEHOLDER_OPTIONS.map((o) => (
                <option key={o.key} value={o.key}>
                  {o.label}
                </option>
              ))}
            </select>
          </Field>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="商品名" className="sm:col-span-2">
            <input required value={form.name} onChange={(e) => set("name", e.target.value)} className={FIELD_CLASS} />
          </Field>
          <Field label="読み仮名 (任意)">
            <input value={form.name_kana} onChange={(e) => set("name_kana", e.target.value)} className={FIELD_CLASS} />
          </Field>
          <Field label="商品の種類 (任意)">
            <input
              value={form.product_type_label}
              onChange={(e) => set("product_type_label", e.target.value)}
              className={FIELD_CLASS}
              placeholder="例: はちみつ梅"
            />
          </Field>
          <Field label="カテゴリ">
            <select
              required
              value={form.category_id}
              onChange={(e) => set("category_id", e.target.value)}
              className={FIELD_CLASS}
            >
              <option value="">選択してください</option>
              {categoryOptions.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                  {c.is_active ? "" : " (無効)"}
                </option>
              ))}
            </select>
          </Field>
          <Field label="物品 / サービス">
            <select
              value={form.item_kind}
              onChange={(e) => {
                const kind = e.target.value as ProductItemKind;
                set("item_kind", kind);
                // サービスは公開中にできないため、公開中なら準備中に切り替える
                if (kind === "service" && form.sales_status === "on_sale") set("sales_status", "preparing");
              }}
              className={FIELD_CLASS}
            >
              {(Object.keys(ITEM_KIND_LABELS) as ProductItemKind[]).map((k) => (
                <option key={k} value={k}>
                  {ITEM_KIND_LABELS[k]}
                </option>
              ))}
            </select>
          </Field>
          <Field label="販売状態" className="sm:col-span-2">
            <select
              value={form.sales_status}
              onChange={(e) => set("sales_status", e.target.value as ProductSalesStatus)}
              className={FIELD_CLASS}
            >
              {SALES_STATUSES.map((s) => (
                <option key={s} value={s} disabled={s === "on_sale" && isService}>
                  {SALES_STATUS_LABELS[s]}
                  {s === "on_sale" && isService ? " (サービスは予約の仕組みができるまで不可)" : ""}
                </option>
              ))}
            </select>
            <span className="mt-1 block text-[12px] text-text-secondary">{STATUS_HINTS[form.sales_status]}</span>
          </Field>
          <Field
            label={
              form.sales_status === "on_sale"
                ? "販売価格 (円・税込・必須)"
                : form.sales_status === "preparing"
                  ? "予定価格 (任意・運営だけが見られます)"
                  : "価格 (円・税込・任意)"
            }
          >
            <input
              required={form.sales_status === "on_sale"}
              type="number"
              min={0}
              step={1}
              inputMode="numeric"
              value={form.price}
              onChange={(e) => set("price", e.target.value)}
              className={FIELD_CLASS}
              placeholder={form.sales_status === "on_sale" ? "" : "未定なら空欄"}
            />
          </Field>
          <Field label="在庫数">
            <input
              required
              type="number"
              min={0}
              step={1}
              inputMode="numeric"
              value={form.stock}
              onChange={(e) => set("stock", e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>
          <label className="flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-border-soft px-3 py-2.5 sm:col-span-2">
            <span>
              <span className="block text-[14px] font-medium text-text-primary">オブザーバー特典付き</span>
              <span className="block text-[12px] text-text-secondary">
                印を付けた公開中・準備中の商品が「オブザーバー特典付き製品一覧」に表示されます。
              </span>
            </span>
            <input
              type="checkbox"
              checked={form.has_observer_benefit}
              onChange={(e) => set("has_observer_benefit", e.target.checked)}
              className="h-5 w-5 accent-[var(--brand)]"
            />
          </label>
          <Field label={isService ? "提供者" : "生産者"} className="sm:col-span-2">
            <select
              value={form.producer_id}
              onChange={(e) => set("producer_id", e.target.value)}
              className={FIELD_CLASS}
            >
              {producers.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.is_placeholder
                    ? `${p.name}${isService ? "" : " ※運営から発送"}`
                    : `${p.name} (${p.origin ?? "—"}${isService ? "" : ` / 発送元: ${p.ship_from_prefecture ?? "—"}`})${p.is_active ? "" : " ※無効"}`}
                </option>
              ))}
            </select>
            {selectedProducer && !selectedProducer.is_placeholder && !isService ? (
              <span className="mt-1 block text-[12px] text-text-secondary">
                発送目安: {selectedProducer.ship_lead_time ?? "—"} (商品ページに表示されます)
              </span>
            ) : null}
          </Field>
          <Field label="SKU (任意)">
            <input value={form.sku} onChange={(e) => set("sku", e.target.value)} className={FIELD_CLASS} />
          </Field>
          <Field label="表示順 (小さいほど先頭)">
            <input
              type="number"
              step={1}
              value={form.sort_order}
              onChange={(e) => set("sort_order", e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>
          <Field
            label={form.sales_status === "on_sale" ? `${labels.volume}・規格 (公開時は必須)` : `${labels.volume}・規格`}
            className="sm:col-span-2"
          >
            <input
              required={form.sales_status === "on_sale"}
              value={form.content_volume}
              onChange={(e) => set("content_volume", e.target.value)}
              className={FIELD_CLASS}
              placeholder={isService ? "例: 1回 60分" : "例: 500g×2袋"}
            />
          </Field>
          {!isService ? (
            <>
              <Field label="原材料・成分 (任意)" className="sm:col-span-2">
                <textarea
                  rows={3}
                  value={form.ingredients}
                  onChange={(e) => set("ingredients", e.target.value)}
                  className={FIELD_CLASS}
                />
              </Field>
              <Field label="賞味期限 / 使用期限の目安 (任意)" className="sm:col-span-2">
                <input
                  value={form.best_before_note}
                  onChange={(e) => set("best_before_note", e.target.value)}
                  className={FIELD_CLASS}
                  placeholder="例: 製造日から180日"
                />
              </Field>
            </>
          ) : null}
          <Field label="商品説明" className="sm:col-span-2">
            <textarea
              rows={5}
              value={form.description}
              onChange={(e) => set("description", e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>
        </div>
      </div>

      {unsetProducerOnPublish ? (
        <p
          role="status"
          className="rounded-xl border border-warning/30 bg-warning-soft px-3 py-2.5 text-[13px] leading-5 text-text-primary"
        >
          生産者が「未設定（運営）」のまま公開します。生産者から直送する商品の場合は、公開前に正しい生産者を選んでください。
          運営から発送する商品であればこのままで構いません (商品ページには生産者情報が表示されません)。
        </p>
      ) : null}

      <Field label="変更理由 (任意・監査ログに記録されます)">
        <input value={reason} onChange={(e) => setReason(e.target.value)} className={FIELD_CLASS} />
      </Field>

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {done ? <FormMessage tone="success">{done}</FormMessage> : null}

      <button type="submit" disabled={pending || uploading} className={BUTTON_CLASS}>
        {pending ? "保存中…" : product ? "変更を保存" : "商品を登録"}
      </button>
    </form>
  );
}
