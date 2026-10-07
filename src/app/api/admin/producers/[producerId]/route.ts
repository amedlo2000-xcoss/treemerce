import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { parseProducerInput } from "@/lib/api/producer-input";

/**
 * 生産者の編集・無効化 (super_admin 専用)。理由必須 (DB 側でも強制)。
 * 仮の生産者「未設定（運営）」は DB 側で編集が拒否される。
 */
export async function PATCH(request: Request, context: { params: Promise<{ producerId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { producerId } = await context.params;
  const parsed = parseProducerInput(await readJson<Record<string, unknown>>(request));
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);
  if (!parsed.input.p_reason) return fail("TREEMERCE_REASON_REQUIRED", "変更理由は必須です。", 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_upsert_producer", {
    ...parsed.input,
    p_producer_id: producerId,
  });
  if (error) return failFromPostgrest(error);

  return ok(data);
}
