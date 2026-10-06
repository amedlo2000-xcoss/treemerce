import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { AGENT_STATUSES, type AgentStatus } from "@/lib/domain/enums";

type Body = { agent_id?: string; status?: string; reason?: string };

/**
 * 代理店の利用開始状態 (status) の変更。super_admin 専用。
 * 絶対原則2: 登録経路 (invited_by) はここでも変更できない。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<Body>(request);
  if (!body?.agent_id) {
    return fail("TREEMERCE_INVALID_INPUT", "代理店IDは必須です。", 400);
  }
  if (!body.status || !(AGENT_STATUSES as readonly string[]).includes(body.status)) {
    return fail("TREEMERCE_INVALID_INPUT", "ステータスの指定が不正です。", 400);
  }
  if (!body.reason?.trim()) {
    return fail("TREEMERCE_REASON_REQUIRED", "変更理由は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_set_agent_status", {
    p_agent_id: body.agent_id,
    p_status: body.status as AgentStatus,
    p_reason: body.reason.trim(),
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
