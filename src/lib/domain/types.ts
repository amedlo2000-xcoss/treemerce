import type {
  AgeGroup,
  AgentApplicationStatus,
  AgentStatus,
  BankAccountType,
  BenefitStatus,
  BenefitType,
  CustomerType,
  Gender,
  OrderStatus,
  ProductCategory,
  ShipmentStatus,
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

/** 商品の販売状態 (0023)。準備中は価格未定・注文不可で表示する */
export type ProductSalesStatus = "unpublished" | "preparing" | "on_sale";
/** 物品 / サービス (0023)。サービスは発送情報を持たず、公開中 (注文可能) にできない */
export type ProductItemKind = "goods" | "service";

/** 商品カテゴリ (0022 のマスタ)。公開の一覧 (treemerce_catalog_categories) は有効なものだけ */
export type CatalogCategory = {
  id: string;
  code: string;
  name: string;
  sort_order: number;
};

/** treemerce_admin_list_categories の 1 件 (無効を含む) */
export type AdminCategoryRow = CatalogCategory & {
  is_active: boolean;
  legacy_code: string | null;
  in_use: boolean;
  updated_at: string;
};

export type ProductRow = {
  id: string;
  sku: string | null;
  name: string;
  description: string | null;
  /** 旧列挙型 (0026 で廃止予定)。表示には category_id を使う */
  category: ProductCategory;
  category_id: string;
  sales_status: ProductSalesStatus;
  item_kind: ProductItemKind;
  has_observer_benefit: boolean;
  product_type_label: string | null;
  name_kana: string | null;
  placeholder_key: string | null;
  /** 公開中は必須。準備中は運営だけが見られる予定価格 (NULL 可) */
  price: number | null;
  stock: number;
  is_published: boolean;
  image_path: string | null;
  sort_order: number;
  producer_id: string;
  content_volume: string | null;
  ingredients: string | null;
  best_before_note: string | null;
  created_at: string;
  updated_at: string;
};

/**
 * producers の公開項目 (ADMIN が直接 SELECT できる列のみ)。
 * 連絡先・発送依頼の送り先は含まれない (super_admin RPC でのみ取得)。
 */
export type ProducerPublicRow = {
  id: string;
  name: string;
  origin: string | null;
  ship_from_prefecture: string | null;
  ship_lead_time: string | null;
  is_active: boolean;
  is_placeholder: boolean;
};

/** treemerce_admin_list_producers の 1 件 (super_admin 専用。連絡先を含む) */
export type ProducerAdminRow = ProducerPublicRow & {
  notify_email: string | null;
  contact_name: string | null;
  contact_phone: string | null;
  contact_email: string | null;
  note: string | null;
  created_at: string;
  updated_at: string;
  product_count: number;
  published_count: number;
  open_shipments: number;
};

/**
 * 公開ショップで返る生産者の公開項目 (仮の生産者の場合は null)。
 * サービスの商品では発送情報 (発送元・発送目安) は返らない。
 */
export type ShopProducer = {
  id: string;
  name: string;
  origin: string | null;
  ship_from_prefecture?: string | null;
  ship_lead_time?: string | null;
};

/**
 * 公開用の商品 (treemerce_shop_products / treemerce_observer_products, 0023・0025)。
 * 在庫の正確な数・予定価格・生産者の連絡先は含まれない。準備中は price が null。
 */
export type PublicProduct = {
  id: string;
  name: string;
  name_kana: string | null;
  product_type_label: string | null;
  description: string | null;
  category: ProductCategory;
  category_id: string;
  category_code: string;
  category_name: string;
  sales_status: Exclude<ProductSalesStatus, "unpublished">;
  orderable: boolean;
  item_kind: ProductItemKind;
  has_observer_benefit: boolean;
  price: number | null;
  image_path: string | null;
  placeholder_key: string | null;
  content_volume: string | null;
  ingredients: string | null;
  best_before_note: string | null;
  producer: ShopProducer | null;
};

/** 公開ショップ RPC (treemerce_shop_products) が返す商品。在庫の正確な数は含まれない。 */
export type ShopProduct = PublicProduct & {
  in_stock: boolean;
  low_stock: boolean;
  max_quantity: number;
};

/** treemerce_observer_products (0025)。代理店とは紐づかない。在庫の情報は含まれない */
export type ObserverCatalog = {
  products: PublicProduct[];
  categories: CatalogCategory[];
};

export type ShopCatalog =
  | { valid: false }
  | {
      valid: true;
      accepting_orders: boolean;
      shipping_fee: number;
      /** 販売者 (運営) の名称。shop_settings.seller_name */
      seller_name: string | null;
      products: ShopProduct[];
    };

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
  product_category: ProductCategory | null;
  /** 注文時点のカテゴリ (0023 以降の明細。それより前は NULL で旧列挙型を読み替える) */
  product_category_id: string | null;
  product_category_name: string | null;
  unit_price: number;
  quantity: number;
  amount: number;
  product_content_volume: string | null;
};

