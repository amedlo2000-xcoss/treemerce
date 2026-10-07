import { ImageOff, Plus } from "lucide-react";
import Link from "next/link";

import {
  Badge,
  DataTable,
  EmptyState,
  LinkButton,
  Mono,
  Notice,
  PageHeader,
  SectionTitle,
  TD,
  TD_STRONG,
  formatDateTime,
  formatYen,
} from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { PRODUCT_CATEGORY_LABELS } from "@/lib/domain/enums";
import type { ProducerPublicRow, ProductRow } from "@/lib/domain/types";
import { productImageUrl } from "@/lib/storage";

/** 商品管理 (super_admin 専用)。非公開の商品も含めて全件を表示する。 */
export default async function AdminProductsPage() {
  const { supabase } = await requireSuperAdminPage("/admin/products");

  const { data } = await supabase
    .from("products")
    .select("*, producer:producers ( id, name, is_active, is_placeholder )")
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });
  const products = (data ?? []) as (ProductRow & {
    producer: Pick<ProducerPublicRow, "id" | "name" | "is_active" | "is_placeholder"> | null;
  })[];
  const unsetPublished = products.filter((p) => p.is_published && p.producer?.is_placeholder).length;

  return (
    <>
      <PageHeader
        title="商品管理"
        description="商品の登録・編集、価格・在庫・公開状態の管理を行います。変更はすべて監査ログに記録されます。"
        action={
          <LinkButton href="/admin/products/new">
            <Plus size={16} className="mr-1" />
            商品を登録
          </LinkButton>
        }
      />

      {unsetPublished > 0 ? (
        <Notice tone="warning">
          生産者が「未設定（運営）」のまま公開中の商品が {unsetPublished} 件あります。
          生産者から直送する商品は、編集画面で正しい生産者を選んでください (運営から発送する商品はそのままで構いません)。
        </Notice>
      ) : null}

      <SectionTitle count={products.length}>商品一覧</SectionTitle>

      {products.length === 0 ? (
        <EmptyState title="商品がまだありません" description="「商品を登録」から追加してください。" />
      ) : (
        <DataTable headers={["", "商品名", "生産者", "カテゴリ", "価格", "在庫", "公開", "更新日時", ""]}>
          {products.map((p) => {
            const image = productImageUrl(p.image_path);
            return (
              <tr key={p.id}>
                <td className={`${TD} w-16`}>
                  <div className="flex h-11 w-11 items-center justify-center overflow-hidden rounded-xl bg-surface-muted">
                    {image ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={image} alt="" className="h-full w-full object-cover" />
                    ) : (
                      <ImageOff size={16} className="text-text-secondary" />
                    )}
                  </div>
                </td>
                <td className={TD_STRONG}>
                  <Link href={`/admin/products/${p.id}`} className="hover:text-brand">
                    {p.name}
                  </Link>
                  {p.sku ? (
                    <div>
                      <Mono>{p.sku}</Mono>
                    </div>
                  ) : null}
                  {p.is_published && !p.content_volume ? (
                    <div className="mt-1">
                      <Badge tone="amber">内容量未入力</Badge>
                    </div>
                  ) : null}
                </td>
                <td className={TD}>
                  {p.producer?.is_placeholder ? (
                    <>
                      <span>{p.producer.name}</span>
                      {p.is_published ? (
                        <div className="mt-1">
                          <Badge tone="amber">生産者未設定のまま公開中</Badge>
                        </div>
                      ) : null}
                    </>
                  ) : (
                    <>
                      <span className="text-text-primary">{p.producer?.name ?? "—"}</span>
                      {p.producer && !p.producer.is_active ? (
                        <div className="mt-1">
                          <Badge tone="red">生産者が無効 (ショップ非表示)</Badge>
                        </div>
                      ) : null}
                    </>
                  )}
                </td>
                <td className={TD}>{PRODUCT_CATEGORY_LABELS[p.category] ?? p.category}</td>
                <td className={`${TD} font-semibold tabular-nums text-text-primary`}>
                  {formatYen(Number(p.price))}
                </td>
                <td className={`${TD} tabular-nums`}>
                  {p.stock === 0 ? <Badge tone="red">在庫切れ</Badge> : p.stock}
                </td>
                <td className={TD}>
                  <Badge tone={p.is_published ? "green" : "neutral"}>
                    {p.is_published ? "公開中" : "非公開"}
                  </Badge>
                </td>
                <td className={`${TD} whitespace-nowrap`}>{formatDateTime(p.updated_at)}</td>
                <td className={`${TD} text-right`}>
                  <Link
                    href={`/admin/products/${p.id}`}
                    className="whitespace-nowrap text-[13px] font-semibold text-brand hover:underline"
                  >
                    編集
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
