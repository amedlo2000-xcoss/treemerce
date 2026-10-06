import type {
  AgeGroup,
  AgentStatus,
  BankAccountType,
  BenefitStatus,
  BenefitType,
  CustomerType,
  Gender,
  OrderStatus,
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
  /** 0013: カテゴリごとの購入者の人数 (入金確認済み以降の注文 + 完了済み購入) */
  product_category: DemographicsBucket[];
  /** 0011: 顧客ごとの購入金額合計の帯 × 人数 */
  amount_band: DemographicsBucket[];
  purchasing_customers: number;
  /** 購入者が k 未満のときは null (個人の購入額が逆算できないように) */
  total_sales: number | null;
  generated_at: string;
};

export const DEMOGRAPHIC_DIMENSIONS = [
  { key: "age_group", title: "年代別構成比" },
  { key: "gender", title: "性別構成比" },
  { key: "prefecture", title: "地域別構成比" },
  { key: "customer_type", title: "顧客タイプ別構成比" },
  { key: "product_category", title: "購入商品カテゴリ別 (購入者数)" },
  { key: "amount_band", title: "購入金額帯別 (購入者数)" },
] as const;

/* -------------------------------------------------------------- 商品・注文 */

export type ProductRow = {
  id: string;
  sku: string | null;
  name: string;
  description: string | null;
  category: ProductCategory;
  price: number;
  stock: number;
  is_published: boolean;
  image_path: string | null;
  sort_order: number;
  created_at: string;
  updated_at: string;
};

/** 公開ショップ RPC (treemerce_shop_products) が返す商品。在庫の正確な数は含まれない。 */
export type ShopProduct = {
  id: string;
  name: string;
  description: string | null;
  category: ProductCategory;
  price: number;
  image_path: string | null;
  in_stock: boolean;
  low_stock: boolean;
  max_quantity: number;
};

export type ShopCatalog =
  | { valid: false }
  | { valid: true; accepting_orders: boolean; shipping_fee: number; products: ShopProduct[] };

/**
 * orders テーブルのうち一般代理店に列 GRANT がある列だけ。
 * referral_agent_id / identity_mismatch は ADMIN 専用 (treemerce_admin_get_order 経由)。
 * agent_id (帰属代理店) は代理店向け画面では表示しない。
 */
export type OrderRow = {
  id: string;
  order_no: string;
  customer_id: string;
  status: OrderStatus;
  subtotal: number;
  shipping_fee: number;
  total: number;
  ship_name: string;
  ship_postal_code: string | null;
  ship_address: string;
  ship_phone: string | null;
  contact_email: string | null;
  contact_phone: string | null;
  customer_note: string | null;
  ordered_at: string;
  payment_due_date: string;
  paid_at: string | null;
  shipped_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
};

export type OrderItemRow = {
  id: string;
  order_id: string;
  product_id: string;
  product_name: string;
  product_sku: string | null;
  product_category: ProductCategory;
  unit_price: number;
  quantity: number;
  amount: number;
};

export type OrderStatusHistoryRow = {
  id: string;
  order_id: string;
  from_status: OrderStatus | null;
  to_status: OrderStatus;
  reason: string;
  changed_by: string | null;
  changed_by_role: string;
  changed_at: string;
};

type AgentRef = { id: string; public_id: string; display_name: string } | null;

/** treemerce_admin_get_order の戻り値 (super_admin 専用) */
export type AdminOrderDetail = {
  order: OrderRow & {
    agent_id: string;
    referral_agent_id: string | null;
    identity_mismatch: boolean;
  };
  customer: { id: string; full_name: string; email: string | null; phone: string | null } | null;
  agent: AgentRef;
  referral_agent: AgentRef;
  current_agent: AgentRef;
  items: OrderItemRow[];
  history: OrderStatusHistoryRow[];
};

/** treemerce_place_order の戻り値。新規/既存顧客で同じ形 (原則6)。 */
export type PlaceOrderResult = {
  status: "received";
  order_no: string;
  ordered_at: string;
  subtotal: number;
  shipping_fee: number;
  total: number;
  items: { product_name: string; unit_price: number; quantity: number; amount: number }[];
  payment: {
    method: "bank_transfer";
    due_date: string;
    bank_name: string | null;
    bank_branch: string | null;
    bank_account_type: BankAccountType | null;
    bank_account_number: string | null;
    bank_account_holder: string | null;
  };
};

export type ShopSettingsRow = {
  seller_name: string | null;
  seller_representative: string | null;
  seller_address: string | null;
  seller_phone: string | null;
  seller_email: string | null;
  business_hours: string | null;
  price_note: string | null;
  additional_fees: string | null;
  payment_method_note: string | null;
  delivery_time: string | null;
  return_policy: string | null;
  extra_notes: string | null;
  shipping_fee: number;
  payment_due_days: number;
  is_accepting_orders: boolean;
  bank_name: string | null;
  bank_branch: string | null;
  bank_account_type: BankAccountType | null;
  bank_account_number: string | null;
  bank_account_holder: string | null;
  updated_at: string;
};

/** treemerce_shop_public_settings (特商法ページ用。振込先は含まれない) */
export type ShopPublicSettings = Omit<
  ShopSettingsRow,
  | "bank_name"
  | "bank_branch"
  | "bank_account_type"
  | "bank_account_number"
  | "bank_account_holder"
  | "is_accepting_orders"
  | "updated_at"
> & { accepting_orders: boolean };

type SuppressedAggregate =
  | { suppressed: false; count: number; total: number }
  | { suppressed: true; count: null; total: null; label: string };

/** treemerce_agent_order_summary (傘下は匿名の件数・金額のみ、n<5 は丸め) */
export type AgentOrderSummary = {
  period: string;
  k_threshold: number;
  own_current: { count: number; total: number };
  own_awaiting_payment: number;
  own_transferred: SuppressedAggregate;
  subtree: SuppressedAggregate;
  generated_at: string;
};