/** treemerce_admin_get_order の shipments の 1 件 (ADMIN 専用。代理店には返らない) */
export type OrderShipmentRow = {
  id: string;
  order_id: string;
  producer_id: string;
  producer_name: string;
  status: ShipmentStatus;
  carrier: string | null;
  tracking_number: string | null;
  shipped_on: string | null;
  request_channel: "email" | "manual" | null;
  requested_at: string | null;
  request_count: number;
  last_notify_error: string | null;
  is_placeholder: boolean;
  producer_active: boolean;
  ship_lead_time: string | null;
  has_notify_email: boolean;
};

/** treemerce_admin_shipment_request (super_admin 専用の発送依頼書) */
export type ShipmentRequest = {
  shipment_id: string;
  status: ShipmentStatus;
  request_channel: "email" | "manual" | null;
  requested_at: string | null;
  request_count: number;
  order_no: string;
  ordered_at: string;
  paid_at: string | null;
  producer: {
    id: string;
    name: string;
    notify_email: string | null;
    ship_lead_time: string | null;
    is_placeholder: boolean;
  };
  ship_to: { name: string; postal_code: string | null; address: string; phone: string | null };
  customer_note: string | null;
  items: {
    product_name: string;
    product_sku: string | null;
    content_volume: string | null;
    quantity: number;
  }[];
  sender: { name: string | null; address: string | null; phone: string | null; email: string | null };
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
  items: (OrderItemRow & { producer_id: string | null })[];
  shipments: OrderShipmentRow[];
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

/**
 * 代理店の事業プロフィール (0016)。本人 (treemerce_my_agent_profile) と
 * super_admin (treemerce_admin_get_agent_profile) にだけ返る。
 */
export type AgentProfile = {
  found: boolean;
  agent_id: string;
  industry: string | null;
  business_description: string | null;
  offerings: string | null;
  target_customers: string | null;
  activity_prefectures: string[];
  website_url: string | null;
  sns_urls: string[];
  self_introduction: string | null;
  updated_at: string | null;
  /** 最後に更新したのが本人か運営か (0020)。未入力なら null */
  updated_by_role: "agent" | "super_admin" | null;
};

/** treemerce_admin_list_agent_overview の 1 件 (0021)。件数のみで、値・顧客の情報は含まない */
export type AgentOverviewRow = {
  agent_id: string;
  profile_filled_count: number;
  profile_updated_at: string | null;
  profile_updated_by_role: "agent" | "super_admin" | null;
  submission_counts: { proxy_draft: number; submitted: number; returned: number; approved: number };
};

/* ------------------------------------------------ 商品の持込み申請 (0018) */

/** 申請の作成経路 (0021)。admin_proxy は運営が代理店の名義で代行作成した申請 (本人には閲覧のみ) */
export type SubmissionCreatedVia = "agent" | "admin_proxy";

export type SubmissionImage = {
  id: string;
  storage_path: string;
  content_type: string;
  sort_order: number;
};

/** 画面表示用に署名付き URL を付けた画像 (URL はサーバーで短時間だけ有効なものを発行) */
export type SubmissionImageView = SubmissionImage & { url: string | null };

export type SubmissionEvent = {
  revision: number;
  from_status: string | null;
  to_status: string;
  reason: string | null;
  actor_role: string;
  changed_at: string;
  /** super_admin 用の詳細でのみ返る (申請・再申請時点の内容) */
  content_snapshot?: Record<string, unknown> | null;
};

/** 申請の内容 (本人 / super_admin にのみ返る。連絡先を含む) */
export type SubmissionContent = {
  id: string;
  submission_no: string;
  status: string;
  revision: number;
  created_via: SubmissionCreatedVia;
  name: string;
  /** 旧列挙型 (確定済みの古い申請の読み替え用)。表示には category_name を使う */
  category: string | null;
  category_id: string | null;
  category_name: string | null;
  description: string | null;
  desired_price: number | null;
  expected_wholesale_price: number | null;
  content_volume: string | null;
  ingredients: string | null;
  best_before_note: string | null;
  producer_name: string | null;
  producer_origin: string | null;
  producer_ship_from_prefecture: string | null;
  producer_ship_lead_time: string | null;
  producer_contact_name: string | null;
  producer_contact_phone: string | null;
  producer_contact_email: string | null;
  submitted_at: string | null;
  reviewed_at: string | null;
  review_reason: string | null;
  created_at: string;
  updated_at: string;
};

/** treemerce_my_submissions の 1 件 */
export type MySubmissionListItem = {
  id: string;
  submission_no: string;
  status: string;
  revision: number;
  created_via: SubmissionCreatedVia;
  name: string;
  category: string | null;
  category_id: string | null;
  category_name: string | null;
  desired_price: number | null;
  submitted_at: string | null;
  reviewed_at: string | null;
  review_reason: string | null;
  image_count: number;
  product_is_published: boolean | null;
  updated_at: string;
};

/** treemerce_my_submission */
export type MySubmissionDetail = SubmissionContent & {
  editable: boolean;
  images: SubmissionImage[];
  events: SubmissionEvent[];
  product_is_published: boolean | null;
};

/** treemerce_admin_list_submissions の 1 件 (連絡先は含まない) */
export type AdminSubmissionListItem = {
  id: string;
  submission_no: string;
  status: string;
  revision: number;
  created_via: SubmissionCreatedVia;
  name: string;
  category: string | null;
  category_id: string | null;
  category_name: string | null;
  desired_price: number | null;
  producer_name: string | null;
  agent_id: string;
  agent_public_id: string;
  agent_display_name: string;
  image_count: number;
  submitted_at: string | null;
  reviewed_at: string | null;
  approved_product_id: string | null;
  updated_at: string;
};

/** treemerce_admin_get_submission */
export type AdminSubmissionDetail = SubmissionContent & {
  agent: { id: string; public_id: string; display_name: string; status: string };
  /** 代行の申請で、運営が編集できる状態 (下書き・差し戻し) か */
  admin_editable: boolean;
  /** ログイン中の super_admin が作成した申請か */
  created_by_me: boolean;
  images: SubmissionImage[];
  events: SubmissionEvent[];
  approved_product_id: string | null;
  approved_producer_id: string | null;
  product_is_published: boolean | null;
};

/**
 * treemerce_my_sourced_product_sales (0019)。持込み代理店本人の持込み商品の売れ行き。
 * 件数・数量・金額のみ。丸めた商品は値が null。合計は丸めていない商品だけの合計。
 */
export type SourcedProductSalesRow = {
  product_id: string;
  product_name: string;
  submission_no: string;
  is_published: boolean;
  suppressed: boolean;
  label: string | null;
  order_count: number | null;
  quantity: number | null;
  amount: number | null;
};

export type SourcedProductSales = {
  period: string;
  k_threshold: number;
  products: SourcedProductSalesRow[];
  visible_total: { product_count: number; order_count: number; quantity: number; amount: number };
  suppressed_product_count: number;
  generated_at: string;
};

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

/** treemerce_current_agent_terms (公開) */
export type AgentTerms =
  | { available: false }
  | { available: true; version: string; title: string; body: string; body_sha256: string; published_at: string };

/** treemerce_my_agent_application (本人。状態と中立的な文面のみ) */
export type MyAgentApplication = {
  state: "none" | "received" | "approved" | "closed";
  message: string | null;
};

/** treemerce_register_member の応答 (顧客ID・担当代理店・招待元は含まない) */
export type RegisterMemberResult = {
  member_status: "registered" | "duplicate";
  member_message: string | null;
  application_status: "received" | null;
  application_message: string | null;
};

/** treemerce_admin_list_agent_applications / treemerce_admin_get_agent_application (super_admin) */
export type AdminAgentApplication = {
  id: string;
  status: AgentApplicationStatus;
  /**
   * 申請の経路。referral_link = 紹介リンク (招待元あり)、admin_link = 運営の登録リンク (招待元なし・0030)、
   * agent_link = 代理店が発行した登録リンク (招待元 = 発行した代理店・0031)
   */
  source: "referral_link" | "admin_link" | "agent_link";
  auth_user_id: string;
  display_name: string;
  /** 申込者の氏名 (代理店登録リンクからの申し込み。0031 より前の申請は null) */
  applicant_name: string | null;
  email: string;
  phone: string | null;
  created_at: string;
  reviewed_at: string | null;
  reviewed_by: string | null;
  created_agent_id: string | null;
  inviter: { id: string; public_id: string; display_name: string; status: AgentStatus } | null;
  registration_link: { id: string; note: string | null; issuer_agent_id: string | null; state: string } | null;
  terms: {
    version: string;
    title: string;
    body_sha256: string;
    accepted_at: string | null;
    accepted_email: string | null;
    ip_address: string | null;
    user_agent: string | null;
  } | null;
};

export type AdminAgentApplicationDetail = AdminAgentApplication & {
  audit: { action: string; actor_user_id: string | null; actor_role: string; reason: string | null; created_at: string }[];
};

/** 代理店登録リンクの状態 (DB の app.registration_link_state と同じ) */
export type RegistrationLinkState = "active" | "expired" | "exhausted" | "revoked" | "issuer_inactive";

/** treemerce_my_inviter_profile (代理店本人、0009)。招待元の代理店名だけ。招待元がいなければ found = false */
export type MyInviterProfile = { found: true; display_name: string } | { found: false };

/** treemerce_resolve_registration_link (公開)。紹介者は代理店名と代理店IDだけ。運営のリンクは inviter = null */
export type RegistrationLinkResolution =
  | { valid: true; inviter: { public_id: string; display_name: string } | null }
  | { valid: false; reason: "not_found" | "expired" | "exhausted" | "revoked" | "unavailable" };

/** treemerce_my_registration_links (代理店本人。自分が発行したリンクだけ。申し込んだ人の情報は含まない) */
export type MyRegistrationLink = {
  id: string;
  note: string | null;
  status: "active" | "revoked";
  state: RegistrationLinkState;
  max_uses: number | null;
  used_count: number;
  expires_at: string | null;
  created_at: string;
  revoked_at: string | null;
};

/** treemerce_admin_list_registration_links (super_admin。トークンは含まない。代理店が発行したリンクも含む) */
export type AdminRegistrationLink = {
  id: string;
  note: string | null;
  status: "active" | "revoked";
  state: RegistrationLinkState;
  /** 発行した代理店 (= 紹介者)。運営が発行したリンクは null */
  issuer: { id: string; public_id: string; display_name: string; status: AgentStatus } | null;
  max_uses: number | null;
  used_count: number;
  expires_at: string | null;
  created_at: string;
  created_by: string | null;
  revoked_at: string | null;
  applications: { pending: number; approved: number; rejected: number };
};
