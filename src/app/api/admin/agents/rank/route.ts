import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { AGENT_RANKS } from "@/lib/domain/rewards";

type Body = { agent_id?: string; rank?: string; reason?: string };

/**
 * オブザーバーのランク変更 (0033 treemerce_admin_set_agent_rank)。super_admin 専用。
 * 理由は必須。変更前後と理由は DB 側で監査ログに残る。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<Body>(request);
  if (!body?.agent_id) {
    return fail("TREEMERCE_INVALID_INPUT", "オブザーバーIDは必須です。", 400);
  }
  if (!body.rank || !(AGENT_RANKS as readonly string[]).includes(body.rank)) {
    return fail("TREEMERCE_INVALID_INPUT", "ランクの指定が不正です。", 400);
  }
  const reason = body.reason?.trim();
  if (!reason) {
    return fail("TREEMERCE_REASON_REQUIRED", "変更理由は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_set_agent_rank", {
    p_agent_id: body.agent_id,
    p_rank: body.rank,
    p_reason: reason,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
