import { ChevronRight, Search } from "lucide-react";
import Link from "next/link";

import {
  BUTTON_CLASS,
  DataTable,
  EmptyState,
  FIELD_CLASS,
  Field,
  FilterPanel,
  Mono,
  Notice,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDate,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import {
  AGE_GROUP_LABELS,
  CUSTOMER_TYPE_LABELS,
  GENDER_LABELS,
  PREFECTURES,
  PRODUCT_CATEGORIES,
  PRODUCT_CATEGORY_LABELS,
} from "@/lib/domain/enums";

type Row = {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  prefecture: string | null;
  age_group: string | null;
  gender: string | null;
  customer_type: string;
  created_at: string;
  assignments: {
    id: string;
    status: string;
    assigned_at: string;
    agent: { id: string; public_id: string; display_name: string } | null;
  }[];
};

/**
 * STEP8 + 統括管理: 商品購入者の横断一覧・検索。super_admin 専用 (requireSuperAdminPage)。
 * CASE10: 購入者に紐づくのは「担当代理店」だけ。
 *         代理店の招待経路 (invited_by) はこの画面には一切出さない。
 */
export default async function AdminCustomersPage({
  searchParams,
}: {
  searchParams: Promise<{
    q?: string;
    prefecture?: string;
    agent_id?: string;
    category?: string;
  }>;
}) {
  const { q, prefecture, agent_id: agentId, category } = await searchParams;
  const { supabase } = await requireSuperAdminPage("/admin/customers");

  // 担当代理店フィルタ用の候補一覧
  const { data: agentOptionsData } = await supabase
    .from("agents")
    .select("id, public_id, display_name")
    .order("public_id");
  const agentOptions = (agentOptionsData ?? []) as {
    id: string;
    public_id: string;
    display_name: string;
  }[];

  // 「担当代理店」「購入カテゴリ」は別テーブル経由の絞り込みのため、
  // 対象となる customer_id 集合を先に求めてから customers.in(...) で絞る。
  let idFilters: Set<string> | null = null;

  if (agentId) {
    const { data } = await supabase
      .from("customer_assignments")
      .select("customer_id")
      .eq("assigned_agent_id", agentId)
      .eq("status", "active");
    const ids = new Set((data ?? []).map((r) => r.customer_id as string));
    idFilters = idFilters ? intersect(idFilters, ids) : ids;
  }

  if (category) {
    const { data } = await supabase
      .from("purchases")
      .select("customer_id")
      .eq("product_category", category);
    const ids = new Set((data ?? []).map((r) => r.customer_id as string));
    idFilters = idFilters ? intersect(idFilters, ids) : ids;
  }

  if (idFilters && idFilters.size === 0) {
    return renderPage([], { q, prefecture, agentId, category }, agentOptions);
  }

  let query = supabase
    .from("customers")
    .select(
      `id, full_name, email, phone, prefecture, age_group, gender, customer_type, created_at,
       assignments:customer_assignments (
         id, status, assigned_at,
         agent:agents!customer_assignments_assigned_agent_id_fkey ( id, public_id, display_name )
       )`,
    )
    .order("created_at", { ascending: false })
    .limit(200);

  const term = q?.trim();
  if (term) {
    const safe = term.replace(/[,()%]/g, "");
    query = query.or(`full_name.ilike.%${safe}%,email.ilike.%${safe}%,phone.ilike.%${safe}%`);
  }
  if (prefecture) {
    query = query.eq("prefecture", prefecture);
  }
  if (idFilters) {
    query = query.in("id", Array.from(idFilters));
  }

  const { data } = await query;
  const customers = (data ?? []) as unknown as Row[];

  return renderPage(customers, { q, prefecture, agentId, category }, agentOptions);
}

function intersect(a: Set<string>, b: Set<string>): Set<string> {
  const out = new Set<string>();
  for (const v of a) if (b.has(v)) out.add(v);
  return out;
}

function renderPage(
  customers: Row[],
  filters: { q?: string; prefecture?: string; agentId?: string; category?: string },
  agentOptions: { id: string; public_id: string; display_name: string }[],
) {
  const { q, prefecture, agentId, category } = filters;
  const hasFilter = Boolean(q || prefecture || agentId || category);

  return (
    <>
      <PageHeader
        title="商品購入者管理"
        description="全購入者を横断して検索し、購入内容・購入額・現在の担当代理店を確認します。"
      />

      <Notice tone="info">
        この画面では購入者の実名・連絡先・購入内容を匿名化せずに表示します(super_admin 専用)。
        代理店同士の招待経路とは別のデータです。担当の変更は各顧客の詳細ページから行います。
      </Notice>

      <FilterPanel>
        <form method="get" className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Field label="検索 (氏名・email・電話)" className="sm:col-span-2 lg:col-span-4">
            <input
              type="text"
              name="q"
              defaultValue={q ?? ""}
              className={FIELD_CLASS}
              placeholder="例: 山田 / yamada@example.com"
            />
          </Field>
          <Field label="都道府県">
            <select name="prefecture" defaultValue={prefecture ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {PREFECTURES.map((p) => (
                <option key={p} value={p}>
                  {p}
                </option>
              ))}
            </select>
          </Field>
          <Field label="担当代理店">
            <select name="agent_id" defaultValue={agentId ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {agentOptions.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.public_id} {a.display_name}
                </option>
              ))}
            </select>
          </Field>
          <Field label="購入カテゴリ">
            <select name="category" defaultValue={category ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {PRODUCT_CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {PRODUCT_CATEGORY_LABELS[c]}
                </option>
              ))}
            </select>
          </Field>
          <div className="flex items-end gap-3">
            <button type="submit" className={`${BUTTON_CLASS} flex-1`}>
              <Search size={16} />
              検索
            </button>
            {hasFilter ? (
              <Link
                href="/admin/customers"
                className="whitespace-nowrap pb-2.5 text-[13px] font-medium text-text-secondary hover:text-text-primary"
              >
                クリア
              </Link>
            ) : null}
          </div>
        </form>
      </FilterPanel>

      <SectionTitle count={customers.length}>購入者一覧</SectionTitle>

      {customers.length === 0 ? (
        <EmptyState title="該当する購入者がいません" />
      ) : (
        <DataTable headers={["氏名", "連絡先", "属性", "現在の担当代理店", "登録日", ""]}>
          {customers.map((customer) => {
            const active = customer.assignments?.find((a) => a.status === "active");
            return (
              <tr key={customer.id}>
                <td className={TD_STRONG}>
                  <Link href={`/admin/customers/${customer.id}`} className="hover:text-brand">
                    {customer.full_name}
                  </Link>
                </td>
                <td className={TD}>
                  {customer.email ?? "—"}
                  <br />
                  {customer.phone ?? "—"}
                </td>
                <td className={TD}>
                  {customer.age_group
                    ? (AGE_GROUP_LABELS[customer.age_group] ?? customer.age_group)
                    : "未回答"}{" "}
                  /{" "}
                  {customer.gender ? (GENDER_LABELS[customer.gender] ?? customer.gender) : "未回答"}
                  <br />
                  {customer.prefecture ?? "—"} ·{" "}
                  {CUSTOMER_TYPE_LABELS[customer.customer_type] ?? customer.customer_type}
                </td>
                <td className={TD}>
                  {active?.agent ? (
                    <>
                      <Mono>{active.agent.public_id}</Mono>{" "}
                      <span className="text-text-primary">{active.agent.display_name}</span>
                      <br />
                      <span className="text-[11px] text-text-secondary">
                        {formatDate(active.assigned_at)} から
                      </span>
                    </>
                  ) : (
                    <span className="text-text-secondary">担当なし</span>
                  )}
                </td>
                <td className={TD}>{formatDate(customer.created_at)}</td>
                <td className={`${TD} text-right`}>
                  <Link
                    href={`/admin/customers/${customer.id}`}
                    className="inline-flex items-center gap-0.5 whitespace-nowrap text-[13px] font-semibold text-brand hover:underline"
                  >
                    詳細
                    <ChevronRight size={14} />
                  </Link>
                </td>
              </tr>
            );
          })}
        </DataTable>
      )}
    </>
  );
}
