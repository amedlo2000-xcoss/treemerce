export const AGENT_STATUSES = ["pending", "active", "suspended", "withdrawn"] as const;
export type AgentStatus = (typeof AGENT_STATUSES)[number];

export const AGENT_STATUS_LABELS: Record<AgentStatus, string> = {
  pending: "承認待ち",
  active: "稼働中",
  suspended: "停止中",
  withdrawn: "退会",
};

export const AGE_GROUPS = [
  "under_20",
  "20s",
  "30s",
  "40s",
  "50s",
  "60s",
  "70_plus",
  "unknown",
] as const;
export type AgeGroup = (typeof AGE_GROUPS)[number];

export const AGE_GROUP_LABELS: Record<string, string> = {
  under_20: "20歳未満",
  "20s": "20代",
  "30s": "30代",
  "40s": "40代",
  "50s": "50代",
  "60s": "60代",
  "70_plus": "70歳以上",
  unknown: "未回答",
};

export const GENDERS = ["male", "female", "other", "prefer_not_to_say"] as const;
export type Gender = (typeof GENDERS)[number];

export const GENDER_LABELS: Record<string, string> = {
  male: "男性",
  female: "女性",
  other: "その他",
  prefer_not_to_say: "未回答",
};

export const CUSTOMER_TYPES = ["individual", "corporate", "sole_proprietor", "other"] as const;
export type CustomerType = (typeof CUSTOMER_TYPES)[number];

export const CUSTOMER_TYPE_LABELS: Record<string, string> = {
  individual: "個人",
  corporate: "法人",
  sole_proprietor: "個人事業主",
  other: "その他",
};

export const PRODUCT_CATEGORIES = [
  "health",
  "beauty",
  "food",
  "apparel",
  "household",
  "digital",
  "service",
  "other",
] as const;
export type ProductCategory = (typeof PRODUCT_CATEGORIES)[number];

export const PRODUCT_CATEGORY_LABELS: Record<string, string> = {
  health: "健康",
  beauty: "美容",
  food: "食品",
  apparel: "アパレル",
  household: "生活用品",
  digital: "デジタル",
  service: "サービス",
  other: "その他",
};

export const BENEFIT_TYPES = [
  "referral_bonus",
  "sales_commission",
  "tier_bonus",
  "adjustment",
] as const;
export type BenefitType = (typeof BENEFIT_TYPES)[number];

export const BENEFIT_TYPE_LABELS: Record<string, string> = {
  referral_bonus: "紹介ボーナス",
  sales_commission: "販売手数料",
  tier_bonus: "ランクボーナス",
  adjustment: "調整",
};

export const BENEFIT_STATUSES = ["pending", "confirmed", "paid", "cancelled"] as const;
export type BenefitStatus = (typeof BENEFIT_STATUSES)[number];

export const BENEFIT_STATUS_LABELS: Record<string, string> = {
  pending: "処理中",
  confirmed: "確定",
  paid: "支払済み",
  cancelled: "取消",
};

export const BANK_ACCOUNT_TYPES = ["ordinary", "checking", "savings"] as const;
export type BankAccountType = (typeof BANK_ACCOUNT_TYPES)[number];

export const BANK_ACCOUNT_TYPE_LABELS: Record<string, string> = {
  ordinary: "普通",
  checking: "当座",
  savings: "貯蓄",
};

export const ASSIGNMENT_SOURCE_LABELS: Record<string, string> = {
  initial_registration: "初回登録",
  admin_transfer: "管理者による変更",
  migration: "データ移行",
  system: "システム",
};

export const ASSIGNMENT_STATUS_LABELS: Record<string, string> = {
  active: "有効",
  superseded: "変更済み",
  released: "解除",
};

export const ANALYTICS_PERIODS = [
  { value: "all", label: "全期間" },
  { value: "1y", label: "直近1年" },
  { value: "3m", label: "直近3ヶ月" },
] as const;
export type AnalyticsPeriod = (typeof ANALYTICS_PERIODS)[number]["value"];

export const PREFECTURES = [
  "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
  "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
  "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
  "岐阜県", "静岡県", "愛知県", "三重県",
  "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
  "鳥取県", "島根県", "岡山県", "広島県", "山口県",
  "徳島県", "香川県", "愛媛県", "高知県",
  "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
] as const;

/** 集計軸のキーを日本語ラベルに変換する。未知のキーはそのまま返す。 */
export function labelForBucket(dimension: string, key: string): string {
  if (key === "該当データ少数" || key === "未回答") return key;
  switch (dimension) {
    case "age_group":
      return AGE_GROUP_LABELS[key] ?? key;
    case "gender":
      return GENDER_LABELS[key] ?? key;
    case "customer_type":
      return CUSTOMER_TYPE_LABELS[key] ?? key;
    case "product_category":
      return PRODUCT_CATEGORY_LABELS[key] ?? key;
    case "amount_band":
      return AMOUNT_BAND_LABELS[key] ?? key;
    default:
      return key;
  }
}

export const PURCHASE_STATUS_LABELS: Record<string, string> = {
  pending: "処理中",
  completed: "完了",
  cancelled: "キャンセル",
  refunded: "返金済み",
};

/* ------------------------------------------------------------- 商品・注文 */

export const ORDER_STATUSES = [
  "received",
  "payment_confirmed",
  "shipped",
  "completed",
  "cancelled",
] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const ORDER_STATUS_LABELS: Record<string, string> = {
  received: "注文受付",
  payment_confirmed: "入金確認済み",
  shipped: "発送済み",
  completed: "完了",
  cancelled: "キャンセル",
};

/** DB (0010 の状態遷移トリガ) と同じ遷移表。UI の選択肢を絞るためだけに使う。 */
export const ORDER_NEXT_STATUSES: Record<OrderStatus, OrderStatus[]> = {
  received: ["payment_confirmed", "cancelled"],
  payment_confirmed: ["shipped", "cancelled"],
  shipped: ["completed", "cancelled"],
  completed: [],
  cancelled: [],
};

/** 客層分析の購入金額帯 (0011 の amount_band と同じキー) */
export const AMOUNT_BAND_LABELS: Record<string, string> = {
  lt_10k: "1万円未満",
  "10k_30k": "1万〜3万円",
  "30k_50k": "3万〜5万円",
  "50k_100k": "5万〜10万円",
  gte_100k: "10万円以上",
};
