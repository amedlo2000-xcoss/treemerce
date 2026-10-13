import type { ProductItemKind, ProductSalesStatus } from "@/lib/domain/types";

/** 商品の販売状態 (0023) */
export const SALES_STATUSES: ProductSalesStatus[] = ["unpublished", "preparing", "on_sale"];

export const SALES_STATUS_LABELS: Record<ProductSalesStatus, string> = {
  unpublished: "非公開",
  preparing: "準備中",
  on_sale: "公開中",
};

export const SALES_STATUS_BADGE: Record<ProductSalesStatus, "neutral" | "amber" | "green"> = {
  unpublished: "neutral",
  preparing: "amber",
  on_sale: "green",
};

/** 物品 / サービス (0023) */
export const ITEM_KIND_LABELS: Record<ProductItemKind, string> = {
  goods: "物品",
  service: "サービス",
};

/** 価格・項目が決まっていないときの表示 (0 円・無料などで代用しない) */
export const UNDECIDED = "未定";

/**
 * 物品とサービスで切り替える項目名。サービスは発送情報を持たないため、
 * 発送元は表示しない (shipFrom = null)。
 */
export function productFieldLabels(kind: ProductItemKind) {
  return kind === "service"
    ? { volume: "提供単位", producer: "提供者名", origin: "提供場所", shipFrom: null, leadTime: "予約方法" }
    : { volume: "内容量", producer: "生産者名", origin: "産地", shipFrom: "発送元", leadTime: "発送目安" };
}
