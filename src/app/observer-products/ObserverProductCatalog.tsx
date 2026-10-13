"use client";

import { X } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { ProductPlaceholder } from "@/components/ProductPlaceholder";
import { formatYen } from "@/components/ui";
import { UNDECIDED, productFieldLabels } from "@/lib/domain/product-labels";
import type { CatalogCategory, PublicProduct } from "@/lib/domain/types";
import { productImageUrl } from "@/lib/storage";

const ALL = "all";

/** 掲載理由 (全商品共通の表示) */
const LISTING_REASON = "TOWAオブザーバー特典付き製品・サービスの掲載イメージを紹介するため。";

function BenefitLabel() {
  return (
    <span className="w-fit rounded-full bg-brand-soft px-2 py-0.5 text-[11px] font-semibold text-brand">
      オブザーバー特典付き
    </span>
  );
}

function ProductVisual({ product, className }: { product: PublicProduct; className: string }) {
  const src = productImageUrl(product.image_path);
  if (!src) {
    return (
      <ProductPlaceholder placeholderKey={product.placeholder_key} itemKind={product.item_kind} className={className} />
    );
  }
  return (
    <div className={`overflow-hidden bg-surface-muted ${className}`}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt="" className="h-full w-full object-cover" />
    </div>
  );
}

function priceText(product: PublicProduct) {
  return product.orderable && product.price != null ? `${formatYen(Number(product.price))} (税込)` : UNDECIDED;
}

/**
 * 詳細の項目。値は商品管理の内容を表示し、未入力は「未定」。架空の値は作らない。
 * サービスは呼び方を変え、発送元は出さない。生産者・提供者の電話番号は表示しない
 * (連絡先は super_admin 専用で、公開 RPC も返さない)。
 */
function detailRows(product: PublicProduct): { label: string; value: string }[] {
  const labels = productFieldLabels(product.item_kind);
  const rows = [
    { label: "商品名", value: product.name },
    { label: "商品の種類", value: product.product_type_label ?? UNDECIDED },
    { label: "カテゴリー", value: product.category_name },
    { label: "説明", value: product.description ?? UNDECIDED },
    { label: "希望販売価格", value: priceText(product) },
    { label: labels.volume, value: product.content_volume ?? UNDECIDED },
    { label: labels.producer, value: product.producer?.name ?? UNDECIDED },
    { label: labels.origin, value: product.producer?.origin ?? UNDECIDED },
  ];
  if (labels.shipFrom) {
    rows.push(
      { label: labels.shipFrom, value: product.producer?.ship_from_prefecture ?? UNDECIDED },
      { label: labels.leadTime, value: product.producer?.ship_lead_time ?? UNDECIDED },
    );
  } else {
    rows.push({ label: labels.leadTime, value: UNDECIDED });
  }
  rows.push({ label: "掲載理由", value: LISTING_REASON });
  return rows;
}

function ProductDetailDialog({ product, onClose }: { product: PublicProduct; onClose: () => void }) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const titleId = `observer-dialog-title-${product.id}`;

  useEffect(() => {
    closeRef.current?.focus();
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
        return;
      }
      // Tab でダイアログの外にフォーカスが出ないようにする
      if (e.key === "Tab" && dialogRef.current) {
        const focusable = dialogRef.current.querySelectorAll<HTMLElement>(
          'button, [href], [tabindex]:not([tabindex="-1"])',
        );
        if (focusable.length === 0) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = previousOverflow;
    };
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-0 sm:items-center sm:p-6"
      onClick={onClose}
      role="presentation"
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[92vh] w-full max-w-lg flex-col overflow-hidden rounded-t-[28px] bg-surface shadow-[var(--shadow-float)] sm:rounded-[24px]"
      >
        <div className="flex items-start justify-between gap-3 border-b border-border-soft px-5 py-4">
          <div className="min-w-0">
            <BenefitLabel />
            <h2 id={titleId} className="mt-2 break-words text-[19px] font-bold leading-snug text-text-primary">
              {product.name}
            </h2>
            {product.name_kana ? <p className="text-[12px] text-text-secondary">{product.name_kana}</p> : null}
          </div>
          <button
            ref={closeRef}
            type="button"
            onClick={onClose}
            aria-label="閉じる"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-text-secondary transition-colors hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-brand"
          >
            <X size={20} />
          </button>
        </div>

        <div className="overflow-y-auto px-5 pb-6 pt-4">
          <ProductVisual product={product} className="mx-auto aspect-[4/3] w-full max-w-sm rounded-2xl" />
          <dl className="mt-4 divide-y divide-border-soft">
            {detailRows(product).map((row) => (
              <div key={row.label} className="grid grid-cols-[7.5rem_minmax(0,1fr)] gap-3 py-2.5">
                <dt className="text-[13px] text-text-secondary">{row.label}</dt>
                <dd className="whitespace-pre-wrap break-words text-[14px] leading-6 text-text-primary">{row.value}</dd>
              </div>
            ))}
          </dl>
        </div>
      </div>
    </div>
  );
}

