import { fetchShopOwnerName } from "@/lib/shop/catalog";

import { CatalogView } from "../_components/CatalogView";

/**
 * 紹介リンクのショップ: 商品一覧 (未ログインで閲覧できる。購入は会員のみ)。
 * 上部にリンクのオブザーバーの表示名だけを出す (購入者・他のオブザーバーの情報は出さない)。
 */
export default async function ShopPage({
  params,
  searchParams,
}: {
  params: Promise<{ agentPublicId: string }>;
  searchParams: Promise<{ category?: string }>;
}) {
  const { agentPublicId } = await params;
  const { category } = await searchParams;
  const ownerName = await fetchShopOwnerName(agentPublicId);

  return (
    <CatalogView
      agentPublicId={agentPublicId}
      title={ownerName ? `${ownerName}さんのショップ` : "ショップ"}
      category={category}
    />
  );
}
