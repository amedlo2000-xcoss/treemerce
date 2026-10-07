import Link from "next/link";

import { Notice, formatYen } from "@/components/ui";
import { EmptyState, MobilePageHeader } from "@/components/mobile/primitives";
import { PRODUCT_CATEGORY_LABELS } from "@/lib/domain/enums";
import { fetchShopCatalog } from "@/lib/shop/catalog";

import { InvalidShopLink, ProductImage, StockLabel } from "./ShopParts";

/** 公開ショップ: 商品一覧 (未ログイン可)。 */
export default async function ShopPage({
  params,
}: {
  params: Promise<{ agentPublicId: string }>;
}) {
  const { agentPublicId } = await params;
  const catalog = await fetchShopCatalog(agentPublicId);

  if (!catalog.valid) return <InvalidShopLink />;

  return (
    <>
      <MobilePageHeader title="商品一覧" />

      {!catalog.accepting_orders ? (
        <Notice tone="warning">現在ご注文の受付を停止しております。</Notice>
      ) : null}

      {catalog.products.length === 0 ? (
        <EmptyState title="現在お取り扱いの商品はありません" />
      ) : (
        <ul className="grid grid-cols-2 gap-3 md:grid-cols-3 md:gap-4 lg:grid-cols-4">
          {catalog.products.map((p) => (
            <li key={p.id}>
              <Link
                href={`/shop/${agentPublicId}/products/${p.id}`}
                className="group flex h-full flex-col overflow-hidden rounded-[20px] border border-border-soft bg-surface shadow-[var(--shadow-card)] transition-colors hover:border-brand/40"
              >
                <ProductImage path={p.image_path} className="aspect-square" />
                <div className="flex flex-1 flex-col gap-1 p-3">
                  <span className="text-[11px] text-text-secondary">
                    {PRODUCT_CATEGORY_LABELS[p.category] ?? p.category}
                  </span>
                  <span className="line-clamp-2 text-[14px] font-semibold leading-5 text-text-primary group-hover:text-brand">
                    {p.name}
                  </span>
                  {p.producer ? (
                    <span className="line-clamp-1 text-[11px] text-text-secondary">
                      {p.producer.name} ・ {p.producer.origin}
                    </span>
                  ) : null}
                  {p.content_volume ? (
                    <span className="line-clamp-1 text-[11px] text-text-secondary">{p.content_volume}</span>
                  ) : null}
                  <span className="mt-auto flex items-end justify-between gap-2 pt-1">
                    <span className="text-[16px] font-bold tabular-nums text-text-primary">
                      {formatYen(Number(p.price))}
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
