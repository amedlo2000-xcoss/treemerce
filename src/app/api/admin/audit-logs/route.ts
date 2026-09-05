import { failFromPostgrest, ok, requireAdminApi } from "@/lib/api/http";

/** 監査ログ。RLS により管理者以外は 1 行も読めない。 */
export async function GET(request: Request) {
  const guard = await requireAdminApi();
  if ("error" in guard) return guard.error;

  const params = new URL(request.url).searchParams;
  const targetId = params.get("target_id");
  const action = params.get("action");

  let query = guard.ctx.supabase
    .from("admin_audit_logs")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(200);

  if (targetId) query = query.eq("target_id", targetId);
  if (action) query = query.eq("action", action);

  const { data, error } = await query;
  if (error) return failFromPostgrest(error);

  return ok({ logs: data ?? [] });
}
