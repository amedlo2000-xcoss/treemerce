import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID } from "@/lib/api/submission-input";

/**
 * 持込み申請の差し戻し・却下 (super_admin 専用。理由必須)。
 * DB 側でも app.is_super_admin() と理由の有無を再判定する。理由は代理店にも表示される。
 */
export async function reviewSubmission(
  request: Request,
  submissionId: string,
  rpc: "treemerce_admin_return_submission" | "treemerce_admin_reject_submission",
) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const body = await readJson<{ reason?: unknown }>(request);
  const reason = typeof body?.reason === "string" ? body.reason.trim() : "";
  if (!reason) return fail("TREEMERCE_REASON_REQUIRED", "理由を入力してください。", 400);
  if (reason.length > 1000) return fail("TREEMERCE_INVALID_INPUT", "理由は 1000 文字以内で入力してください。", 400);

  const { data, error } = await guard.ctx.supabase.rpc(rpc, {
    p_submission_id: submissionId,
    p_reason: reason,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
