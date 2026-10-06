import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { parseProductInput } from "@/lib/api/product-input";

/** 商品の編集 (super_admin 専用)。変更前後は監査ログに残る。 */
export async function PATCH(request: Request, context: { params: Promise<{ productId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { productId } = await context.params;
  const parsed = parseProductInput(await readJson<Record<string, unknown>>(request));
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_upsert_product", {
    ...parsed.input,
    p_product_id: productId,
  });
  if (error) return failFromPostgrest(error);

  return ok(data);
}
