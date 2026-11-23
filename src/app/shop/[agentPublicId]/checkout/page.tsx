import { CheckoutView } from "../../_components/CheckoutView";

/** 紹介リンクのショップ: カート確認と注文手続き (注文手続きは会員のみ) */
export default async function ShopCheckoutPage({
  params,
}: {
  params: Promise<{ agentPublicId: string }>;
}) {
  const { agentPublicId } = await params;
  return <CheckoutView agentPublicId={agentPublicId} />;
}
