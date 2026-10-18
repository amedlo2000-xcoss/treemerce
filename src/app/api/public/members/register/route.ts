import { fail, failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";
import { requestMeta } from "@/lib/api/request-meta";
import {
  AGE_GROUPS,
  CUSTOMER_TYPES,
  GENDERS,
  PREFECTURES,
  type AgeGroup,
  type CustomerType,
  type Gender,
} from "@/lib/domain/enums";

type Body = {
  agent_public_id?: string;
  full_name?: string;
  full_name_kana?: string | null;
  email?: string | null;
  phone?: string | null;
  age_group?: string | null;
  gender?: string | null;
  prefecture?: string | null;
  customer_type?: string | null;
  apply_agent?: unknown;
  accept_agent_terms?: unknown;
  agent_terms_version?: string | null;
  agent_display_name?: string | null;
  // ip_address / user_agent は受け取らない (送られてきても無視する)
};

function pick<T extends string>(value: unknown, allowed: readonly T[]): T | null {
  return typeof value === "string" && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : null;
}

/**
 * 紹介リンク (/register/{公開ID}) からの登録。登録した人は全員「会員 (購入者)」になり、
 * 「代理店登録も申し込む」「代理店規約に同意する」の両方にチェックした人だけ代理店申請を作る。
 *
 * 絶対原則3・4: 会員の担当はリンクの代理店で確定し (treemerce_register_customer)、
 *               申請の招待元もリンクの代理店で申請時点に固定される。2つは別々に記録され、
 *               どちらも他方から導出・変更しない。
 * 絶対原則6: 会員の重複・申請の重複・既に代理店であることは、いずれも中立メッセージのみ。
 *            応答に顧客ID・担当代理店・招待元は含まれない (DB 側で除いている)。
 * 規約の同意に残す IP アドレスとブラウザ情報は、ここでリクエストヘッダーから取得して渡す。
 */
export async function POST(request: Request) {
  const { supabase } = await getApiContext();

  const body = await readJson<Body>(request);
  if (!body?.agent_public_id?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "登録元の代理店IDが指定されていません。", 400);
  }
  if (!body.full_name?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "氏名は必須です。", 400);
  }

  const email = body.email?.trim() || null;
  const phone = body.phone?.trim() || null;
  if (!email && !phone) {
    return fail(
      "TREEMERCE_IDENTIFIER_REQUIRED",
      "メールアドレスまたは電話番号のいずれかが必要です。",
      400,
    );
  }

  const applyAgent = body.apply_agent === true;
  const acceptTerms = body.accept_agent_terms === true;
  if (applyAgent && !acceptTerms) {
    return fail(
      "TREEMERCE_TERMS_CONSENT_REQUIRED",
      "代理店登録のお申し込みには代理店規約への同意が必要です。",
      400,
    );
  }
  if (applyAgent && !body.agent_display_name?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "代理店名は必須です。", 400);
  }

  const prefecture =
    typeof body.prefecture === "string" && (PREFECTURES as readonly string[]).includes(body.prefecture)
      ? body.prefecture
      : null;
  const meta = applyAgent ? requestMeta(request) : { ipAddress: null, userAgent: null };

  const { data, error } = await supabase.rpc("treemerce_register_member", {
    p_agent_public_id: body.agent_public_id.trim(),
    p_full_name: body.full_name.trim(),
    p_email: email,
    p_phone: phone,
    p_full_name_kana: body.full_name_kana?.trim() || null,
    p_age_group: pick<AgeGroup>(body.age_group, AGE_GROUPS),
    p_gender: pick<Gender>(body.gender, GENDERS),
    p_prefecture: prefecture,
    p_customer_type: pick<CustomerType>(body.customer_type, CUSTOMER_TYPES) ?? "individual",
    p_apply_agent: applyAgent,
    // 「申し込む」がないときは同意の値を送らない (DB 側でも記録しない)
    p_accept_agent_terms: applyAgent && acceptTerms,
    p_agent_terms_version: applyAgent ? body.agent_terms_version?.trim() || null : null,
    p_agent_display_name: applyAgent ? body.agent_display_name?.trim() || null : null,
    p_ip_address: meta.ipAddress,
    p_user_agent: meta.userAgent,
  });

  if (error) return failFromPostgrest(error);

  const result = data as { member_status: string };
  return ok(data, result.member_status === "registered" ? 201 : 200);
}
