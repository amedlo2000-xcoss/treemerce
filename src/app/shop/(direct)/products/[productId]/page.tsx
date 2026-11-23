import { ProductView } from "../../../_components/ProductView";

/** 運営のショップ: 商品詳細 (/shop/products/{商品ID}) */
export default async function DirectShopProductPage({
  params,
}: {
  params: Promise<{ productId: string }>;
}) {
  const { productId } = await params;
  return <ProductView agentPublicId={null} productId={productId} />;
}
