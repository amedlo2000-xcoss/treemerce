import { PREFECTURES, PRODUCT_CATEGORIES, type ProductCategory } from "@/lib/domain/enums";

export type SubmissionInput = {
  p_name: string;
  p_category: ProductCategory;
  p_description: string | null;
  p_desired_price: number | null;
  p_expected_wholesale_price: number | null;
  p_content_volume: string | null;
  p_ingredients: string | null;
  p_best_before_note: string | null;
  p_producer_name: string | null;
  p_producer_origin: string | null;
  p_producer_ship_from_prefecture: string | null;
  p_producer_ship_lead_time: string | null;
  p_producer_contact_name: string | null;
  p_producer_contact_phone: string | null;
  p_producer_contact_email: string | null;
};

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** 文字数の上限 (DB の CHECK / 0018 の RPC と同じ) */
export const SUBMISSION_LIMITS = {
  name: 100,
  description: 4000,
  content_volume: 200,
  ingredients: 2000,
  best_before_note: 200,
  producer_name: 100,
  producer_origin: 100,
  producer_ship_lead_time: 100,
  producer_contact_name: 100,
  producer_contact_phone: 30,
} as const;

const LABELS: Record<keyof typeof SUBMISSION_LIMITS, string> = {
  name: "商品名",
  description: "説明",
  content_volume: "内容量",
  ingredients: "原材料",
  best_before_note: "期限の目安",
  producer_name: "生産者名",
  producer_origin: "産地",
  producer_ship_lead_time: "発送目安",
  producer_contact_name: "生産者の担当者名",
  producer_contact_phone: "生産者の電話番号",
};

/** 空なら null。0 以上 1 億円未満の整数 (円) でなければエラー文言を返す。 */
export function parseYen(value: unknown, label: string): { value: number | null } | { error: string } {
  if (value == null || (typeof value === "string" && value.trim() === "")) return { value: null };
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0 || n >= 100_000_000) {
    return { error: `${label}は 0 円以上 1 億円未満の整数で入力してください。` };
  }
  return { value: n };
}

/**
 * 申請フォームの入力を treemerce_save_my_submission の引数に整える。
 * 値の妥当性は DB 側 (0017 の CHECK / 0018 の RPC) でも必ず再検証される。
 * 必須項目の確認は申請時 (submit) に DB 側で行う。下書きは商品名だけでよい。
 */
export function parseSubmissionInput(
  body: Record<string, unknown> | null,
): { input: SubmissionInput } | { error: string } {
  if (!body) return { error: "入力内容が不正です。" };

  const text = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

  const texts = {} as Record<keyof typeof SUBMISSION_LIMITS, string | null>;
  for (const key of Object.keys(SUBMISSION_LIMITS) as (keyof typeof SUBMISSION_LIMITS)[]) {
    const value = text(body[key]);
    if (value && value.length > SUBMISSION_LIMITS[key]) {
      return { error: `${LABELS[key]}は ${SUBMISSION_LIMITS[key]} 文字以内で入力してください。` };
    }
    texts[key] = value;
  }
  if (!texts.name) return { error: "商品名は必須です。" };

  const category = (PRODUCT_CATEGORIES as readonly string[]).includes(String(body.category))
    ? (body.category as ProductCategory)
    : "other";

  const desired = parseYen(body.desired_price, "希望販売価格");
  if ("error" in desired) return desired;
  const wholesale = parseYen(body.expected_wholesale_price, "想定卸値");
  if ("error" in wholesale) return wholesale;

  const prefecture = text(body.producer_ship_from_prefecture);
  if (prefecture && !(PREFECTURES as readonly string[]).includes(prefecture)) {
    return { error: "発送元の都道府県を選択し直してください。" };
  }
  const email = text(body.producer_contact_email);
  if (email && !EMAIL.test(email)) return { error: "生産者の連絡先メールの形式が正しくありません。" };

  return {
    input: {
      p_name: texts.name,
      p_category: category,
      p_description: texts.description,
      p_desired_price: desired.value,
      p_expected_wholesale_price: wholesale.value,
      p_content_volume: texts.content_volume,
      p_ingredients: texts.ingredients,
      p_best_before_note: texts.best_before_note,
      p_producer_name: texts.producer_name,
      p_producer_origin: texts.producer_origin,
      p_producer_ship_from_prefecture: prefecture,
      p_producer_ship_lead_time: texts.producer_ship_lead_time,
      p_producer_contact_name: texts.producer_contact_name,
      p_producer_contact_phone: texts.producer_contact_phone,
      p_producer_contact_email: email,
    },
  };
}
