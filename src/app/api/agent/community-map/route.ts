import { failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";

/**
 * STEP7: 代理店コミュニティマップ。
 * CASE9: 代理店ノードと招待経路のエッジのみ。customers は構造上一切含まれない。
 */
export async function GET() {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_community_map", {
    p_root_agent_id: null,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
