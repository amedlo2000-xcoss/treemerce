import { fail, failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";

type Body = {
  auth_user_id?: string;
  display_name?: string;
  email?: string;
  phone?: string | null;
  inviter_mode?: string;
  inviter_agent_id?: string | null;
  reason?: string;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 代理店の直接作成 (super_admin 専用)。
 *
 * 一般の人 (未ログインを含む) は代理店を作れない。代理店登録は紹介リンクの登録フォームから申し込み、
 * 運営の承認で作られる。ここでは RPC を呼ばずに案内だけを返す。
 *
 * 絶対原則2: super_admin が作る場合も、招待元は明示が必須 ('agent' + 代理店ID か 'none')。
 *            作成と招待経路の確定は DB 側の app.create_agent() だけが行い、監査ログに
 *            実行者・日時・招待元が残る。既に代理店のアカウントは作り直せない。
 */
export async function POST(request: Request) {
  const { supabase, viewer } = await getApiContext();

  if (!viewer.isAdmin || viewer.adminRole !== "super_admin") {
    return fail(
      "TREEMERCE_AGENT_APPLICATION_REQUIRED",
      "オブザーバー登録は、紹介リンクの登録フォームからお申し込みください。運営の確認後にオブザーバーとしてご利用いただけます。",
      403,
    );
  }

  const body = await readJson<Body>(request);
  if (!body?.auth_user_id || !UUID.test(body.auth_user_id)) {
    return fail("TREEMERCE_INVALID_INPUT", "対象のアカウントを指定してください。", 400);
  }
  if (!body.display_name?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "オブザーバー名は必須です。", 400);
  }
  if (!body.email?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "メールアドレスは必須です。", 400);
  }
  if (!body.reason?.trim()) {
    return fail("TREEMERCE_REASON_REQUIRED", "作成理由は必須です。", 400);
  }
  const inviterMode = body.inviter_mode;
  const inviterId = body.inviter_agent_id?.trim() || null;
  if (
    !(inviterMode === "agent" && inviterId && UUID.test(inviterId)) &&
    !(inviterMode === "none" && inviterId === null)
  ) {
    return fail(
      "TREEMERCE_INVITER_REQUIRED",
      "招待元を指定してください (オブザーバーを指定するか、招待元なしを明示)。",
      400,
    );
  }

  const { data, error } = await supabase.rpc("treemerce_register_agent", {
    p_auth_user_id: body.auth_user_id,
    p_display_name: body.display_name.trim(),
    p_email: body.email.trim(),
    p_phone: body.phone?.trim() || null,
    p_inviter_mode: inviterMode,
    p_inviter_agent_id: inviterId,
    p_reason: body.reason.trim(),
  });

  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
