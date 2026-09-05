import { fail, failFromPostgrest, ok, requireAdminApi } from "@/lib/api/http";
import { ANALYTICS_PERIODS } from "@/lib/domain/enums";

const VALID_PERIODS = new Set(ANALYTICS_PERIODS.map((p) => p.value as string));

/**
 * STEP6: ADMIN 向け客層分析。
 * root_agent_id を省略すると全代理店横断の集計になる。
 * 特定の代理店を指定すれば、その代理店を根とする部分木の集計を見られる。
 */
export async function GET(request: Request) {
  const guard = await requireAdminApi();
  if ("error" in guard) return guard.error;

  const params = new URL(request.url).searchParams;
  const period = params.get("period") ?? "all";
  const rootAgentId = params.get("root_agent_id");

  if (!VALID_PERIODS.has(period)) {
    return fail("TREEMERCE_INVALID_PERIOD", "期間の指定が不正です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_customer_demographics", {
    p_root_agent_id: rootAgentId || null,
    p_period: period,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
