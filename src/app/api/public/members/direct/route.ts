import { fail, failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";
import { CUSTOMER_TYPES, type CustomerType } from "@/lib/domain/enums";

type Body = {
  full_name?: string;
  full_name_kana?: string | null;
  email?: string | null;
  phone?: string | null;
  customer_type?: string | null;
};

/**
 * 運営のショップ (/shop) からの会員登録。どのオブザーバーにも紐づかない「運営直接」の会員になる
 * (紹介者・担当なし。treemerce_register_direct_member、0037)。
 *
 * 原則4: 既存の会員 (担当あり・運営直接のどちらでも) は何も変わらない。
 * 原則6: 新規・既存の会員で応答を同じにする (状態コード・本文とも。登録状況・担当は返さない)。
 */
export async function POST(request: Request) {
  const { supabase } = await getApiContext();

  const body = await readJson<Body>(request);
  if (!body?.full_name?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "氏名は必須です。", 400);
  }
  const email = body.email?.trim() || null;
  const phone = body.phone?.trim() || null;
  if (!email && !phone) {
    return fail("TREEMERCE_IDENTIFIER_REQUIRED", "メールアドレスまたは電話番号のいずれかが必要です。", 400);
  }
  const customerType =
    typeof body.customer_type === "string" && (CUSTOMER_TYPES as readonly string[]).includes(body.customer_type)
      ? (body.customer_type as CustomerType)
      : "individual";

  const { error } = await supabase.rpc("treemerce_register_direct_member", {
    p_full_name: body.full_name.trim(),
    p_email: email,
    p_phone: phone,
    p_full_name_kana: body.full_name_kana?.trim() || null,
    p_customer_type: customerType,
  });
  if (error) return failFromPostgrest(error);

  return ok({ application_status: null, application_message: null }, 200);
}
