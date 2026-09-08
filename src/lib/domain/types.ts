import type {
  AgeGroup,
  AgentStatus,
  BankAccountType,
  BenefitStatus,
  BenefitType,
  CustomerType,
  Gender,
  ProductCategory,
} from "./enums";

export type AgentRow = {
  id: string;
  auth_user_id: string | null;
  public_id: string;
  display_name: string;
  legal_name: string | null;
  email: string;
  phone: string | null;
  profile_bio: string | null;
  avatar_url: string | null;
  prefecture: string | null;
  registered_at: string;
  status: AgentStatus;
  invited_by: string | null;
  created_at: string;
};

export type CustomerRow = {
  id: string;
  full_name: string;
  full_name_kana: string | null;
  email: string | null;
  phone: string | null;
  postal_code: string | null;
  address_line: string | null;
  first_assigned_at: string;
  age_group: AgeGroup | null;
  gender: Gender | null;
  prefecture: string | null;
  customer_type: CustomerType;
  note: string | null;
  created_at: string;
};

export type PurchaseRow = {
  id: string;
  customer_id: string;
  agent_id: string | null;
  product_category: ProductCategory;
  product_name: string;
  quantity: number;
  unit_price: number;
  amount: number;
  currency: string;
  status: string;
  purchased_at: string;
};

export type BenefitRow = {
  id: string;
  agent_id: string;
  purchase_id: string | null;
  benefit_type: BenefitType;
  amount: number;
  currency: string;
  period_month: string | null;
  status: BenefitStatus;
  paid_at: string | null;
  note: string | null;
  created_at: string;
};

export type BankAccountRow = {
  id: string;
  agent_id: string;
  bank_name: string;
  bank_code: string | null;
  branch_name: string;
  branch_code: string | null;
  account_type: BankAccountType;
  account_number: string;
  account_holder_kana: string;
  created_at: string;
  updated_at: string;
};

export type AssignmentRow = {
  id: string;
  customer_id: string;
  assigned_agent_id: string;
  assigned_at: string;
  assignment_source: string;
  status: string;
};

export type AssignmentHistoryRow = {
  id: string;
  customer_id: string;
  previous_agent_id: string | null;
  new_agent_id: string;
  reason: string;
  changed_by: string | null;
  changed_by_role: string;
  changed_at: string;
};

export type AuditLogRow = {
  id: string;
  actor_user_id: string | null;
  actor_role: string;
  action: string;
  target_table: string;
  target_id: string | null;
  before_state: Record<string, unknown> | null;
  after_state: Record<string, unknown> | null;
  reason: string | null;
  created_at: string;
};

/* ---------------------------------------------------------------- 商流マップ */

export type CommerceMapAgent = {
  agent_id: string;
  public_id: string;
  display_name: string;
  status: AgentStatus;
  depth: number;
  invited_by: string | null;
  is_self: boolean;
  customer_count: number;
};

/** 自分が担当している顧客のみこの形になる。 */
export type CommerceMapNamedCustomer = {
  anonymous: false;
  customer_id: string;
  agent_id: string;
  label: string;
  email: string | null;
  phone: string | null;
  prefecture: string | null;
  assigned_at: string;
  purchases: {
    purchase_id: string;
    product_name: string;
    product_category: ProductCategory;
    quantity: number;
    amount: number;
    purchased_at: string;
  }[];
};

/** 傘下の他代理店が担当する顧客。実データは1つも含まれない。 */
export type CommerceMapAnonymousCustomer = {
  anonymous: true;
  customer_id: null;
  agent_id: string;
  label: string;
};

export type CommerceMapCustomer = CommerceMapNamedCustomer | CommerceMapAnonymousCustomer;

export type CommerceMap = {
  viewer_role: "admin" | "agent";
  root_agent_id: string | null;
  scope: "all" | "subtree";
  agents: CommerceMapAgent[];
  customers: CommerceMapCustomer[];
  generated_at: string;
};

/* -------------------------------------------------------- コミュニティマップ */

export type CommunityMapNode = {
  agent_id: string;
  public_id: string;
  display_name: string;
  status: AgentStatus;
  prefecture: string | null;
  depth: number;
  is_self: boolean;
  registered_at: string;
};

export type CommunityMap = {
  root_agent_id: string | null;
  nodes: CommunityMapNode[];
  edges: { from: string; to: string }[];
  generated_at: string;
};

/* ------------------------------------------------------------------ 客層分析 */

export type DemographicsBucket = {
  key: string;
  count: number;
  ratio: number;
};

export type Demographics = {
  scope: "all" | "subtree";
  root_agent_id: string | null;
  period: string;
  k_threshold: number;
  total_customers: number;
  scope_agent_count: number;
  age_group: DemographicsBucket[];
  gender: DemographicsBucket[];
  prefecture: DemographicsBucket[];
  customer_type: DemographicsBucket[];
  product_category: DemographicsBucket[];
  generated_at: string;
};

export const DEMOGRAPHIC_DIMENSIONS = [
  { key: "age_group", title: "年代別構成比" },
  { key: "gender", title: "性別構成比" },
  { key: "prefecture", title: "地域別構成比" },
  { key: "customer_type", title: "顧客タイプ別構成比" },
  { key: "product_category", title: "購入商品カテゴリ別構成比" },
] as const;
