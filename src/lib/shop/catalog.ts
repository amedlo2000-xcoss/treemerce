import type { ShopCatalog } from "@/lib/domain/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * 公開ショップの商品一覧を取得する (サーバー専用)。
 * 稼働中の代理店の紹介リンクでなければ { valid: false } が返る。
 * agentPublicId = null は、どのオブザーバーにも紐づかない運営のショップ (/shop、0037)。
 * 代理店名・正確な在庫数・予定価格は RPC 側で返さない設計 (0011 / 0013 / 0023)。
 *
 * includePreparing = true で「準備中」(価格未定・注文不可) の商品も含める (一覧・詳細の表示用)。
 * 注文手続き (カート・注文確認) は既定の false で、注文できる商品だけを扱う。
 */
export async function fetchShopCatalog(
  agentPublicId: string | null,
  productId: string | null = null,
  options: { includePreparing?: boolean } = {},
): Promise<ShopCatalog> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("treemerce_shop_products", {
    p_agent_public_id: agentPublicId,
    p_product_id: productId,
    p_include_preparing: options.includePreparing ?? false,
  });
  if (error || !data) return { valid: false };
  return data as ShopCatalog;
}

/**
 * ショップの上部に出す、紹介リンクのオブザーバーの表示名 (公開プロフィールの RPC、表示名と公開IDのみ)。
 * 見つからなければ null。
 */
export async function fetchShopOwnerName(agentPublicId: string): Promise<string | null> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("treemerce_agent_public_profile", { p_public_id: agentPublicId });
  if (error || !data) return null;
  const profile = data as { found?: boolean; display_name?: string };
  return profile.found && profile.display_name ? profile.display_name : null;
}
