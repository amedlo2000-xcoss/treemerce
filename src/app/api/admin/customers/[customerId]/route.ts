import { fail, failFromPostgrest, ok, readJson, requireAdminApi } from "@/lib/api/http";

type Body = { patch?: Record<string, unknown>; reason?: string | null };

const EDITABLE_FIELDS = new Set([
  "full_name",
  "full_name_kana",
  "email",
  "phone",
  "postal_code",
  "address_line",
  "prefecture",
  "age_group",
  "gender",
  "customer_type",
  "note",
]);

/**
 * 購入者情報の更新 (ADMIN 専用)。
 * ここでは担当代理店を変更できない。担当変更は /api/admin/assignments/transfer のみ。
 */
export async function PATCH(request: Request, context: { params: Promise<{ customerId: string }> }) {
  const guard = await requireAdminApi();
  if ("error" in guard) return guard.error;

  const { customerId } = await context.params;
  const body = await readJson<Body>(request);

  if (!body?.patch || typeof body.patch !== "object") {
    return fail("TREEMERCE_INVALID_INPUT", "更新内容が指定されていません。", 400);
  }

  const patch = Object.fromEntries(
    Object.entries(body.patch).filter(([key]) => EDITABLE_FIELDS.has(key)),
  );

  if (Object.keys(patch).length === 0) {
    return fail("TREEMERCE_INVALID_INPUT", "更新できる項目がありません。", 400);
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_update_customer", {
    p_customer_id: customerId,
    p_patch: patch,
    p_reason: body.reason?.trim() || null,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
