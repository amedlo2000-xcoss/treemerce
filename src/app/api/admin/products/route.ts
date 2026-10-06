import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { parseProductInput } from "@/lib/api/product-input";

/** 商品の新規登録 (super_admin 専用)。DB 側でも app.is_super_admin() を再判定し、監査ログに残す。 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const parsed = parseProductInput(await readJson<Record<string, unknown>>(request));
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_upsert_product", {
    ...parsed.input,
    p_product_id: null,
  });
  if (error) return failFromPostgrest(error);

  return ok(data, 201);
}
