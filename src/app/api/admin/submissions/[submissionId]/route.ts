import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID, parseReason, parseSubmissionInput } from "@/lib/api/submission-input";

/**
 * 代行の申請の保存 (super_admin 専用・代行の申請の下書き・差し戻しのみ, 0021)。
 * 代理店本人が作成した申請は DB 側で拒否される。agent_id を渡すと申請の代理店と一致するか確認する。
 */
export async function PUT(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const body = await readJson<Record<string, unknown>>(request);
  const parsed = parseSubmissionInput(body);
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const reason = parseReason(body?.reason);
  if ("error" in reason) return fail("TREEMERCE_INVALID_INPUT", reason.error, 400);

  const agentId = typeof body?.agent_id === "string" && UUID.test(body.agent_id) ? body.agent_id : null;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_save_proxy_submission", {
    p_agent_id: agentId,
    p_submission_id: submissionId,
    ...parsed.input,
    p_reason: reason.value,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
