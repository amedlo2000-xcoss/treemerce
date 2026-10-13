import type { ProductItemKind, ProductSalesStatus } from "@/lib/domain/types";

export type ProductInput = {
  p_name: string;
  p_category_id: string;
  p_sales_status: ProductSalesStatus;
  p_price: number | null;
  p_stock: number;
  p_item_kind: ProductItemKind;
  p_has_observer_benefit: boolean;
  p_product_type_label: string | null;
  p_name_kana: string | null;
  p_placeholder_key: string | null;
  p_description: string | null;
  p_image_path: string | null;
  p_sku: string | null;
  p_sort_order: number;
  p_producer_id: string | null;
  p_content_volume: string | null;
  p_ingredients: string | null;
  p_best_before_note: string | null;
  p_reason: string | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const STATUSES: ProductSalesStatus[] = ["unpublished", "preparing", "on_sale"];

/**
 * 商品フォームの入力を treemerce_admin_save_product (0023) の引数に整える。
 * フォームの全項目で置き換える。値の妥当性は DB 側でも必ず再検証される
 * (公開中は価格必須・サービスは公開中にできない・無効なカテゴリは選べない など)。
 */
export function parseProductInput(
  body: Record<string, unknown> | null,
): { input: ProductInput } | { error: string } {
  if (!body) return { error: "入力内容が不正です。" };

  const text = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

  const name = text(body.name);
  if (!name) return { error: "商品名は必須です。" };

  const categoryId = text(body.category_id);
  if (!categoryId || !UUID.test(categoryId)) return { error: "カテゴリを選択してください。" };

  const status = STATUSES.includes(body.sales_status as ProductSalesStatus)
    ? (body.sales_status as ProductSalesStatus)
    : null;
  if (!status) return { error: "販売状態を選択してください。" };

  const itemKind: ProductItemKind = body.item_kind === "service" ? "service" : "goods";
  if (itemKind === "service" && status === "on_sale") {
    return { error: "サービスは予約の仕組みができるまで公開 (注文可能) にできません。「準備中」にしてください。" };
  }

  let price: number | null = null;
  if (body.price != null && body.price !== "") {
    price = Number(body.price);
    if (!Number.isInteger(price) || price < 0 || price >= 100_000_000) {
      return { error: "価格は 0 円以上 1 億円未満の整数で入力してください。" };
    }
  }
  if (status === "on_sale" && price == null) {
    return { error: "公開中にするには販売価格が必要です (価格が未定なら「準備中」にしてください)。" };
  }

  const stock = Number(body.stock ?? 0);
  if (!Number.isInteger(stock) || stock < 0) return { error: "在庫は 0 以上の整数で入力してください。" };

  const sortOrder = body.sort_order == null || body.sort_order === "" ? 0 : Number(body.sort_order);
  if (!Number.isInteger(sortOrder)) return { error: "表示順は整数で入力してください。" };

  const producerId = text(body.producer_id);
  if (producerId && !UUID.test(producerId)) return { error: "生産者の指定が不正です。" };

  const placeholderKey = text(body.placeholder_key);
  if (placeholderKey && !/^[a-z0-9-]{1,40}$/.test(placeholderKey)) return { error: "イラストの種類が不正です。" };

  return {
    input: {
      p_name: name,
      p_category_id: categoryId,
      p_sales_status: status,
      p_price: price,
      p_stock: stock,
      p_item_kind: itemKind,
      p_has_observer_benefit: body.has_observer_benefit === true,
      p_product_type_label: text(body.product_type_label),
      p_name_kana: text(body.name_kana),
      p_placeholder_key: placeholderKey,
      p_description: text(body.description),
      p_image_path: text(body.image_path),
      p_sku: text(body.sku),
      p_sort_order: sortOrder,
      p_producer_id: producerId,
      p_content_volume: text(body.content_volume),
      p_ingredients: text(body.ingredients),
      p_best_before_note: text(body.best_before_note),
      p_reason: text(body.reason),
    },
  };
}
