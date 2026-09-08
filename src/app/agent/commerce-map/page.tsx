import { redirect } from "next/navigation";

/** 組織画面 (タブ) へ統合。旧URLへのアクセスも壊さないためのリダイレクト。 */
export default function CommerceMapRedirect() {
  redirect("/agent/organization?tab=commerce");
}
