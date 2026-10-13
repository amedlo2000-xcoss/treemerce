import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { parseAgentProfileInput } from "@/lib/api/agent-profile-input";
import { UUID, parseReason } from "@/lib/api/submission-input";

/**
 * 代理店の事業プロフィールを運営が入力・編集する (super_admin 専用。DB 側でも再判定, 0020)。
 *   reason              : 入力済みのプロフィールを変更するときは必須 (初回の入力は任意)
 *   expected_updated_at : 画面を開いた時点の更新日時 (未入力なら null)。違えば保存しない
 * 監査ログには値を書かず、変更した項目名と理由だけが残る。招待経路・顧客の担当には触れない。
 */
export async function PUT(request: Request, context: { params: Promise<{ agentId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { agentId } = await context.params;
  if (!UUID.test(agentId)) return fail("TREEMERCE_AGENT_NOT_FOUND", "指定の代理店が見つかりません。", 404);

  const body = await readJson<Record<string, unknown>>(request);
  const parsed = parseAgentProfileInput(body);
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const reason = parseReason(body?.reason);
  if ("error" in reason) return fail("TREEMERCE_INVALID_INPUT", reason.error, 400);

  const expected = body?.expected_updated_at;
  if (expected != null && (typeof expected !== "string" || Number.isNaN(Date.parse(expected)))) {
    return fail("TREEMERCE_INVALID_INPUT", "入力内容が不正です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_update_agent_profile", {
    p_agent_id: agentId,
    ...parsed.input,
    p_reason: reason.value,
    p_expected_updated_at: expected ?? null,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
