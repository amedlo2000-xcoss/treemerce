import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { AGENT_RANKS } from "@/lib/domain/rewards";

type Body = { rank?: string; percent?: number | string; reason?: string };

/**
 * ランク別の紹介者の割合の変更 (0033 treemerce_admin_set_reward_rate)。super_admin 専用。
 * 画面からは % (例: 20) で受け取り、DB には比率 (0.20) で渡す。範囲 (0〜30%) は DB でも検証する。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<Body>(request);
  if (!body?.rank || !(AGENT_RANKS as readonly string[]).includes(body.rank)) {
    return fail("TREEMERCE_INVALID_INPUT", "ランクの指定が不正です。", 400);
  }
  const percent = typeof body.percent === "string" ? Number(body.percent.trim()) : Number(body.percent);
  if (body.percent == null || body.percent === "" || !Number.isFinite(percent) || percent < 0 || percent > 30) {
    return fail("TREEMERCE_INVALID_INPUT", "紹介者の割合は 0〜30 (%) の数値で入力してください。", 400);
  }
  if (Math.round(percent * 100) !== percent * 100) {
    return fail("TREEMERCE_INVALID_INPUT", "紹介者の割合は小数第2位 (例: 12.5) までで入力してください。", 400);
  }
  const reason = body.reason?.trim();
  if (!reason) {
    return fail("TREEMERCE_REASON_REQUIRED", "変更理由は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_set_reward_rate", {
    p_rank: body.rank,
    p_rate: Math.round(percent * 100) / 10000,
    p_reason: reason,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
