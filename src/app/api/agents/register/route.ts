import { fail, failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";

type Body = {
  display_name?: string;
  email?: string;
  phone?: string | null;
  invitation_code?: string | null;
};

/**
 * 代理店登録 / 招待経路の確定。
 *
 * 絶対原則2 & CASE19: 既に invited_by が確定している代理店に別の招待コードを
 * 適用しようとした場合、DB 側 (treemerce_register_agent + immutable トリガ) が
 * 例外を投げ、ここで 409 に変換される。
 */
export async function POST(request: Request) {
  const { supabase, viewer } = await getApiContext();

  if (!viewer.userId) {
    return fail("UNAUTHENTICATED", "ログインが必要です。", 401);
  }

  const body = await readJson<Body>(request);
  if (!body?.display_name?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "代理店名は必須です。", 400);
  }

  const email = body.email?.trim() || viewer.email;
  if (!email) {
    return fail("TREEMERCE_INVALID_INPUT", "メールアドレスは必須です。", 400);
  }

  const { data, error } = await supabase.rpc("treemerce_register_agent", {
    p_display_name: body.display_name.trim(),
    p_email: email,
    p_phone: body.phone?.trim() || null,
    p_invitation_code: body.invitation_code?.trim() || null,
  });

  if (error) return failFromPostgrest(error);

  return ok(data, 200);
}
