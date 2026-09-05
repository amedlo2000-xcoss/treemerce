import { failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";

/**
 * STEP5: 商流マップ (読み取り専用)。
 *
 * 部分木の算出と匿名化は全て `treemerce_commerce_map` (SECURITY DEFINER / STABLE)
 * の中で行われる。ここでは根を指定しない = 常にログイン代理店自身が根になる。
 *
 * CASE11: 自分担当は実名+購入商品、傘下他代理店担当は匿名ノード + 件数のみ
 * CASE12: 兄弟枝は再帰CTEの構造上入らない
 * CASE13: upline (招待元) も入らない
 * CASE14: STABLE 関数なので書込みが構造的に発生しない
 * CASE15: レスポンス自体に他代理店担当顧客の実データが含まれない
 */
export async function GET() {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_commerce_map", {
    p_root_agent_id: null,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
