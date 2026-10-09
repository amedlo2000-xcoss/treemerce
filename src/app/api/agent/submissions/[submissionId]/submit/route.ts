import { fail, failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";
import { UUID } from "@/lib/api/submission-input";

/** 申請・再申請 (本人の下書き・差し戻しのみ)。必須項目の確認は DB 側で行う。 */
export async function POST(_request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_submit_my_submission", {
    p_submission_id: submissionId,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
