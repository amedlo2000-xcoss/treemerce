import { EmptyState, MobilePageHeader, Surface } from "@/components/mobile/primitives";
import { requireAgentPage } from "@/lib/auth/viewer";

import { CustomerBrowser, type CustomerListItem } from "./CustomerBrowser";

type Row = {
  id: string;
  assigned_at: string;
  assignment_source: string;
  customer: {
    id: string;
    full_name: string;
    email: string | null;
    phone: string | null;
    prefecture: string | null;
    age_group: string | null;
    gender: string | null;
    customer_type: string;
    purchases: { id: string; amount: number; status: string; product_name: string }[];
  } | null;
};

/**
 * STEP4: 担当顧客一覧。
 * RLS により、自分が担当している購入者しかここには現れない。
 * 傘下代理店が担当する購入者は 1 行も返らない (絶対原則5)。
 * 一覧⇄カードスワイプの切替は CustomerBrowser (client) に委譲する。
 */
export default async function AgentCustomersPage() {
  const { supabase } = await requireAgentPage("/agent/customers");

  const { data } = await supabase
    .from("customer_assignments")
    .select(
      `id, assigned_at, assignment_source,
       customer:customers!inner (
         id, full_name, email, phone, prefecture, age_group, gender, customer_type,
         purchases ( id, amount, status, product_name )
       )`,
    )
    .eq("status", "active")
    .order("assigned_at", { ascending: false });

  const rows = (data ?? []) as unknown as Row[];

  const items: CustomerListItem[] = rows
    .filter((row) => row.customer)
    .map((row) => {
      const c = row.customer!;
      const validPurchases = c.purchases.filter(
        (p) => p.status !== "cancelled" && p.status !== "refunded",
      );
      return {
        id: c.id,
        full_name: c.full_name,
        email: c.email,
        phone: c.phone,
        prefecture: c.prefecture,
        age_group: c.age_group,
        gender: c.gender,
        customer_type: c.customer_type,
        assigned_at: row.assigned_at,
        total_amount: validPurchases.reduce((sum, p) => sum + Number(p.amount ?? 0), 0),
        product_names: [...new Set(validPurchases.map((p) => p.product_name))],
      };
    });

  return (
    <>
      <MobilePageHeader
        title="顧客"
        description="あなたが担当している商品購入者です。他の代理店の担当者は表示されません。"
      />

      {items.length === 0 ? (
        <Surface>
          <EmptyState
            title="担当顧客はまだいません"
            description="あなたの登録URLから購入者が登録されると、ここに表示されます。"
          />
        </Surface>
      ) : (
        <CustomerBrowser items={items} />
      )}
    </>
  );
}
