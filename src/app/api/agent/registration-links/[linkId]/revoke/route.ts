import { failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";
import { readRevokeLinkInput } from "@/lib/api/registration-link-input";

/**
 * 自分が発行した代理店登録リンクの無効化 (代理店本人・理由必須)。
 * 他の代理店のリンクは DB 側で「見つかりません」になる (存在も開示しない)。理由は監査ログに残る。
 */
export async function POST(request: Request, context: { params: Promise<{ linkId: string }> }) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { linkId } = await context.params;
  const input = await readRevokeLinkInput(request, linkId);
  if ("error" in input) return input.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_revoke_my_registration_link", input.params);
  if (error) return failFromPostgrest(error);
  return ok(data);
}
