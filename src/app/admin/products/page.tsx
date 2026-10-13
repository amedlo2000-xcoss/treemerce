import { Plus } from "lucide-react";
import Link from "next/link";

import { ProductPlaceholder } from "@/components/ProductPlaceholder";
import {
  Badge,
  DataTable,
  EmptyState,
  FIELD_CLASS,
  Field,
  FilterPanel,
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
import { loadAdminCategories } from "@/lib/catalog-categories";
import {
  ITEM_KIND_LABELS,
  SALES_STATUSES,
  SALES_STATUS_BADGE,
  SALES_STATUS_LABELS,
  UNDECIDED,
} from "@/lib/domain/product-labels";
import type {
  AdminSubmissionListItem,
  ProducerPublicRow,
  ProductRow,
  ProductSalesStatus,
} from "@/lib/domain/types";
import { productImageUrl } from "@/lib/storage";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 商品管理 (super_admin 専用)。非公開・準備中の商品も含めて全件を表示する。
 * カテゴリ・販売状態・オブザーバー特典付きで絞り込める。
 */
export default async function AdminProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string; status?: string; observer?: string }>;
}) {
  const { category, status, observer } = await searchParams;
  const { supabase } = await requireSuperAdminPage("/admin/products");

  const categoryFilter = category && UUID.test(category) ? category : null;
  const statusFilter = (SALES_STATUSES as string[]).includes(status ?? "") ? (status as ProductSalesStatus) : null;
  const observerOnly = observer === "1";

  let query = supabase
    .from("products")
    .select("*, producer:producers ( id, name, is_active, is_placeholder )")
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });
  if (categoryFilter) query = query.eq("category_id", categoryFilter);
  if (statusFilter) query = query.eq("sales_status", statusFilter);
  if (observerOnly) query = query.eq("has_observer_benefit", true);

  const [{ data }, categories, { data: approvedData }] = await Promise.all([
    query,
    loadAdminCategories(supabase),
    // 持込み商品 (0017)。持込み元は super_admin 用の申請一覧 RPC からのみ引ける。
    supabase.rpc("treemerce_admin_list_submissions", { p_status: "approved" }),
  ]);
  const products = (data ?? []) as (ProductRow & {
    producer: Pick<ProducerPublicRow, "id" | "name" | "is_active" | "is_placeholder"> | null;
  })[];
  const categoryName = new Map(categories.map((c) => [c.id, c.name]));
  const unsetPublished = products.filter((p) => p.sales_status === "on_sale" && p.producer?.is_placeholder).length;
  const sourcedIds = new Set(
    ((approvedData ?? []) as AdminSubmissionListItem[]).map((s) => s.approved_product_id).filter(Boolean),
  );
  const filtered = Boolean(categoryFilter || statusFilter || observerOnly);

  return (
    <>
      <PageHeader
        title="商品管理"
        description="商品の登録・編集、価格・在庫・販売状態 (非公開 / 準備中 / 公開中) の管理を行います。変更はすべて監査ログに記録されます。"
        action={
          <div className="flex flex-wrap gap-2">
            <LinkButton href="/admin/categories" variant="secondary">
              カテゴリ管理
            </LinkButton>
            <LinkButton href="/admin/products/new">
              <Plus size={16} className="mr-1" />
              商品を登録
            </LinkButton>
          </div>
        }
      />

      {unsetPublished > 0 ? (
        <Notice tone="warning">
          生産者が「未設定（運営）」のまま公開中の商品が {unsetPublished} 件あります。
          生産者から直送する商品は、編集画面で正しい生産者を選んでください (運営から発送する商品はそのままで構いません)。
        </Notice>
      ) : null}

      <FilterPanel>
        <form method="get" className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto_auto] lg:items-end">
          <Field label="カテゴリ">
            <select name="category" defaultValue={categoryFilter ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                  {c.is_active ? "" : " (無効)"}
                </option>
              ))}
            </select>
          </Field>
          <Field label="販売状態">
            <select name="status" defaultValue={statusFilter ?? ""} className={FIELD_CLASS}>
              <option value="">すべて</option>
              {SALES_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {SALES_STATUS_LABELS[s]}
                </option>
              ))}
            </select>
          </Field>
          <label className="flex items-center gap-2 rounded-xl border border-border-soft px-3 py-2.5 text-[14px] text-text-primary">
            <input type="checkbox" name="observer" value="1" defaultChecked={observerOnly} className="h-4 w-4" />
            オブザーバー特典付きのみ
          </label>
          <div className="flex items-center gap-3">
            <button type="submit" className="rounded-xl bg-brand px-4 py-2.5 text-[14px] font-semibold text-brand-foreground">
              絞り込む
            </button>
            {filtered ? (
              <Link href="/admin/products" className="whitespace-nowrap text-[13px] font-medium text-text-secondary hover:text-text-primary">
                クリア
              </Link>
            ) : null}
          </div>
        </form>
      </FilterPanel>

      <SectionTitle count={products.length}>商品一覧</SectionTitle>

      {products.length === 0 ? (
        <EmptyState
          title={filtered ? "条件に合う商品はありません" : "商品がまだありません"}
          description={filtered ? undefined : "「商品を登録」から追加してください。"}
        />
      ) : (
        <DataTable headers={["", "商品名", "生産者", "カテゴリ", "価格", "在庫", "状態", "更新日時", ""]}>
          {products.map((p) => {
            const image = productImageUrl(p.image_path);
            return (
              <tr key={p.id}>
                <td className={`${TD} w-16`}>
                  <div className="h-11 w-11 overflow-hidden rounded-xl bg-surface-muted">
                    {image ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={image} alt="" className="h-full w-full object-cover" />
                    ) : (
                      <ProductPlaceholder placeholderKey={p.placeholder_key} itemKind={p.item_kind} className="h-full w-full [&>span]:hidden" />
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
                  <div className="mt-1 flex flex-wrap gap-1">
                    {p.has_observer_benefit ? <Badge tone="blue">オブザーバー特典付き</Badge> : null}
                    {p.item_kind === "service" ? <Badge tone="neutral">{ITEM_KIND_LABELS.service}</Badge> : null}
                    {sourcedIds.has(p.id) ? <Badge tone="blue">持込み</Badge> : null}
                    {p.sales_status === "on_sale" && !p.content_volume ? <Badge tone="amber">内容量未入力</Badge> : null}
                  </div>
                </td>
                <td className={TD}>
                  {p.producer?.is_placeholder ? (
                    <>
                      <span>{p.producer.name}</span>
                      {p.sales_status === "on_sale" ? (
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
                <td className={TD}>{categoryName.get(p.category_id) ?? "—"}</td>
                <td className={`${TD} tabular-nums text-text-primary`}>
                  {p.sales_status === "on_sale" ? (
                    <span className="font-semibold">{formatYen(Number(p.price))}</span>
                  ) : (
                    <>
                      <span>{UNDECIDED}</span>
                      {p.price != null ? (
                        <div className="text-[12px] text-text-secondary">予定 {formatYen(Number(p.price))}</div>
                      ) : null}
                    </>
                  )}
                </td>
                <td className={`${TD} tabular-nums`}>
                  {p.sales_status === "on_sale" && p.stock === 0 ? <Badge tone="red">在庫切れ</Badge> : p.stock}
                </td>
                <td className={TD}>
                  <Badge tone={SALES_STATUS_BADGE[p.sales_status]}>{SALES_STATUS_LABELS[p.sales_status]}</Badge>
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
