import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { UUID, parseReason } from "@/lib/api/submission-input";

/**
 * 商品カテゴリの名称変更・有効/無効 (super_admin 専用。DB 側でも再判定, 0022)。理由は必須。
 *   { name, reason }       : 名称変更 (キーは変わらない。過去の注文明細は注文時点の名前のまま)
 *   { is_active, reason }  : 有効・無効 (公開中・準備中の商品が使っているカテゴリは無効にできない)
 * 削除はできない。
 */
export async function PATCH(request: Request, context: { params: Promise<{ categoryId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { categoryId } = await context.params;
  if (!UUID.test(categoryId)) return fail("TREEMERCE_CATEGORY_NOT_FOUND", "カテゴリが見つかりません。", 404);

  const body = await readJson<{ name?: unknown; is_active?: unknown; reason?: unknown }>(request);
  const reason = parseReason(body?.reason);
  if ("error" in reason) return fail("TREEMERCE_INVALID_INPUT", reason.error, 400);
  if (!reason.value) return fail("TREEMERCE_REASON_REQUIRED", "理由は必須です。", 400);

  if (typeof body?.is_active === "boolean") {
    const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_set_category_active", {
      p_category_id: categoryId,
      p_is_active: body.is_active,
      p_reason: reason.value,
    });
    if (error) return failFromPostgrest(error);
    return ok(data);
  }

  const name = typeof body?.name === "string" ? body.name.trim() : "";
  if (!name || name.length > 40) return fail("TREEMERCE_INVALID_INPUT", "カテゴリ名は 1〜40 文字で入力してください。", 400);
  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_upsert_category", {
    p_category_id: categoryId,
    p_name: name,
    p_code: null,
    p_reason: reason.value,
  });
  if (error) return failFromPostgrest(error);
  return ok(data);
}
