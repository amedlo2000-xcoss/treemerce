import { fail, failFromPostgrest, ok, readJson, requireAgentApi } from "@/lib/api/http";
import { UUID } from "@/lib/api/submission-input";

/** 取り下げ (本人の下書き・差し戻しのみ)。申請は削除されず、取り下げとして残る。 */
export async function POST(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const body = await readJson<{ reason?: unknown }>(request);
  const reason = typeof body?.reason === "string" && body.reason.trim() ? body.reason.trim() : null;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_withdraw_my_submission", {
    p_submission_id: submissionId,
    p_reason: reason,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
