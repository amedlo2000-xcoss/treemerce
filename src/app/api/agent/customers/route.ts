import { failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";

/**
 * STEP4: 代理店マイページ「担当顧客」一覧。
 *
 * 絶対原則5 / CASE5 / CASE6:
 * `customer_assignments` の SELECT ポリシーが assigned_agent_id = 自分 に限定し、
 * `customers` の SELECT ポリシーが app.is_assigned_agent() に限定するため、
 * 他代理店 (傘下を含む) が担当する購入者はそもそも 1 行も返らない。
 */
export async function GET() {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase
    .from("customer_assignments")
    .select(
      `id, assigned_at, assignment_source, status,
       customer:customers!inner (
         id, full_name, full_name_kana, email, phone, prefecture,
         age_group, gender, customer_type, first_assigned_at,
         purchases ( id, product_name, product_category, quantity, amount, purchased_at, status )
       )`,
    )
    .eq("status", "active")
    .order("assigned_at", { ascending: false });

  if (error) return failFromPostgrest(error);

  return ok({
    assigned_agent_id: guard.agent.id,
    count: data?.length ?? 0,
    customers: data ?? [],
  });
}
