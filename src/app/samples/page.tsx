import { redirect } from "next/navigation";

/** /samples はサンプル一覧 (現在はオブザーバー特典付き製品・サービスのみ) へ転送する。 */
export default function SamplesIndexPage() {
  redirect("/samples/observer");
}
