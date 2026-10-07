import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";
import { parseProducerInput } from "@/lib/api/producer-input";

/**
 * 生産者の新規登録 (super_admin 専用)。DB 側でも app.is_super_admin() を再判定し、
 * 監査ログに残す (連絡先・送り先メールの値は監査ログに書かれない)。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const parsed = parseProducerInput(await readJson<Record<string, unknown>>(request));
  if ("error" in parsed) return fail("TREEMERCE_INVALID_INPUT", parsed.error, 400);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_upsert_producer", {
    ...parsed.input,
    p_producer_id: null,
  });
  if (error) return failFromPostgrest(error);

  return ok(data, 201);
}
