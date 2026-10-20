import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 承認の理由が空のときに監査ログへ記録する文言 */
const NO_REASON = "（理由の入力なし）";

/**
 * 代理店申請の承認・却下 (super_admin 専用。承認の理由は任意、却下は理由必須)。
 * DB 側でも app.is_super_admin() と理由の有無を再判定し、監査ログに記録する。
 * 承認は招待元を受け取らない (申請時点で固定された招待元をそのまま使う)。
 * 却下の理由は監査ログにだけ残り、申請者本人には表示されない。
 */
export async function reviewAgentApplication(
  request: Request,
  applicationId: string,
  rpc: "treemerce_admin_approve_agent_application" | "treemerce_admin_reject_agent_application",
) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  if (!UUID.test(applicationId)) {
    return fail("TREEMERCE_APPLICATION_NOT_FOUND", "申請が見つかりません。", 404);
  }

  const body = await readJson<{ reason?: unknown }>(request);
  const input = typeof body?.reason === "string" ? body.reason.trim() : "";
  // 承認の理由は任意 (空なら監査ログに定型文を残す)。却下は理由必須
  const reason = input || (rpc === "treemerce_admin_approve_agent_application" ? NO_REASON : "");
  if (!reason) return fail("TREEMERCE_REASON_REQUIRED", "理由を入力してください。", 400);
  if (reason.length > 1000) {
    return fail("TREEMERCE_INVALID_INPUT", "理由は 1000 文字以内で入力してください。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc(rpc, {
    p_application_id: applicationId,
    p_reason: reason,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
