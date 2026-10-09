import { AGENT_INDUSTRIES, PREFECTURES } from "@/lib/domain/enums";

export type AgentProfileInput = {
  p_industry: string | null;
  p_business_description: string | null;
  p_offerings: string | null;
  p_target_customers: string | null;
  p_activity_prefectures: string[];
  p_website_url: string | null;
  p_sns_urls: string[];
  p_self_introduction: string | null;
};

/** DB の app.is_http_url と同じ条件 (http(s) のみ・500 文字まで)。 */
const HTTP_URL = /^https?:\/\/[^/\s<>"']+(\/[^\s<>"']*)?$/i;

export function isHttpUrl(value: string) {
  return value.length <= 500 && HTTP_URL.test(value);
}

const LIMITS = {
  business_description: { max: 2000, label: "事業内容" },
  offerings: { max: 2000, label: "取扱商品・サービス" },
  target_customers: { max: 1000, label: "得意な客層・地域" },
  self_introduction: { max: 2000, label: "自己紹介" },
} as const;

/**
 * 事業プロフィールの入力を treemerce_update_my_agent_profile の引数に整える。
 * 値の妥当性は DB 側 (0016 の CHECK / RPC) でも必ず再検証される。
 */
export function parseAgentProfileInput(
  body: Record<string, unknown> | null,
): { input: AgentProfileInput } | { error: string } {
  if (!body) return { error: "入力内容が不正です。" };

  const text = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);
  const list = (v: unknown) =>
    Array.isArray(v)
      ? [...new Set(v.filter((x): x is string => typeof x === "string").map((x) => x.trim()).filter(Boolean))]
      : [];

  const industry = text(body.industry);
  if (industry && !(AGENT_INDUSTRIES as readonly string[]).includes(industry)) {
    return { error: "業種を選択し直してください。" };
  }

  const texts = {} as Record<keyof typeof LIMITS, string | null>;
  for (const key of Object.keys(LIMITS) as (keyof typeof LIMITS)[]) {
    const value = text(body[key]);
    if (value && value.length > LIMITS[key].max) {
      return { error: `${LIMITS[key].label}は ${LIMITS[key].max} 文字以内で入力してください。` };
    }
    texts[key] = value;
  }

  const prefectures = list(body.activity_prefectures);
  if (prefectures.some((p) => !(PREFECTURES as readonly string[]).includes(p))) {
    return { error: "活動エリアの都道府県が正しくありません。" };
  }

  const website = text(body.website_url);
  if (website && !isHttpUrl(website)) {
    return { error: "Web サイトの URL は http:// または https:// で始めてください。" };
  }

  const sns = list(body.sns_urls);
  if (sns.length > 5) return { error: "SNS の URL は 5 件までです。" };
  if (sns.some((u) => !isHttpUrl(u))) {
    return { error: "SNS の URL は http:// または https:// で始めてください。" };
  }

  return {
    input: {
      p_industry: industry,
      p_business_description: texts.business_description,
      p_offerings: texts.offerings,
      p_target_customers: texts.target_customers,
      p_activity_prefectures: prefectures,
      p_website_url: website,
      p_sns_urls: sns,
      p_self_introduction: texts.self_introduction,
    },
  };
}
