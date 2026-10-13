import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID, parseReason } from "@/lib/api/submission-input";

/**
 * 商品カテゴリの並べ替え (super_admin 専用。DB 側でも再判定, 0022)。
 * 全カテゴリ (無効を含む) の id を新しい順に 1 回ずつ並べて渡す。過不足は DB 側で拒否される。
 */
export async function PUT(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<{ ids?: unknown; reason?: unknown }>(request);
  const ids = Array.isArray(body?.ids) ? body.ids : null;
  if (!ids || ids.length === 0 || ids.some((id) => typeof id !== "string" || !UUID.test(id))) {
    return fail("TREEMERCE_INVALID_INPUT", "並び順の指定が不正です。", 400);
  }
  const reason = parseReason(body?.reason);
  if ("error" in reason) return fail("TREEMERCE_INVALID_INPUT", reason.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_reorder_categories", {
    p_category_ids: ids,
    p_reason: reason.value,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
