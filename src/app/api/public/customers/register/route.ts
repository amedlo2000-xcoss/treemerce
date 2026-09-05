import { fail, failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";
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
  postal_code?: string | null;
  address_line?: string | null;
};

function pick<T extends string>(value: unknown, allowed: readonly T[]): T | null {
  return typeof value === "string" && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : null;
}

/**
 * 商品購入者の登録。代理店の登録URL (公開ID) 経由で呼ばれる。
 *
 * CASE3: 登録に使われた代理店が、そのまま担当代理店として保存される。
 * CASE4: 既存の識別子と一致した場合は重複として扱い、担当は一切変更しない。
 *        レスポンスは中立メッセージのみで、担当代理店が誰かは開示しない (絶対原則6)。
 * 絶対原則7: email / 電話番号の識別子で照合する。氏名のみでは同定しない。
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

  const prefecture =
    typeof body.prefecture === "string" && (PREFECTURES as readonly string[]).includes(body.prefecture)
      ? body.prefecture
      : null;

  const { data, error } = await supabase.rpc("treemerce_register_customer", {
    p_agent_public_id: body.agent_public_id.trim(),
    p_full_name: body.full_name.trim(),
    p_email: email,
    p_phone: phone,
    p_full_name_kana: body.full_name_kana?.trim() || null,
    p_age_group: pick<AgeGroup>(body.age_group, AGE_GROUPS),
    p_gender: pick<Gender>(body.gender, GENDERS),
    p_prefecture: prefecture,
    p_customer_type: pick<CustomerType>(body.customer_type, CUSTOMER_TYPES) ?? "individual",
    p_postal_code: body.postal_code?.trim() || null,
    p_address_line: body.address_line?.trim() || null,
  });

  if (error) return failFromPostgrest(error);

  const result = data as { status: string };
  return ok(data, result.status === "registered" ? 201 : 200);
}
