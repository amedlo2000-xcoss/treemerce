import { fail, failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";
import { requestMeta } from "@/lib/api/request-meta";

type Body = {
  token?: string;
  agent_display_name?: string;
  email?: string;
  phone?: string | null;
  accept_agent_terms?: unknown;
  agent_terms_version?: string | null;
  // ip_address / user_agent は受け取らない (送られてきても無視する)
};

/**
 * 運営の代理店登録リンク (/join/{トークン}) からの申し込み。代理店の申し込みだけで、会員登録は行わない。
 *
 * 絶対原則2: 招待元はなし (運営からの直接登録) で申請時点に固定される。代理店は承認でだけ作られる。
 * 絶対原則6: 承認待ち・既に代理店の場合も、新規受付と同じ中立メッセージのみ (DB 側で揃えている)。
 * 規約の同意に残す IP アドレスとブラウザ情報は、ここでリクエストヘッダーから取得して渡す。
 */
export async function POST(request: Request) {
  const { supabase } = await getApiContext();

  const body = await readJson<Body>(request);
  if (!body?.token?.trim()) {
    return fail("TREEMERCE_REGISTRATION_LINK_UNAVAILABLE", "この代理店登録リンクは利用できません。", 409);
  }
  if (body.accept_agent_terms !== true) {
    return fail(
      "TREEMERCE_TERMS_CONSENT_REQUIRED",
      "代理店登録のお申し込みには代理店規約への同意が必要です。",
      400,
    );
  }
  if (!body.agent_display_name?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "代理店名は必須です。", 400);
  }
  if (!body.email?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "メールアドレスは必須です。", 400);
  }

  const meta = requestMeta(request);

  const { data, error } = await supabase.rpc("treemerce_apply_agent_via_link", {
    p_token: body.token.trim(),
    p_agent_display_name: body.agent_display_name.trim(),
    p_email: body.email.trim(),
    p_phone: body.phone?.trim() || null,
    p_accept_agent_terms: true,
    p_agent_terms_version: body.agent_terms_version?.trim() || null,
    p_ip_address: meta.ipAddress,
    p_user_agent: meta.userAgent,
  });

  if (error) return failFromPostgrest(error);
  return ok(data);
}
