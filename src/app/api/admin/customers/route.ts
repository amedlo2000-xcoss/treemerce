import { failFromPostgrest, ok, requireAdminApi } from "@/lib/api/http";

/**
 * 商品購入者管理。
 * CASE10: 購入者に紐づくのは「担当代理店 (customer_assignments)」だけ。
 *         代理店の登録経路とは別メニュー・別データとして扱う。
 */
export async function GET(request: Request) {
  const guard = await requireAdminApi();
  if ("error" in guard) return guard.error;

  const q = new URL(request.url).searchParams.get("q")?.trim();

  let query = guard.ctx.supabase
    .from("customers")
    .select(
      `id, full_name, full_name_kana, email, phone, prefecture, age_group, gender,
       customer_type, first_assigned_at, created_at,
       assignments:customer_assignments (
         id, status, assigned_at, assignment_source,
         agent:agents!customer_assignments_assigned_agent_id_fkey ( id, public_id, display_name )
       )`,
    )
    .order("created_at", { ascending: false })
    .limit(200);

  if (q) {
    query = query.or(`full_name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%`);
  }

  const { data, error } = await query;
  if (error) return failFromPostgrest(error);

  return ok({ customers: data ?? [] });
}
