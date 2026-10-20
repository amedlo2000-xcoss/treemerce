import { failFromPostgrest, ok, requireSuperAdminApi } from "@/lib/api/http";
import { readRevokeLinkInput } from "@/lib/api/registration-link-input";

/**
 * 代理店登録リンクの無効化 (super_admin 専用・理由必須。代理店が発行したリンクも対象)。
 * 以後の申し込みを受け付けない。既に届いた申請はそのまま審査できる。理由は監査ログに残る。
 */
export async function POST(request: Request, context: { params: Promise<{ linkId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { linkId } = await context.params;
  const input = await readRevokeLinkInput(request, linkId);
  if ("error" in input) return input.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_revoke_registration_link", input.params);
  if (error) return failFromPostgrest(error);
  return ok(data);
}
