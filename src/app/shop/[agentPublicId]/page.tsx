import Link from "next/link";

import { Notice, formatYen } from "@/components/ui";
import { EmptyState, MobilePageHeader } from "@/components/mobile/primitives";
import { UNDECIDED } from "@/lib/domain/product-labels";
import { fetchShopCatalog } from "@/lib/shop/catalog";

import { InvalidShopLink, ProductImage, StockLabel } from "./ShopParts";

/**
 * 公開ショップ: 商品一覧 (未ログイン可)。
 * 公開中に加えて「準備中」(価格未定・注文不可) の商品も表示する。カテゴリで絞り込める (?category=キー)。
 */
export default async function ShopPage({
  params,
  searchParams,
}: {
  params: Promise<{ agentPublicId: string }>;
  searchParams: Promise<{ category?: string }>;
}) {
  const { agentPublicId } = await params;
  const { category } = await searchParams;
  const catalog = await fetchShopCatalog(agentPublicId, null, { includePreparing: true });

  if (!catalog.valid) return <InvalidShopLink />;

  // 商品のある (有効な) カテゴリだけを絞り込みに出す。並び順は RPC の並び (カテゴリ順) のまま
  const categories: { code: string; name: string; count: number }[] = [];
  for (const p of catalog.products) {
    const entry = categories.find((c) => c.code === p.category_code);
    if (entry) entry.count += 1;
    else categories.push({ code: p.category_code, name: p.category_name, count: 1 });
  }
  const active = categories.some((c) => c.code === category) ? category : undefined;
  const products = active ? catalog.products.filter((p) => p.category_code === active) : catalog.products;

  const chip = (selected: boolean) =>
    `inline-flex items-center gap-1.5 rounded-2xl border px-3.5 py-2 text-[14px] font-medium transition-colors ${
      selected ? "border-brand bg-brand-soft text-brand" : "border-border-soft bg-surface text-text-primary hover:bg-surface-muted"
    }`;

  return (
    <>
      <MobilePageHeader title="商品一覧" />

      {!catalog.accepting_orders ? (
        <Notice tone="warning">現在ご注文の受付を停止しております。</Notice>
      ) : null}

      {categories.length > 1 ? (
        <nav aria-label="カテゴリで絞り込み" className="flex flex-wrap gap-2">
          <Link href={`/shop/${agentPublicId}`} aria-current={!active ? "page" : undefined} className={chip(!active)}>
            すべて
            <span className="text-[12px] tabular-nums">{catalog.products.length}</span>
          </Link>
          {categories.map((c) => (
            <Link
              key={c.code}
              href={`/shop/${agentPublicId}?category=${encodeURIComponent(c.code)}`}
              aria-current={active === c.code ? "page" : undefined}
              className={chip(active === c.code)}
            >
              {c.name}
              <span className="text-[12px] tabular-nums">{c.count}</span>
            </Link>
          ))}
        </nav>
      ) : null}

      {products.length === 0 ? (
        <EmptyState title="現在お取り扱いの商品はありません" />
      ) : (
        <ul className="grid grid-cols-2 gap-3 md:grid-cols-3 md:gap-4 lg:grid-cols-4">
          {products.map((p) => (
            <li key={p.id}>
              <Link
                href={`/shop/${agentPublicId}/products/${p.id}`}
                className="group flex h-full flex-col overflow-hidden rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)] transition-colors hover:border-brand/40"
              >
                <ProductImage
                  path={p.image_path}
                  placeholderKey={p.placeholder_key}
                  itemKind={p.item_kind}
                  className="aspect-square"
                />
                <div className="flex flex-1 flex-col gap-1 p-3">
                  <span className="text-[11px] text-text-secondary">{p.category_name}</span>
                  <span className="line-clamp-2 text-[14px] font-semibold leading-5 text-text-primary group-hover:text-brand">
                    {p.name}
                  </span>
                  {p.has_observer_benefit ? (
                    <span className="w-fit rounded-full bg-brand-soft px-2 py-0.5 text-[10px] font-semibold text-brand">
                      オブザーバー特典付き
                    </span>
                  ) : null}
                  {p.producer ? (
                    <span className="line-clamp-1 text-[11px] text-text-secondary">
                      {p.producer.name}
                      {p.producer.origin ? ` ・ ${p.producer.origin}` : ""}
                    </span>
                  ) : null}
                  {p.content_volume ? (
                    <span className="line-clamp-1 text-[11px] text-text-secondary">{p.content_volume}</span>
                  ) : null}
                  <span className="mt-auto flex items-end justify-between gap-2 pt-1">
                    <span className="text-[16px] font-bold tabular-nums text-text-primary">
                      {p.orderable && p.price != null ? formatYen(Number(p.price)) : `販売価格：${UNDECIDED}`}
                    </span>
                    <StockLabel product={p} />
                  </span>
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
