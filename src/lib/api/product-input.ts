import { PRODUCT_CATEGORIES, type ProductCategory } from "@/lib/domain/enums";

export type ProductInput = {
  p_name: string;
  p_price: number;
  p_stock: number;
  p_is_published: boolean;
  p_category: ProductCategory;
  p_description: string | null;
  p_image_path: string | null;
  p_sku: string | null;
  p_sort_order: number;
  p_reason: string | null;
  p_producer_id: string | null;
  p_content_volume: string | null;
  p_ingredients: string | null;
  p_best_before_note: string | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 商品フォームの入力を treemerce_admin_upsert_product の引数に整える。
 * 値の妥当性は DB 側 (0011 / 0015) でも必ず再検証される。ここは早期に分かりやすいエラーを返すため。
 */
export function parseProductInput(
  body: Record<string, unknown> | null,
): { input: ProductInput } | { error: string } {
  if (!body) return { error: "入力内容が不正です。" };

  const name = typeof body.name === "string" ? body.name.trim() : "";
  if (!name) return { error: "商品名は必須です。" };

  const price = Number(body.price);
  if (!Number.isFinite(price) || price < 0) return { error: "価格は 0 以上の数値で入力してください。" };

  const stock = Number(body.stock);
  if (!Number.isInteger(stock) || stock < 0) return { error: "在庫は 0 以上の整数で入力してください。" };

  const sortOrder = body.sort_order == null || body.sort_order === "" ? 0 : Number(body.sort_order);
  if (!Number.isInteger(sortOrder)) return { error: "表示順は整数で入力してください。" };

  const category = (PRODUCT_CATEGORIES as readonly string[]).includes(String(body.category))
    ? (body.category as ProductCategory)
    : "other";

  const text = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);
  // 0015 の追加項目: 文字列なら送る (空文字 = 空にする)、未指定なら null (= DB 側で変更しない)
  const keepable = (v: unknown) => (typeof v === "string" ? v.trim() : null);

  const producerId = text(body.producer_id);
  if (producerId && !UUID.test(producerId)) return { error: "生産者の指定が不正です。" };

  return {
    input: {
      p_name: name,
      p_price: price,
      p_stock: stock,
      p_is_published: body.is_published === true,
      p_category: category,
      p_description: text(body.description),
      p_image_path: text(body.image_path),
      p_sku: text(body.sku),
      p_sort_order: sortOrder,
      p_reason: text(body.reason),
      p_producer_id: producerId,
      p_content_volume: keepable(body.content_volume),
      p_ingredients: keepable(body.ingredients),
      p_best_before_note: keepable(body.best_before_note),
    },
  };
}
