import { redirect } from "next/navigation";

/** 旧 URL。オブザーバー特典付き製品一覧 (/observer-products) へ転送する。 */
export default function LegacyObserverSamplesPage() {
  redirect("/observer-products");
}
