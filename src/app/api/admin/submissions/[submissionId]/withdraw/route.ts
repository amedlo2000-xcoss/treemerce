import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID, parseReason } from "@/lib/api/submission-input";

/** 代行の申請の取り下げ (super_admin 専用・下書き・差し戻しのみ・理由必須, 0021)。申請は削除されない。 */
export async function POST(request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const reason = parseReason((await readJson<{ reason?: unknown }>(request))?.reason);
  if ("error" in reason) return fail("TREEMERCE_INVALID_INPUT", reason.error, 400);
  if (!reason.value) return fail("TREEMERCE_REASON_REQUIRED", "取り下げの理由は必須です。", 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_withdraw_proxy_submission", {
    p_submission_id: submissionId,
    p_reason: reason.value,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
