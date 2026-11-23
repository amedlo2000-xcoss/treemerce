/**
 * オブザーバーの報酬 (0033) の型・表示ラベル。
 * データはすべて 0033 の RPC から取得する (テーブルを直接組み合わせて復元しない)。
 */

export const AGENT_RANKS = ["general", "level3", "level4", "level5"] as const;
export type AgentRank = (typeof AGENT_RANKS)[number];

export const AGENT_RANK_LABELS: Record<AgentRank, string> = {
  general: "一般",
  level3: "レベル3",
  level4: "レベル4",
  level5: "レベル5",
};

export function rankLabel(rank: string | null | undefined): string {
  if (!rank) return "—";
  return AGENT_RANK_LABELS[rank as AgentRank] ?? rank;
}

export type RewardRole = "seller" | "referrer" | "operator";
export type RewardKind = "accrual" | "reversal";

/** 運営画面の区分 */
export const REWARD_ROLE_LABELS: Record<RewardRole, string> = {
  seller: "出店者",
  referrer: "紹介者",
  operator: "運営",
};

/** オブザーバー本人に見せる区分 */
export const MY_REWARD_ROLE_LABELS: Record<string, string> = {
  seller: "出店者報酬",
  referrer: "紹介報酬",
};

/** 0.2 → "20%" (小数第 2 位まで、末尾の 0 は省く) */
export function formatRate(rate: number | string | null | undefined): string {
  if (rate == null || rate === "") return "—";
  const n = Number(rate);
  if (!Number.isFinite(n)) return "—";
  return `${Number((n * 100).toFixed(2))}%`;
}

/** treemerce_admin_list_reward_rates の戻り値 */
export type RewardRates = {
  seller_rate: number;
  pool_rate: number;
  no_referrer_operator_rate: number;
  ranks: {
    rank: AgentRank;
    rank_label: string;
    referrer_rate: number;
    operator_rate: number;
    updated_at: string;
  }[];
};

/** treemerce_admin_list_reward_entries の 1 行 */
export type AdminRewardEntry = {
  id: string;
  order_id: string;
  order_no: string;
  entry_kind: RewardKind;
  recipient_role: RewardRole;
  recipient_agent_id: string | null;
  recipient_name: string | null;
  recipient_public_id: string | null;
  seller_agent_id: string;
  seller_name: string;
  seller_public_id: string;
  referrer_agent_id: string | null;
  referrer_name: string | null;
  referrer_public_id: string | null;
  referrer_rank: AgentRank | null;
  referrer_rank_label: string | null;
  referrer_rate: number | null;
  base_amount: number;
  rate: number;
  amount: number;
  product_lines: { product_id: string; product_name: string; quantity: number; amount: number }[];
  reverses_entry_id: string | null;
  reason: string | null;
  settled_on: string;
  created_at: string;
};

/** treemerce_my_reward_entries の戻り値 (購入者・注文番号は含まれない) */
export type MyRewards = {
  rank: AgentRank;
  rank_label: string;
  total_amount: number;
  entries: {
    id: string;
    role: RewardRole;
    kind: RewardKind;
    product_names: string[];
    amount: number;
    date: string;
    base_amount?: number;
    rate?: number;
  }[];
};
