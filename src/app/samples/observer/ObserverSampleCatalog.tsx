"use client";

import { X } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import {
  CATALOG_CATEGORIES,
  CATALOG_CATEGORY_ALL,
  type CatalogCategory,
  isServiceCategory,
} from "@/lib/domain/catalog-categories";
import {
  OBSERVER_SAMPLES,
  SAMPLE_LISTING_REASON,
  SAMPLE_UNDECIDED,
  type ObserverSample,
} from "@/lib/samples/observer-samples";

import { SampleIllustration } from "./SampleIllustration";

type Filter = CatalogCategory | typeof CATALOG_CATEGORY_ALL;

function SampleLabels() {
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="rounded-full border border-text-secondary/40 px-2 py-0.5 text-[11px] font-semibold tracking-wider text-text-secondary">
        SAMPLE
      </span>
      <span className="rounded-full bg-brand-soft px-2 py-0.5 text-[11px] font-semibold text-brand">
        オブザーバー特典付き
      </span>
    </div>
  );
}

/** 詳細の項目。施術などのサービスは呼び方を変え、発送情報は出さない。値は架空のものを作らず「未定」。 */
function detailRows(sample: ObserverSample): { label: string; value: string }[] {
  const service = isServiceCategory(sample.category);
  const rows = [
    { label: "商品名", value: sample.name },
    { label: "商品の種類", value: sample.type },
    { label: "カテゴリー", value: sample.category },
    { label: "説明", value: sample.description },
    { label: "希望販売価格", value: SAMPLE_UNDECIDED },
    { label: service ? "提供単位" : "内容量", value: SAMPLE_UNDECIDED },
    { label: service ? "提供者名" : "生産者名", value: SAMPLE_UNDECIDED },
    { label: service ? "提供場所" : "産地", value: SAMPLE_UNDECIDED },
  ];
  if (!service) rows.push({ label: "発送元", value: SAMPLE_UNDECIDED });
  rows.push(
    { label: service ? "予約方法" : "発送目安", value: SAMPLE_UNDECIDED },
    { label: service ? "提供者の電話番号" : "生産者の電話番号", value: SAMPLE_UNDECIDED },
    { label: "掲載理由", value: SAMPLE_LISTING_REASON },
  );
  return rows;
}

function SampleDetailDialog({ sample, onClose }: { sample: ObserverSample; onClose: () => void }) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const titleId = `sample-dialog-title-${sample.id}`;

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
            <SampleLabels />
            <h2 id={titleId} className="mt-2 break-words text-[19px] font-bold leading-snug text-text-primary">
              {sample.name}
            </h2>
            {sample.reading ? <p className="text-[12px] text-text-secondary">{sample.reading}</p> : null}
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
          <SampleIllustration id={sample.id} className="mx-auto aspect-[4/3] w-full max-w-sm rounded-2xl" />
          <dl className="mt-4 divide-y divide-border-soft">
            {detailRows(sample).map((row) => (
              <div key={row.label} className="grid grid-cols-[7.5rem_minmax(0,1fr)] gap-3 py-2.5">
                <dt className="text-[13px] text-text-secondary">{row.label}</dt>
                <dd className="break-words text-[14px] leading-6 text-text-primary">{row.value}</dd>
              </div>
            ))}
          </dl>
          <p className="mt-4 rounded-2xl bg-surface-muted px-3.5 py-3 text-[12px] leading-5 text-text-secondary">
            企画段階のサンプルです。実際の販売・提供を案内するものではありません。
          </p>
        </div>
      </div>
    </div>
  );
}

/**
 * オブザーバー特典付き製品・サービスのサンプル一覧 (カテゴリ絞り込み + カード + 詳細ダイアログ)。
 * 購入・予約・問い合わせの操作は置かない。データはローカルの固定データのみ (DB には接続しない)。
 */
export function ObserverSampleCatalog() {
  const [filter, setFilter] = useState<Filter>(CATALOG_CATEGORY_ALL);
  const [openId, setOpenId] = useState<string | null>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);

  // カテゴリごとの件数はデータから計算する
  const counts = useMemo(() => {
    const map = new Map<CatalogCategory, number>();
    for (const s of OBSERVER_SAMPLES) map.set(s.category, (map.get(s.category) ?? 0) + 1);
    return map;
  }, []);

  const filters: { key: Filter; count: number }[] = [
    { key: CATALOG_CATEGORY_ALL, count: OBSERVER_SAMPLES.length },
    ...CATALOG_CATEGORIES.filter((c) => (counts.get(c) ?? 0) > 0).map((c) => ({ key: c, count: counts.get(c) ?? 0 })),
  ];

  const visible =
    filter === CATALOG_CATEGORY_ALL ? OBSERVER_SAMPLES : OBSERVER_SAMPLES.filter((s) => s.category === filter);
  const openSample = OBSERVER_SAMPLES.find((s) => s.id === openId) ?? null;

  const close = useCallback(() => {
    setOpenId(null);
    // 閉じたら「詳細を見る」ボタンにフォーカスを戻す
    requestAnimationFrame(() => triggerRef.current?.focus());
  }, []);

  return (
    <>
      <section aria-labelledby="sample-filter-heading" className="space-y-3">
        <h2 id="sample-filter-heading" className="px-1 text-[13px] font-semibold tracking-wide text-text-secondary">
          カテゴリで絞り込む
        </h2>
        <div className="flex flex-wrap gap-2" role="group" aria-label="カテゴリ">
          {filters.map(({ key, count }) => {
            const selected = key === filter;
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
                {key}
                <span className={`text-[12px] tabular-nums ${selected ? "text-brand" : "text-text-secondary"}`}>
                  {count}
                </span>
              </button>
            );
          })}
        </div>
        <p className="px-1 text-[13px] text-text-secondary" aria-live="polite">
          {filter}：{visible.length} 件を表示中
        </p>
      </section>

      <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {visible.map((s) => (
          <li key={s.id} data-sample-id={s.id}>
            <article className="flex h-full flex-col overflow-hidden rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)]">
              <SampleIllustration id={s.id} className="aspect-[4/3]" />
              <div className="flex flex-1 flex-col gap-2 p-4">
                <SampleLabels />
                <p className="text-[12px] text-text-secondary">{s.category}</p>
                <div>
                  <h3 className="break-words text-[17px] font-bold leading-snug text-text-primary">{s.name}</h3>
                  {s.reading ? <p className="text-[12px] text-text-secondary">{s.reading}</p> : null}
                </div>
                <p className="text-[13px] font-medium text-text-primary">{s.type}</p>
                <p className="text-[13px] leading-6 text-text-secondary">{s.description}</p>
                <div className="mt-auto space-y-3 pt-2">
                  <p className="text-[14px] text-text-primary">
                    <span className="text-text-secondary">販売価格：</span>
                    <span className="font-semibold">{SAMPLE_UNDECIDED}</span>
                  </p>
                  <button
                    type="button"
                    onClick={(e) => {
                      triggerRef.current = e.currentTarget;
                      setOpenId(s.id);
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

      {openSample ? <SampleDetailDialog sample={openSample} onClose={close} /> : null}
    </>
  );
}
