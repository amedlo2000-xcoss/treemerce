import { notFound } from "next/navigation";

import { BackLink, Card, Notice, PageHeader } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import type { ProducerAdminRow } from "@/lib/domain/types";

import { ProducerForm } from "../ProducerForm";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function AdminProducerEditPage({
  params,
  searchParams,
}: {
  params: Promise<{ producerId: string }>;
  searchParams: Promise<{ created?: string }>;
}) {
  const { producerId } = await params;
  const { created } = await searchParams;
  if (!UUID.test(producerId)) notFound();
  const { supabase } = await requireSuperAdminPage(`/admin/producers/${producerId}`);

  const { data } = await supabase.rpc("treemerce_admin_list_producers", { p_producer_id: producerId });
  const producer = ((data ?? []) as ProducerAdminRow[])[0];
  if (!producer || producer.is_placeholder) notFound();

  return (
    <>
      <BackLink href="/admin/producers">生産者一覧</BackLink>
      <PageHeader
        title={producer.name}
        description={`商品 ${producer.product_count} 件 (公開 ${producer.published_count}) ・ 未発送 ${producer.open_shipments} 件`}
      />
      {created ? <Notice tone="info">生産者を登録しました。</Notice> : null}
      <Card>
        <ProducerForm key={producer.updated_at} producer={producer} />
      </Card>
    </>
  );
}
