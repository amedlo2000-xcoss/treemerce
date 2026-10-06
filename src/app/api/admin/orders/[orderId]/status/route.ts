import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { ORDER_STATUSES, type OrderStatus } from "@/lib/domain/enums";

type Body = { status?: string; reason?: string; restock?: boolean | null };

/**
 * 注文ステータスの変更 (super_admin 専用)。
 * 遷移の妥当性・理由必須・在庫の戻し・履歴と監査ログへの記録はすべて DB 側
 * (treemerce_admin_set_order_status / 0013) で強制される。
 * 帰属代理店 (agent_id) はここからは一切変更できない。
 */
export async function POST(request: Request, context: { params: Promise<{ orderId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { orderId } = await context.params;
  const body = await readJson<Body>(request);

  if (!body?.status || !(ORDER_STATUSES as readonly string[]).includes(body.status)) {
    return fail("TREEMERCE_INVALID_INPUT", "変更後のステータスを指定してください。", 400);
  }
  if (!body.reason?.trim()) {
    return fail("TREEMERCE_REASON_REQUIRED", "変更理由は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_set_order_status", {
    p_order_id: orderId,
    p_status: body.status as OrderStatus,
    p_reason: body.reason.trim(),
    p_restock: typeof body.restock === "boolean" ? body.restock : null,
  });
  if (error) return failFromPostgrest(error);

  return ok(data);
}
