import { Card, Notice, PageHeader } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { loadAdminCategories } from "@/lib/catalog-categories";

import { CategoryManager } from "./CategoryManager";

/**
 * 商品カテゴリの管理 (super_admin 専用, 0022)。
 * 追加・名称変更 (理由必須)・並べ替え・有効/無効 (理由必須) ができる。削除はできない。
 * 変更はすべて監査ログに残る。カテゴリはショップ・商品管理・一覧ページ・持込み申請の絞り込みに使われる。
 */
export default async function AdminCategoriesPage() {
  const { supabase } = await requireSuperAdminPage("/admin/categories");
  const categories = await loadAdminCategories(supabase);

  return (
    <>
      <PageHeader
        title="カテゴリ管理"
        description="商品カテゴリの追加・名称変更・並べ替え・有効/無効を行います。カテゴリは削除できません (使わなくなったものは無効にしてください)。"
      />
      <Notice tone="info">
        名称を変えても、受付済みの注文明細には注文時点のカテゴリ名が残ります。公開中・準備中の商品が使っているカテゴリは無効にできません。
        無効なカテゴリは、商品・持込み申請で新たに選べなくなります。
      </Notice>
      <Card>
        <CategoryManager categories={categories} />
      </Card>
    </>
  );
}
