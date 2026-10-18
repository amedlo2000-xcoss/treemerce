import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 代理店登録リンクの無効化 (super_admin 専用・理由必須)。以後の申し込みを受け付けない。
 * 既に届いた申請はそのまま審査できる。理由は監査ログに残る。
 */
export async function POST(request: Request, context: { params: Promise<{ linkId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { linkId } = await context.params;
  if (!UUID.test(linkId)) {
    return fail("TREEMERCE_REGISTRATION_LINK_NOT_FOUND", "代理店登録リンクが見つかりません。", 404);
  }

  const body = await readJson<{ reason?: unknown }>(request);
  const reason = typeof body?.reason === "string" ? body.reason.trim() : "";
  if (!reason) return fail("TREEMERCE_REASON_REQUIRED", "理由を入力してください。", 400);
  if (reason.length > 1000) {
    return fail("TREEMERCE_INVALID_INPUT", "理由は 1000 文字以内で入力してください。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_revoke_registration_link", {
    p_link_id: linkId,
    p_reason: reason,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
