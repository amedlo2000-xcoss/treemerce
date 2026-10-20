import { failFromPostgrest, ok, requireSuperAdminApi } from "@/lib/api/http";
import { readIssueLinkInput } from "@/lib/api/registration-link-input";

/** 代理店登録リンクの一覧 (super_admin 専用。代理店が発行したリンクも含む)。トークンは含まない。 */
export async function GET() {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_list_registration_links");
  if (error) return failFromPostgrest(error);
  return ok({ links: data ?? [] });
}

/**
 * 運営の代理店登録リンクの発行 (super_admin 専用。紐づけ先なし = 運営直下)。
 * DB でも super_admin を再判定し、監査ログに残す。トークンはこの応答でだけ返る (DB にはハッシュだけを保存する)。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const input = await readIssueLinkInput(request);
  if ("error" in input) return input.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_create_registration_link", input.params);
  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
