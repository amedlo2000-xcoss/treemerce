import { notFound } from "next/navigation";

import { BackLink, Card, Notice, PageHeader } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import type { ProductRow } from "@/lib/domain/types";

import { ProductForm } from "../ProductForm";

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

  return (
    <>
      <BackLink href="/admin/products">商品一覧</BackLink>
      <PageHeader
        title={product.name}
        description="価格を変更しても、受付済みの注文の金額は変わりません。"
      />
      {created ? <Notice tone="info">商品を登録しました。</Notice> : null}
      <Card>
        <ProductForm key={product.updated_at} product={product} />
      </Card>
    </>
  );
}
