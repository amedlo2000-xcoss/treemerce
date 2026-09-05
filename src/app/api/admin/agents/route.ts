import { failFromPostgrest, ok, requireAdminApi } from "@/lib/api/http";

/**
 * 代理店管理。
 * CASE10: ここで扱うのは代理店の登録経路 (invited_by) のみ。
 *         顧客の担当関係は「顧客担当管理」(/api/admin/assignments) の責務。
 */
export async function GET() {
  const guard = await requireAdminApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase
    .from("agents")
    .select(
      "id, public_id, display_name, legal_name, email, phone, prefecture, status, invited_by, registered_at",
    )
    .order("registered_at", { ascending: true });

  if (error) return failFromPostgrest(error);
  return ok({ agents: data ?? [] });
}
