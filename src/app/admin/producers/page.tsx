import { Plus } from "lucide-react";
import Link from "next/link";

import {
  Badge,
  DataTable,
  EmptyState,
  LinkButton,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDateTime,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import type { ProducerAdminRow } from "@/lib/domain/types";

/**
 * 生産者マスタ (super_admin 専用)。連絡先・発送依頼の送り先を含むため
 * treemerce_admin_list_producers (super_admin RPC) で取得する。
 */
export default async function AdminProducersPage() {
  const { supabase } = await requireSuperAdminPage("/admin/producers");

  const { data } = await supabase.rpc("treemerce_admin_list_producers", { p_producer_id: null });
  const producers = (data ?? []) as ProducerAdminRow[];

  return (
    <>
      <PageHeader
        title="生産者"
        description="商品を直送する生産者を管理します。連絡先・発送依頼の送り先は super_admin のみ閲覧でき、商品ページには公開されません。変更はすべて監査ログに記録されます。"
        action={
          <LinkButton href="/admin/producers/new">
            <Plus size={16} className="mr-1" />
            生産者を登録
          </LinkButton>
        }
      />

      <SectionTitle count={producers.length}>生産者一覧</SectionTitle>

      {producers.length === 0 ? (
        <EmptyState title="生産者がまだありません" />
      ) : (
        <DataTable headers={["生産者名", "産地・発送元", "発送目安", "発送依頼", "商品", "未発送", "状態", "更新日時", ""]}>
          {producers.map((p) => (
            <tr key={p.id}>
              <td className={TD_STRONG}>
                {p.is_placeholder ? (
                  <>
                    {p.name}
                    <div className="text-[12px] font-normal text-text-secondary">
                      既存商品の移行先 (運営が発送)。編集できません
                    </div>
                  </>
                ) : (
                  <Link href={`/admin/producers/${p.id}`} className="hover:text-brand">
                    {p.name}
                  </Link>
                )}
              </td>
              <td className={TD}>
                {p.origin ?? "—"}
                {p.ship_from_prefecture ? (
                  <div className="text-[12px]">発送元: {p.ship_from_prefecture}</div>
                ) : null}
              </td>
              <td className={TD}>{p.ship_lead_time ?? "—"}</td>
              <td className={TD}>
                {p.is_placeholder ? (
                  "—"
                ) : p.notify_email ? (
                  <Badge tone="green">メール設定済み</Badge>
                ) : (
                  <Badge tone="amber">未設定 (手動で依頼)</Badge>
                )}
              </td>
              <td className={`${TD} tabular-nums`}>
                {p.product_count}
                <span className="text-[12px]"> (公開 {p.published_count})</span>
              </td>
              <td className={`${TD} tabular-nums`}>
                {p.open_shipments > 0 ? <Badge tone="blue">{p.open_shipments}</Badge> : 0}
              </td>
              <td className={TD}>
                <Badge tone={p.is_active ? "green" : "neutral"}>{p.is_active ? "有効" : "無効"}</Badge>
              </td>
              <td className={`${TD} whitespace-nowrap`}>{formatDateTime(p.updated_at)}</td>
              <td className={`${TD} text-right`}>
                {p.is_placeholder ? null : (
                  <Link
                    href={`/admin/producers/${p.id}`}
                    className="whitespace-nowrap text-[13px] font-semibold text-brand hover:underline"
                  >
                    編集
                  </Link>
                )}
              </td>
            </tr>
          ))}
        </DataTable>
      )}
    </>
  );
}
