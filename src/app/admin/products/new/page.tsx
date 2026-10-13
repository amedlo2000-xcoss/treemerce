import { BackLink, Card, PageHeader } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";

import { ProductForm } from "../ProductForm";
import { loadProducerOptions } from "../producer-options";
import { loadAdminCategories } from "@/lib/catalog-categories";

export default async function AdminProductNewPage() {
  const { supabase } = await requireSuperAdminPage("/admin/products/new");
  const [producers, categories] = await Promise.all([loadProducerOptions(supabase), loadAdminCategories(supabase)]);

  return (
    <>
      <BackLink href="/admin/products">商品一覧</BackLink>
      <PageHeader
        title="商品を登録"
        description="登録時は「非公開」または「準備中」にしておき、価格・内容を確認してから公開できます。"
      />
      <Card>
        <ProductForm producers={producers} categories={categories} />
      </Card>
    </>
  );
}
