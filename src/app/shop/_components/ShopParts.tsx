import { EmptyState } from "@/components/mobile/primitives";
import { ProductPlaceholder } from "@/components/ProductPlaceholder";
import type { ProductItemKind, ShopProduct } from "@/lib/domain/types";
import { productImageUrl } from "@/lib/storage";

/** 商品画像。画像がなければ仮のイラスト (「イメージ」の表示付き) を出す。 */
export function ProductImage({
  path,
  placeholderKey = null,
  itemKind = "goods",
  className = "",
}: {
  path: string | null;
  placeholderKey?: string | null;
  itemKind?: ProductItemKind;
  className?: string;
}) {
  const src = productImageUrl(path);
  if (!src) {
    return <ProductPlaceholder placeholderKey={placeholderKey} itemKind={itemKind} className={className} />;
  }
  return (
    <div className={`flex items-center justify-center overflow-hidden bg-surface-muted ${className}`}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt="" className="h-full w-full object-cover" />
    </div>
  );
}

export function StockLabel({ product }: { product: ShopProduct }) {
  if (!product.orderable) {
    return <span className="text-[12px] font-semibold text-warning">準備中</span>;
  }
  if (!product.in_stock) {
    return <span className="text-[12px] font-semibold text-danger">在庫切れ</span>;
  }
  if (product.low_stock) {
    return <span className="text-[12px] font-semibold text-warning">残りわずか</span>;
  }
  return <span className="text-[12px] text-success">在庫あり</span>;
}

/** ショップを表示できないとき。direct = 運営のショップ (/shop) */
export function InvalidShopLink({ direct = false }: { direct?: boolean }) {
  if (direct) {
    return (
      <EmptyState
        title="ショップは現在ご利用いただけません"
        description="お手数ですが、時間をおいて再度アクセスしてください。"
      />
    );
  }
  return (
    <EmptyState
      title="このリンクは現在ご利用いただけません"
      description="お手数ですが、ご案内を受けた方に最新のリンクをご確認ください。"
    />
  );
}

/** 運営のショップ (/shop) の名前 */
export const DIRECT_SHOP_TITLE = "5D PLUS COMMUNITY ショップ";
