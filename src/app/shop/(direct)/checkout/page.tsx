import { CheckoutView } from "../../_components/CheckoutView";

/** 運営のショップ: カート確認と注文手続き (/shop/checkout。注文手続きは会員のみ) */
export default function DirectShopCheckoutPage() {
  return <CheckoutView agentPublicId={null} />;
}
