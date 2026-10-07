import { BackLink, Card, PageHeader } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";

import { ProducerForm } from "../ProducerForm";

export default async function AdminProducerNewPage() {
  await requireSuperAdminPage("/admin/producers/new");

  return (
    <>
      <BackLink href="/admin/producers">生産者一覧</BackLink>
      <PageHeader
        title="生産者を登録"
        description="登録後、商品の編集画面で生産者を選ぶと商品ページに生産者名・産地・発送元・発送目安が表示されます。"
      />
      <Card>
        <ProducerForm />
      </Card>
    </>
  );
}
