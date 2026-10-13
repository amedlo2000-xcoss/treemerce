import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID, parseReason, parseSubmissionInput } from "@/lib/api/submission-input";

/**
 * 運営が代理店の名義で持込み申請の下書きを作る (super_admin 専用。DB 側でも再判定, 0021)。
 * 理由 (ヒアリングの日付・経緯など) は必須。対象は稼働中の代理店のみ。
 * 承認すると持込み元はこの代理店になる (変更不可)。招待経路・顧客の担当には触れない。
 */
export async function POST(request: Request, context: { params: Promise<{ agentId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { agentId } = await context.params;
  if (!UUID.test(agentId)) return fail("TREEMERCE_AGENT_NOT_FOUND", "指定の代理店が見つかりません。", 404);

  const body = await readJson<Record<string, unknown>>(request);
  const parsed = parseSubmissionInput(body);
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const reason = parseReason(body?.reason);
  if ("error" in reason) return fail("TREEMERCE_INVALID_INPUT", reason.error, 400);
  if (!reason.value) {
    return fail("TREEMERCE_REASON_REQUIRED", "代行で作成する理由 (ヒアリングの日付・経緯など) は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_save_proxy_submission", {
    p_agent_id: agentId,
    p_submission_id: null,
    ...parsed.input,
    p_reason: reason.value,
  });
  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
