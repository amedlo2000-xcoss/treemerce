import { fail, failFromPostgrest, ok, requireAgentApi } from "@/lib/api/http";
import { ANALYTICS_PERIODS } from "@/lib/domain/enums";

const VALID_PERIODS = new Set(ANALYTICS_PERIODS.map((p) => p.value as string));

/**
 * STEP6: 客層分析。
 *
 * 集計対象 = ログイン代理店自身 + 傘下代理店全員 (商流マップと同じ再帰CTE)。
 * 傘下他代理店担当の顧客は属性値のみが匿名のまま合算される。
 *
 * CASE16: 自分 + 傘下が対象
 * CASE17: 兄弟枝・upline は対象外 (根は常にサーバー側で自分に固定)
 * CASE18: レスポンスに代理店別内訳・顧客IDを含めない
 */
export async function GET(request: Request) {
  const guard = await requireAgentApi();
  if ("error" in guard) return guard.error;

  const period = new URL(request.url).searchParams.get("period") ?? "all";
  if (!VALID_PERIODS.has(period)) {
    return fail("TREEMERCE_INVALID_PERIOD", "期間の指定が不正です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_customer_demographics", {
    p_root_agent_id: null,
    p_period: period,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
