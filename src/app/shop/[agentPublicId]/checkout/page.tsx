import { fetchShopCatalog } from "@/lib/shop/catalog";
import { getShopMember } from "@/lib/shop/member";

import { InvalidShopLink } from "../ShopParts";
import { CheckoutFlow } from "./CheckoutFlow";

/**
 * 紹介リンクのショップ: カート確認 → (お客様情報) → お届け先 → 確認 → 注文完了 (振込先表示)。
 * カートは未ログインでも見られるが、注文手続きは会員 (ログイン中) だけ。氏名・連絡先は会員情報から入れる。
 * 表示用の価格は最新の商品一覧から取るが、注文時の金額はサーバー側で必ず再計算される。
 */
export default async function ShopCheckoutPage({
  params,
}: {
  params: Promise<{ agentPublicId: string }>;
}) {
  const { agentPublicId } = await params;
  const [catalog, member] = await Promise.all([fetchShopCatalog(agentPublicId), getShopMember()]);
  if (!catalog.valid) return <InvalidShopLink />;

  return (
    <CheckoutFlow
      agentPublicId={agentPublicId}
      products={catalog.products}
      shippingFee={Number(catalog.shipping_fee)}
      acceptingOrders={catalog.accepting_orders}
      member={member}
    />
  );
}
