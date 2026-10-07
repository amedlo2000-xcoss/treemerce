import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Notice, formatYen } from "@/components/ui";
import { StatusPill, Surface } from "@/components/mobile/primitives";
import { PRODUCT_CATEGORY_LABELS } from "@/lib/domain/enums";
import { fetchShopCatalog } from "@/lib/shop/catalog";

import { InvalidShopLink, ProductImage, StockLabel } from "../../ShopParts";
import { AddToCart } from "./AddToCart";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 公開ショップ: 商品詳細 (未ログイン可)。非公開の商品は表示されない。 */
export default async function ShopProductPage({
  params,
}: {
  params: Promise<{ agentPublicId: string; productId: string }>;
}) {
  const { agentPublicId, productId } = await params;
  if (!UUID.test(productId)) notFound();

  const catalog = await fetchShopCatalog(agentPublicId, productId);
  if (!catalog.valid) return <InvalidShopLink />;

  const product = catalog.products[0];
  if (!product) notFound();

  return (
    <>
      <Link
        href={`/shop/${agentPublicId}`}
        className="inline-flex items-center gap-1 text-[14px] font-medium text-text-secondary hover:text-text-primary"
      >
        <ChevronLeft size={18} />
        商品一覧
      </Link>

      <div className="space-y-5 md:grid md:grid-cols-2 md:items-start md:gap-8 md:space-y-0">
        <ProductImage
          path={product.image_path}
          className="aspect-square rounded-[24px] border border-border-soft"
        />

        <div className="space-y-5">
          <div className="space-y-2">
            <StatusPill tone="brand">
              {PRODUCT_CATEGORY_LABELS[product.category] ?? product.category}
            </StatusPill>
            <h1 className="text-[24px] font-bold leading-tight text-text-primary">{product.name}</h1>
            {product.producer ? (
              <p className="text-[13px] text-text-secondary">
                {product.producer.name} ・ {product.producer.origin}
              </p>
            ) : null}
            <div className="flex items-end gap-3">
              <span className="text-[28px] font-bold tabular-nums text-text-primary">
                {formatYen(Number(product.price))}
              </span>
              <span className="pb-1.5 text-[12px] text-text-secondary">税込</span>
              <span className="pb-1.5">
                <StockLabel product={product} />
              </span>
            </div>
            {catalog.shipping_fee > 0 ? (
              <p className="text-[12px] text-text-secondary">
                送料 {formatYen(Number(catalog.shipping_fee))} (1回のご注文につき)
              </p>
            ) : (
              <p className="text-[12px] text-text-secondary">送料無料</p>
            )}
          </div>

          {catalog.accepting_orders ? (
            <Surface>
              <AddToCart
                agentPublicId={agentPublicId}
                productId={product.id}
                maxQuantity={product.max_quantity}
                disabled={!product.in_stock}
              />
            </Surface>
          ) : (
            <Notice tone="warning">現在ご注文の受付を停止しております。</Notice>
          )}

          {product.description ? (
            <Surface>
              <h2 className="mb-2 text-[14px] font-semibold text-text-primary">商品説明</h2>
              <p className="whitespace-pre-wrap text-[14px] leading-7 text-text-primary">
                {product.description}
              </p>
            </Surface>
          ) : null}

          <Surface>
            <h2 className="mb-1 text-[14px] font-semibold text-text-primary">商品情報</h2>
            <dl className="divide-y divide-border-soft text-[14px]">
              {(
                [
                  ["価格", `${formatYen(Number(product.price))} (税込)`],
                  ["内容量・規格", product.content_volume],
                  ["原材料・成分", product.ingredients],
                  ["賞味期限 / 使用期限の目安", product.best_before_note],
                  ["生産者", product.producer?.name],
                  ["産地", product.producer?.origin],
                  ["発送元", product.producer?.ship_from_prefecture],
                  ["発送の目安", product.producer?.ship_lead_time],
                ] as [string, string | null | undefined][]
              )
                .filter(([, value]) => value)
                .map(([label, value]) => (
                  <div key={label} className="flex gap-4 py-2.5">
                    <dt className="w-32 shrink-0 text-[13px] text-text-secondary">{label}</dt>
                    <dd className="min-w-0 whitespace-pre-wrap break-words text-text-primary">{value}</dd>
                  </div>
                ))}
            </dl>
            {product.producer ? (
              <p className="mt-2 text-[12px] leading-5 text-text-secondary">
                この商品は生産者から直接お届けします。複数の生産者の商品をご注文の場合は、別々に届きます。
              </p>
            ) : null}
          </Surface>

          <Surface>
            <h2 className="mb-1 text-[14px] font-semibold text-text-primary">販売者</h2>
            <p className="text-[14px] text-text-primary">{catalog.seller_name ?? "運営事務局"}</p>
            <p className="mt-1 text-[12px] leading-5 text-text-secondary">
              ご注文・お支払い・お問い合わせの窓口は販売者です。代金は販売者の口座へお振込みください。
            </p>
            <Link
              href="/legal/tokushoho"
              className="mt-2 inline-block text-[13px] font-semibold text-brand hover:underline"
            >
              特定商取引法に基づく表記
            </Link>
          </Surface>
        </div>
      </div>
    </>
  );
}
