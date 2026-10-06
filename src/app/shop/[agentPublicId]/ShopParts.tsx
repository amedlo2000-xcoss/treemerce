import { ImageOff } from "lucide-react";

import { EmptyState } from "@/components/mobile/primitives";
import type { ShopProduct } from "@/lib/domain/types";
import { productImageUrl } from "@/lib/storage";

export function ProductImage({
  path,
  className = "",
}: {
  path: string | null;
  className?: string;
}) {
  const src = productImageUrl(path);
  return (
    <div
      className={`flex items-center justify-center overflow-hidden bg-surface-muted ${className}`}
    >
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt="" className="h-full w-full object-cover" />
      ) : (
        <ImageOff size={28} className="text-text-secondary" />
      )}
    </div>
  );
}

export function StockLabel({ product }: { product: ShopProduct }) {
  if (!product.in_stock) {
    return <span className="text-[12px] font-semibold text-danger">在庫切れ</span>;
  }
  if (product.low_stock) {
    return <span className="text-[12px] font-semibold text-warning">残りわずか</span>;
  }
  return <span className="text-[12px] text-success">在庫あり</span>;
}

export function InvalidShopLink() {
  return (
    <EmptyState
      title="このリンクは現在ご利用いただけません"
      description="お手数ですが、ご案内を受けた方に最新のリンクをご確認ください。"
    />
  );
}
