import { BackLink, Card, PageHeader } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";

import { ProductForm } from "../ProductForm";

export default async function AdminProductNewPage() {
  await requireSuperAdminPage("/admin/products/new");

  return (
    <>
      <BackLink href="/admin/products">商品一覧</BackLink>
      <PageHeader
        title="商品を登録"
        description="登録時は「非公開」のままにしておき、内容を確認してから公開できます。"
      />
      <Card>
        <ProductForm />
      </Card>
    </>
  );
}
