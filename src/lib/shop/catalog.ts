import type { ShopCatalog } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * 公開ショップの商品一覧を取得する (サーバー専用)。
 * 稼働中の代理店の紹介リンクでなければ { valid: false } が返る。
 * 代理店名・正確な在庫数は RPC 側で返さない設計 (0011 / 0013)。
 */
export async function fetchShopCatalog(
  agentPublicId: string,
  productId: string | null = null,
): Promise<ShopCatalog> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("treemerce_shop_products", {
    p_agent_public_id: agentPublicId,
    p_product_id: productId,
  });
  if (error || !data) return { valid: false };
  return data as ShopCatalog;
}
