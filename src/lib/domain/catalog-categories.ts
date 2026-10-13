/**
 * 製品・サービスのカテゴリ名 (表示順)。
 *
 * 現在はオブザーバー特典付き製品一覧 (/observer-products) だけが使う。
 * 本番の商品カテゴリを設計するときに再利用できるよう、カテゴリ名はこのファイルにだけ定義する。
 *
 * 注意: DB の商品カテゴリ (public.product_category / enums.ts の PRODUCT_CATEGORIES) とは別物で、
 * まだ DB・RPC・商品データとは連動していない。本番に取り込む場合は、DB の列挙型の変更と
 * 合わせて設計し直すこと。
 */
export const CATALOG_CATEGORIES = [
  "食品・飲料",
  "香り・キャンドル",
  "五次元結晶",
  "施術・体験",
  "アクセサリー",
  "アート",
  "生活雑貨",
  "文具",
] as const;

export type CatalogCategory = (typeof CATALOG_CATEGORIES)[number];

/** 絞り込みで「すべて」を表す値 (カテゴリ名とは重ならない) */
export const CATALOG_CATEGORY_ALL = "すべて";

/**
 * 物の発送を伴わない「施術・体験」などのサービス系カテゴリ。
 * 詳細表示で「生産者名 → 提供者名」「産地 → 提供場所」「発送目安 → 予約方法」に切り替え、
 * 発送元などの発送情報は表示しない。
 */
export const SERVICE_CATALOG_CATEGORIES: readonly CatalogCategory[] = ["施術・体験"];

export function isServiceCategory(category: CatalogCategory) {
  return SERVICE_CATALOG_CATEGORIES.includes(category);
}
