import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";

/** 運営の代理店登録リンクの一覧 (super_admin 専用)。トークンは含まない。 */
export async function GET() {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_list_registration_links");
  if (error) return failFromPostgrest(error);
  return ok({ links: data ?? [] });
}

type Body = { note?: string | null; max_uses?: number | null; expires_at?: string | null };

/**
 * 代理店登録リンクの発行 (super_admin 専用)。DB でも super_admin を再判定し、監査ログに残す。
 * トークンはこの応答でだけ返る (DB にはハッシュだけを保存する)。
 */
export async function POST(request: Request) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const body = (await readJson<Body>(request)) ?? {};
  const note = typeof body.note === "string" ? body.note.trim() : "";
  if (note.length > 200) {
    return fail("TREEMERCE_INVALID_INPUT", "メモは 200 文字以内で入力してください。", 400);
  }
  const maxUses = body.max_uses == null ? null : Number(body.max_uses);
  if (maxUses !== null && (!Number.isInteger(maxUses) || maxUses <= 0)) {
    return fail("TREEMERCE_INVALID_INPUT", "使用回数の上限は 1 以上の整数で指定してください。", 400);
  }
  let expiresAt: string | null = null;
  if (body.expires_at) {
    const date = new Date(body.expires_at);
    if (Number.isNaN(date.getTime())) {
      return fail("TREEMERCE_INVALID_INPUT", "有効期限の指定が不正です。", 400);
    }
    expiresAt = date.toISOString();
  }

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_create_registration_link", {
    p_note: note || null,
    p_max_uses: maxUses,
    p_expires_at: expiresAt,
  });
  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
