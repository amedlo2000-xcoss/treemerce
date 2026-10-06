import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";

type Body = { customer_id?: string; new_agent_id?: string; reason?: string };

/**
 * 担当代理店の変更 (super_admin 専用)。
 *
 * 絶対原則4 / 8, CASE7 / CASE8。
 * 防御は 2 段:
 *   1. ここ (API 層) で requireSuperAdminApi() が super_admin 以外を 403 で弾く
 *   2. DB 側 `treemerce_admin_transfer_customer` が app.is_super_admin() を再チェックし、
 *      さらに customer_assignments のガードトリガが認可コンテキスト外の書込みを拒否する
 * 変更前後・理由・実行者・日時は admin_audit_logs と
 * customer_assignment_history の両方に保存される。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<Body>(request);
  if (!body?.customer_id || !body.new_agent_id) {
    return fail("TREEMERCE_INVALID_INPUT", "顧客IDと変更先の代理店IDは必須です。", 400);
  }
  if (!body.reason?.trim()) {
    return fail("TREEMERCE_REASON_REQUIRED", "変更理由は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_transfer_customer", {
    p_customer_id: body.customer_id,
    p_new_agent_id: body.new_agent_id,
    p_reason: body.reason.trim(),
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
