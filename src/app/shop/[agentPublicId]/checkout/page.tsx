import { fetchShopCatalog } from "@/lib/shop/catalog";

import { InvalidShopLink } from "../ShopParts";
import { CheckoutFlow } from "./CheckoutFlow";

/**
 * 公開ショップ: カート確認 → お客様情報 → お届け先 → 確認 → 注文完了 (振込先表示)。
 * 表示用の価格は最新の商品一覧から取るが、注文時の金額はサーバー側で必ず再計算される。
 */
export default async function ShopCheckoutPage({
  params,
}: {
  params: Promise<{ agentPublicId: string }>;
}) {
  const { agentPublicId } = await params;
  const catalog = await fetchShopCatalog(agentPublicId);
  if (!catalog.valid) return <InvalidShopLink />;

  return (
    <CheckoutFlow
      agentPublicId={agentPublicId}
      products={catalog.products}
      shippingFee={Number(catalog.shipping_fee)}
      acceptingOrders={catalog.accepting_orders}
    />
  );
}
