import { fail, failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";

/**
 * 担当顧客の詳細。
 *
 * CASE5: 担当していない顧客は RLS により 0 行 → 404。
 *        「存在するが権限がない」ことも伝えないため 403 ではなく 404 を返す。
 * CASE6: 担当している顧客は氏名・連絡先・購入内容まで返す (正当な閲覧)。
 */
export async function GET(
  _request: Request,
  context: { params: Promise<{ customerId: string }> },
) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { customerId } = await context.params;

  const { data: assignment, error: assignmentError } = await guard.ctx.supabase
    .from("customer_assignments")
    .select("id, assigned_agent_id, assigned_at, assignment_source, status")
    .eq("customer_id", customerId)
    .eq("status", "active")
    .maybeSingle();

  if (assignmentError) return failFromPostgrest(assignmentError);

  // API 層でももう一度「自分が担当か」を確認する (多層防御)
  if (!assignment || assignment.assigned_agent_id !== guard.agent.id) {
    return fail("NOT_FOUND", "該当する担当顧客が見つかりません。", 404);
  }

  const [{ data: customer, error: customerError }, { data: purchases, error: purchaseError }] =
    await Promise.all([
      guard.ctx.supabase.from("customers").select("*").eq("id", customerId).maybeSingle(),
      guard.ctx.supabase
        .from("purchases")
        .select("*")
        .eq("customer_id", customerId)
        .order("purchased_at", { ascending: false }),
    ]);

  if (customerError) return failFromPostgrest(customerError);
  if (purchaseError) return failFromPostgrest(purchaseError);
  if (!customer) return fail("NOT_FOUND", "該当する担当顧客が見つかりません。", 404);

  return ok({ customer, assignment, purchases: purchases ?? [] });
}
