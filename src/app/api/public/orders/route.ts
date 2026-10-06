import { fail, failFromPostgrest, getApiContext, ok, readJson } from "@/lib/api/http";
import {
  AGE_GROUPS,
  GENDERS,
  PREFECTURES,
  type AgeGroup,
  type Gender,
} from "@/lib/domain/enums";

type Body = {
  agent_public_id?: string;
  items?: { product_id?: unknown; quantity?: unknown }[];
  full_name?: string;
  full_name_kana?: string | null;
  email?: string | null;
  phone?: string | null;
  postal_code?: string | null;
  prefecture?: string | null;
  address?: string | null;
  age_group?: string | null;
  gender?: string | null;
  note?: string | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function pick<T extends string>(value: unknown, allowed: readonly T[]): T | null {
  return typeof value === "string" && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : null;
}

/**
 * 注文受付 (未ログイン可)。紹介リンク (代理店の公開ID) 経由でのみ受け付ける。
 *
 * 帰属代理店・在庫・金額・既存顧客の照合はすべて DB 側 (treemerce_place_order) で決まり、
 * クライアントから受け取った価格や代理店は一切使わない。
 * 原則6: 応答は新規/既存顧客で同じ形で、担当代理店が誰かは含まれない。
 */
export async function POST(request: Request) {
  const { supabase } = await getApiContext();
  const body = await readJson<Body>(request);

  if (!body?.agent_public_id?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "紹介リンクが無効です。", 400);
  }
  if (!body.full_name?.trim()) {
    return fail("TREEMERCE_INVALID_INPUT", "お名前は必須です。", 400);
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

  const prefecture = pick(body.prefecture, PREFECTURES);
  const address = body.address?.trim() || "";
  if (!prefecture || !address) {
    return fail("TREEMERCE_INVALID_INPUT", "お届け先の都道府県と住所を入力してください。", 400);
  }

  const items = (Array.isArray(body.items) ? body.items : [])
    .filter(
      (i) =>
        typeof i.product_id === "string" &&
        UUID.test(i.product_id) &&
        Number.isInteger(i.quantity) &&
        (i.quantity as number) > 0 &&
        (i.quantity as number) <= 99,
    )
    .map((i) => ({ product_id: i.product_id as string, quantity: i.quantity as number }));
  if (items.length === 0 || items.length > 20) {
    return fail("TREEMERCE_INVALID_ITEMS", "商品の指定が不正です。", 400);
  }

  const { data, error } = await supabase.rpc("treemerce_place_order", {
    p_agent_public_id: body.agent_public_id.trim(),
    p_items: items,
    p_full_name: body.full_name.trim(),
    p_ship_address: `${prefecture}${address}`,
    p_email: email,
    p_phone: phone,
    p_ship_postal_code: body.postal_code?.trim() || null,
    p_full_name_kana: body.full_name_kana?.trim() || null,
    p_age_group: pick<AgeGroup>(body.age_group, AGE_GROUPS),
    p_gender: pick<Gender>(body.gender, GENDERS),
    p_prefecture: prefecture,
    p_customer_type: "individual",
    p_note: body.note?.trim() || null,
  });

  if (error) return failFromPostgrest(error);
  return ok(data, 201);
}
