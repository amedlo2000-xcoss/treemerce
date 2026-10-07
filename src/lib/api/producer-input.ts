import { PREFECTURES } from "@/lib/domain/enums";

export type ProducerInput = {
  p_name: string;
  p_origin: string;
  p_ship_from_prefecture: string;
  p_ship_lead_time: string;
  p_notify_email: string | null;
  p_contact_name: string | null;
  p_contact_phone: string | null;
  p_contact_email: string | null;
  p_note: string | null;
  p_is_active: boolean;
  p_reason: string | null;
};

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/**
 * 生産者フォームの入力を treemerce_admin_upsert_producer の引数に整える。
 * 値の妥当性は DB 側 (0014 の CHECK / 0015 の RPC) でも必ず再検証される。
 */
export function parseProducerInput(
  body: Record<string, unknown> | null,
): { input: ProducerInput } | { error: string } {
  if (!body) return { error: "入力内容が不正です。" };

  const text = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

  const name = text(body.name);
  if (!name) return { error: "生産者名は必須です。" };
  const origin = text(body.origin);
  if (!origin) return { error: "産地は必須です。" };
  const prefecture = text(body.ship_from_prefecture);
  if (!prefecture || !(PREFECTURES as readonly string[]).includes(prefecture)) {
    return { error: "発送元の都道府県を選択してください。" };
  }
  const leadTime = text(body.ship_lead_time);
  if (!leadTime) return { error: "発送目安は必須です。" };

  const notifyEmail = text(body.notify_email);
  if (notifyEmail && !EMAIL.test(notifyEmail)) {
    return { error: "発送依頼の送り先メールの形式が正しくありません。" };
  }
  const contactEmail = text(body.contact_email);
  if (contactEmail && !EMAIL.test(contactEmail)) {
    return { error: "連絡先メールの形式が正しくありません。" };
  }

  return {
    input: {
      p_name: name,
      p_origin: origin,
      p_ship_from_prefecture: prefecture,
      p_ship_lead_time: leadTime,
      p_notify_email: notifyEmail,
      p_contact_name: text(body.contact_name),
      p_contact_phone: text(body.contact_phone),
      p_contact_email: contactEmail,
      p_note: text(body.note),
      p_is_active: body.is_active !== false,
      p_reason: text(body.reason),
    },
  };
}
