import { fail, failFromPostgrest, ok, readJson, requireAgentApi } from "@/lib/api/http";
import { UUID, parseSubmissionInput } from "@/lib/api/submission-input";

/**
 * 持込み申請の保存 (本人の下書き・差し戻しのみ)。
 * 他の代理店の申請 ID を指定しても DB 側で「見つかりません」になる。
 */
export async function PUT(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const parsed = parseSubmissionInput(await readJson<Record<string, unknown>>(request));
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_save_my_submission", {
    p_submission_id: submissionId,
    ...parsed.input,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