/**
 * オブザーバー特典付き製品一覧 (カテゴリ絞り込み + カード + 詳細ダイアログ)。
 * データは商品管理 (treemerce_observer_products) から読み込む。購入・予約・問い合わせの操作は置かない。
 */
export function ObserverProductCatalog({
  products,
  categories,
}: {
  products: PublicProduct[];
  categories: CatalogCategory[];
}) {
  const [filter, setFilter] = useState<string>(ALL);
  const [openId, setOpenId] = useState<string | null>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);

  // カテゴリごとの件数は商品から計算する (商品のあるカテゴリだけを並び順で出す)
  const filters = useMemo(() => {
    const counts = new Map<string, number>();
    for (const p of products) counts.set(p.category_id, (counts.get(p.category_id) ?? 0) + 1);
    return [
      { key: ALL, name: "すべて", count: products.length },
      ...categories
        .filter((c) => (counts.get(c.id) ?? 0) > 0)
        .map((c) => ({ key: c.id, name: c.name, count: counts.get(c.id) ?? 0 })),
    ];
  }, [products, categories]);

  const current = filters.find((f) => f.key === filter) ?? filters[0];
  const visible = current.key === ALL ? products : products.filter((p) => p.category_id === current.key);
  const openProduct = products.find((p) => p.id === openId) ?? null;

  const close = useCallback(() => {
    setOpenId(null);
    // 閉じたら「詳細を見る」ボタンにフォーカスを戻す
    requestAnimationFrame(() => triggerRef.current?.focus());
  }, []);

  return (
    <>
      <section aria-labelledby="observer-filter-heading" className="space-y-3">
        <h2 id="observer-filter-heading" className="px-1 text-[13px] font-semibold tracking-wide text-text-secondary">
          カテゴリで絞り込む
        </h2>
        <div className="flex flex-wrap gap-2" role="group" aria-label="カテゴリ">
          {filters.map(({ key, name, count }) => {
            const selected = key === current.key;
            return (
              <button
                key={key}
                type="button"
                aria-pressed={selected}
                onClick={() => setFilter(key)}
                className={`inline-flex items-center gap-1.5 rounded-2xl border px-3.5 py-2 text-[14px] font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand ${
                  selected
                    ? "border-brand bg-brand-soft text-brand"
                    : "border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
                }`}
              >
                {name}
                <span className={`text-[12px] tabular-nums ${selected ? "text-brand" : "text-text-secondary"}`}>
                  {count}
                </span>
              </button>
            );
          })}
        </div>
        <p className="px-1 text-[13px] text-text-secondary" aria-live="polite">
          {current.name}：{visible.length} 件を表示中
        </p>
      </section>

      {visible.length === 0 ? (
        <p className="rounded-[20px] border border-dashed border-border-soft px-6 py-12 text-center text-[14px] text-text-secondary">
          現在ご紹介している製品はありません。
        </p>
      ) : (
        <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {visible.map((p) => (
            <li key={p.id} data-product-id={p.id}>
              <article className="flex h-full flex-col overflow-hidden rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)]">
                <ProductVisual product={p} className="aspect-[4/3]" />
                <div className="flex flex-1 flex-col gap-2 p-4">
                  <BenefitLabel />
                  <p className="text-[12px] text-text-secondary">{p.category_name}</p>
                  <div>
                    <h3 className="break-words text-[17px] font-bold leading-snug text-text-primary">{p.name}</h3>
                    {p.name_kana ? <p className="text-[12px] text-text-secondary">{p.name_kana}</p> : null}
                  </div>
                  {p.product_type_label ? (
                    <p className="text-[13px] font-medium text-text-primary">{p.product_type_label}</p>
                  ) : null}
                  {p.description ? (
                    <p className="line-clamp-4 text-[13px] leading-6 text-text-secondary">{p.description}</p>
                  ) : null}
                  <div className="mt-auto space-y-3 pt-2">
                    <p className="text-[14px] text-text-primary">
                      <span className="text-text-secondary">販売価格：</span>
                      <span className="font-semibold">
                        {p.orderable && p.price != null ? formatYen(Number(p.price)) : UNDECIDED}
                      </span>
                    </p>
                    <button
                      type="button"
                      onClick={(e) => {
                        triggerRef.current = e.currentTarget;
                        setOpenId(p.id);
                      }}
                      aria-haspopup="dialog"
                      className="inline-flex w-full items-center justify-center rounded-2xl border border-border-soft bg-surface px-4 py-2.5 text-[14px] font-semibold text-text-primary transition-colors hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
                    >
                      詳細を見る
                    </button>
                  </div>
                </div>
              </article>
            </li>
          ))}
        </ul>
      )}

      {openProduct ? <ProductDetailDialog product={openProduct} onClose={close} /> : null}
    </>
  );
}
