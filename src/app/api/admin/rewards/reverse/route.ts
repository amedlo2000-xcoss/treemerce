import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";

type Body = { order_id?: string; reason?: string };

/**
 * 注文の報酬の取り消し (0033 treemerce_admin_reverse_order_rewards)。super_admin 専用。
 * 取り消されていない確定明細それぞれにマイナスの明細を作る。理由は必須で監査ログに残る。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<Body>(request);
  if (!body?.order_id) {
    return fail("TREEMERCE_INVALID_INPUT", "注文IDは必須です。", 400);
  }
  const reason = body.reason?.trim();
  if (!reason) {
    return fail("TREEMERCE_REASON_REQUIRED", "取り消しの理由は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_reverse_order_rewards", {
    p_order_id: body.order_id,
    p_reason: reason,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
