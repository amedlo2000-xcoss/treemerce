import Link from "next/link";
import { notFound } from "next/navigation";

import { BackLink, Card, Mono, Notice, PageHeader } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import type { AdminSubmissionListItem, ProductRow } from "@/lib/domain/types";

import { ProductForm } from "../ProductForm";
import { loadProducerOptions } from "../producer-options";

export default async function AdminProductEditPage({
  params,
  searchParams,
}: {
  params: Promise<{ productId: string }>;
  searchParams: Promise<{ created?: string }>;
}) {
  const { productId } = await params;
  const { created } = await searchParams;
  const { supabase } = await requireSuperAdminPage(`/admin/products/${productId}`);

  const { data } = await supabase.from("products").select("*").eq("id", productId).maybeSingle();
  const product = data as ProductRow | null;
  if (!product) notFound();
  const producers = await loadProducerOptions(supabase, product.producer_id);

  // 持込み元 (0017)。product_sources は直接読めないため、super_admin 用の申請一覧 RPC から引く。
  const { data: approvedData } = await supabase.rpc("treemerce_admin_list_submissions", { p_status: "approved" });
  const source = ((approvedData ?? []) as AdminSubmissionListItem[]).find(
    (s) => s.approved_product_id === product.id,
  );

  return (
    <>
      <BackLink href="/admin/products">商品一覧</BackLink>
      <PageHeader
        title={product.name}
        description="価格を変更しても、受付済みの注文の金額は変わりません。"
      />
      {created ? <Notice tone="info">商品を登録しました。</Notice> : null}
      {source ? (
        <Notice tone={product.is_published ? "info" : "warning"}>
          持込み商品です (持込み代理店: <Mono>{source.agent_public_id}</Mono> {source.agent_display_name} / 申請{" "}
          <Link href={`/admin/submissions/${source.id}`} className="font-semibold text-brand hover:underline">
            {source.submission_no}
          </Link>
          )。持込み代理店はショップには表示されません。
          {product.is_published
            ? null
            : " 価格・在庫を確定してから公開してください (公開できるのは super_admin のみで、監査ログに記録されます)。"}
        </Notice>
      ) : null}
      <Card>
        <ProductForm key={product.updated_at} product={product} producers={producers} />
      </Card>
    </>
  );
}
