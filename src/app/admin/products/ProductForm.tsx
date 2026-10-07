"use client";

import { ImagePlus, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { BUTTON_CLASS, FIELD_CLASS, Field, FormMessage } from "@/components/ui";
import {
  PLACEHOLDER_PRODUCER_ID,
  PRODUCT_CATEGORIES,
  PRODUCT_CATEGORY_LABELS,
} from "@/lib/domain/enums";
import type { ProducerPublicRow, ProductRow } from "@/lib/domain/types";
import { PRODUCT_IMAGE_BUCKET, productImageUrl } from "@/lib/storage";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

/**
 * 商品の登録・編集フォーム (super_admin 専用ページから使う)。
 * 画像は Storage (product-images) にランダム名で直接アップロードし、パスだけを RPC に渡す。
 * アップロードの可否は Storage の RLS (0012: super_admin のみ) でも判定される。
 *
 * 生産者が仮の「未設定（運営）」のまま公開する場合は警告を出す (公開自体は止めない)。
 * 内容量・規格は公開時のみ必須 (商品ページに表示するため)。
 */
export function ProductForm({
  product,
  producers,
}: {
  product?: ProductRow;
  /** 選択肢。有効な生産者と仮の生産者 (+ 現在の生産者が無効ならそれも) */
  producers: ProducerPublicRow[];
}) {
  const router = useRouter();
  const [form, setForm] = useState({
    name: product?.name ?? "",
    sku: product?.sku ?? "",
    category: product?.category ?? "other",
    price: product ? String(product.price) : "",
    stock: product ? String(product.stock) : "0",
    sort_order: product ? String(product.sort_order) : "0",
    description: product?.description ?? "",
    is_published: product?.is_published ?? false,
    producer_id: product?.producer_id ?? PLACEHOLDER_PRODUCER_ID,
    content_volume: product?.content_volume ?? "",
    ingredients: product?.ingredients ?? "",
    best_before_note: product?.best_before_note ?? "",
  });
  const [imagePath, setImagePath] = useState<string | null>(product?.image_path ?? null);
  const [reason, setReason] = useState("");
  const [uploading, setUploading] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

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
    setPending(true);
    setError(null);
    setDone(null);

    const response = await fetch(product ? `/api/admin/products/${product.id}` : "/api/admin/products", {
      method: product ? "PATCH" : "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        ...form,
        price: Number(form.price),
        stock: Number(form.stock),
        sort_order: Number(form.sort_order || 0),
        image_path: imagePath,
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
  const unsetProducerOnPublish = form.is_published && form.producer_id === PLACEHOLDER_PRODUCER_ID;
  const selectedProducer = producers.find((p) => p.id === form.producer_id);

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <div className="grid gap-5 md:grid-cols-[14rem_minmax(0,1fr)]">
        <div className="space-y-2">
          <span className="block text-[12px] font-semibold text-text-secondary">商品画像</span>
          <div className="relative flex aspect-square items-center justify-center overflow-hidden rounded-2xl border border-dashed border-border-soft bg-surface-muted">
            {preview ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={preview} alt="" className="h-full w-full object-cover" />
            ) : (
              <ImagePlus size={32} className="text-text-secondary" />
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
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="商品名" className="sm:col-span-2">
            <input
              required
              value={form.name}
              onChange={(e) => set("name", e.target.value)}
              className={FIELD_CLASS}
            />
          </Field>
          <Field label="価格 (円・税込)">
            <input
              required
              type="number"
              min={0}
              step={1}
              inputMode="numeric"
              value={form.price}
              onChange={(e) => set("price", e.target.value)}
              className={FIELD_CLASS}
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
          <Field label="カテゴリ">
            <select
              value={form.category}
              onChange={(e) => set("category", e.target.value as typeof form.category)}
              className={FIELD_CLASS}
            >
              {PRODUCT_CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {PRODUCT_CATEGORY_LABELS[c]}
                </option>
              ))}
            </select>
          </Field>
          <Field label="生産者" className="sm:col-span-2">
            <select
              value={form.producer_id}
              onChange={(e) => set("producer_id", e.target.value)}
              className={FIELD_CLASS}
            >
              {producers.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.is_placeholder
                    ? `${p.name} ※運営から発送`
                    : `${p.name} (${p.origin ?? "—"} / 発送元: ${p.ship_from_prefecture ?? "—"})${p.is_active ? "" : " ※無効"}`}
                </option>
              ))}
            </select>
            {selectedProducer && !selectedProducer.is_placeholder ? (
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
          <div className="flex items-end">
            <label className="flex w-full cursor-pointer items-center justify-between gap-3 rounded-xl border border-border-soft px-3 py-2.5">
              <span className="text-[14px] font-medium text-text-primary">
                {form.is_published ? "公開中" : "非公開"}
              </span>
              <input
                type="checkbox"
                checked={form.is_published}
                onChange={(e) => set("is_published", e.target.checked)}
                className="h-5 w-5 accent-[var(--brand)]"
              />
            </label>
          </div>
          <Field label={form.is_published ? "内容量・規格 (公開時は必須)" : "内容量・規格"} className="sm:col-span-2">
            <input
              required={form.is_published}
              value={form.content_volume}
              onChange={(e) => set("content_volume", e.target.value)}
              className={FIELD_CLASS}
              placeholder="例: 500g×2袋"
            />
          </Field>
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
