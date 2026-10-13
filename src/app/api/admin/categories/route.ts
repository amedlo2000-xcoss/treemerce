import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { parseReason } from "@/lib/api/submission-input";

/**
 * 商品カテゴリの追加 (super_admin 専用。DB 側でも再判定, 0022)。キーを省略すると自動で作る。
 * 並び順は末尾。監査ログに category.create が残る。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<{ name?: unknown; code?: unknown; reason?: unknown }>(request);
  const name = typeof body?.name === "string" ? body.name.trim() : "";
  if (!name || name.length > 40) return fail("TREEMERCE_INVALID_INPUT", "カテゴリ名は 1〜40 文字で入力してください。", 400);
  const code = typeof body?.code === "string" && body.code.trim() ? body.code.trim().toLowerCase() : null;
  if (code && !/^[a-z][a-z0-9_]{1,39}$/.test(code)) {
    return fail("TREEMERCE_INVALID_INPUT", "キーは英小文字で始まる英小文字・数字・_ の 2〜40 文字で入力してください。", 400);
  }
  const reason = parseReason(body?.reason);
  if ("error" in reason) return fail("TREEMERCE_INVALID_INPUT", reason.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_upsert_category", {
    p_category_id: null,
    p_name: name,
    p_code: code,
    p_reason: reason.value,
  });
  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
