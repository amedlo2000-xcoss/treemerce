import { failFromPostgrest, ok, requireAdminApi } from "@/lib/api/http";

/**
 * 顧客担当管理。
 * CASE10: 返すのは「購入者 ↔ 担当代理店」の関係と履歴だけ。
 *         代理店の登録経路 (invited_by) はここに一切含めない。
 */
export async function GET(request: Request) {
  const guard = await requireAdminApi();
  if ("error" in guard) return guard.error;

  const customerId = new URL(request.url).searchParams.get("customer_id");

  let query = guard.ctx.supabase
    .from("customer_assignments")
    .select(
      `id, customer_id, assigned_agent_id, assigned_at, assignment_source, status,
       customer:customers ( id, full_name, email, phone ),
       agent:agents!customer_assignments_assigned_agent_id_fkey ( id, public_id, display_name )`,
    )
    .order("assigned_at", { ascending: false });

  if (customerId) query = query.eq("customer_id", customerId);

  const { data: assignments, error } = await query;
  if (error) return failFromPostgrest(error);

  let historyQuery = guard.ctx.supabase
    .from("customer_assignment_history")
    .select("*")
    .order("changed_at", { ascending: false })
    .limit(200);

  if (customerId) historyQuery = historyQuery.eq("customer_id", customerId);

  const { data: history, error: historyError } = await historyQuery;
  if (historyError) return failFromPostgrest(historyError);

  return ok({ assignments: assignments ?? [], history: history ?? [] });
}
