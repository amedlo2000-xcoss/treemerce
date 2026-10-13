import { fail, failFromPostgrest, ok, requireSuperAdminApi } from "@/lib/api/http";
import { UUID } from "@/lib/api/submission-input";

/**
 * 代行の申請を申請中にする (super_admin 専用, 0021)。必須項目の確認は DB 側で行う。
 * 申請中になったあとは、従来の審査 (承認・差し戻し・却下) をそのまま使う。
 */
export async function POST(_request: Request, context: { params: Promise<{ submissionId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { submissionId } = await context.params;
  if (!UUID.test(submissionId)) return fail("TREEMERCE_SUBMISSION_NOT_FOUND", "申請が見つかりません。", 404);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_submit_proxy_submission", {
    p_submission_id: submissionId,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
