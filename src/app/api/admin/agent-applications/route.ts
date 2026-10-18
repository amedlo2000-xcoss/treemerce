import { failFromPostgrest, ok, requireSuperAdminApi } from "@/lib/api/http";
import { AGENT_APPLICATION_STATUSES, type AgentApplicationStatus } from "@/lib/domain/enums";

/** 代理店申請の一覧 (super_admin 専用)。?status=pending|approved|rejected で絞り込む。 */
export async function GET(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const status = new URL(request.url).searchParams.get("status");
  const statusFilter = (AGENT_APPLICATION_STATUSES as readonly string[]).includes(status ?? "")
    ? (status as AgentApplicationStatus)
    : null;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_list_agent_applications", {
    p_status: statusFilter,
  });
  if (error) return failFromPostgrest(error);
  return ok({ applications: data ?? [] });
}
