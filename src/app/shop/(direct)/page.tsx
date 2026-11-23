import { CatalogView } from "../_components/CatalogView";
import { DIRECT_SHOP_TITLE } from "../_components/ShopParts";

/** 運営のショップ: 商品一覧 (/shop。未ログインで閲覧できる。購入は会員のみ) */
export default async function DirectShopPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>;
}) {
  const { category } = await searchParams;
  return <CatalogView agentPublicId={null} title={DIRECT_SHOP_TITLE} category={category} />;
}
