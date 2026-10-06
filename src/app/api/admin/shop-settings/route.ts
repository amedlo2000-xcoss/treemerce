import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";

type Body = { patch?: Record<string, unknown>; reason?: string };

/**
 * ショップ設定 (運営の振込先・特商法表記・送料・支払期限・注文受付) の更新。super_admin 専用。
 * 変更可能な項目の絞り込み・受付開始時の必須項目チェック・監査ログは DB 側 (0011) で行う。
 */
export async function PATCH(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = await readJson<Body>(request);
  if (!body?.patch || typeof body.patch !== "object") {
    return fail("TREEMERCE_INVALID_INPUT", "更新内容が指定されていません。", 400);
  }
  if (!body.reason?.trim()) {
    return fail("TREEMERCE_REASON_REQUIRED", "変更理由は必須です。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_update_shop_settings", {
    p_patch: body.patch,
    p_reason: body.reason.trim(),
  });
  if (error) return failFromPostgrest(error);

  return ok(data);
}
