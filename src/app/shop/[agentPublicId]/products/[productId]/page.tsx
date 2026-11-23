import { ProductView } from "../../../_components/ProductView";

/** 紹介リンクのショップ: 商品詳細 (未ログインで閲覧できる。カートに入れられるのは会員だけ) */
export default async function ShopProductPage({
  params,
}: {
  params: Promise<{ agentPublicId: string; productId: string }>;
}) {
  const { agentPublicId, productId } = await params;
  return <ProductView agentPublicId={agentPublicId} productId={productId} />;
}
