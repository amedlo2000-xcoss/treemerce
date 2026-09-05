import { CommerceMapTree } from "@/components/CommerceMapTree";
import { EmptyState, Notice, PageHeader, Stat } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import type { CommerceMap } from "@/lib/domain/types";

/**
 * STEP5: 商流マップ (読み取り専用)。
 *
 * 部分木の算出と匿名化は treemerce_commerce_map (SECURITY DEFINER / STABLE) が
 * サーバー側で行う。このページは返ってきた JSON を描画するだけで、
 * 他代理店担当顧客の実データはそもそも手元に届かない。
 */
export default async function CommerceMapPage() {
  const { supabase } = await requireAgentPage("/agent/commerce-map");

  const { data } = await supabase.rpc("treemerce_commerce_map", { p_root_agent_id: null });
  const map = data as CommerceMap | null;

  const namedCount = map?.customers.filter((c) => !c.anonymous).length ?? 0;
  const anonymousCount = map?.customers.filter((c) => c.anonymous).length ?? 0;

  return (
    <>
      <PageHeader
        title="商流マップ"
        description="あなたを根として、招待経路をたどった傘下の広がりを表示します。招待元や別系統の代理店は含まれません。"
      />

      <Notice tone="info">
        自分が担当する購入者は実名と購入商品を表示します。傘下の他代理店が担当する購入者は、
        件数と匿名ノードのみを表示し、氏名・連絡先・購入商品・販売額は表示されません。
        この画面は閲覧専用で、担当や登録経路が変わることはありません。
      </Notice>

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat label="傘下代理店 (自分を含む)" value={map?.agents.length ?? 0} />
        <Stat label="自分が担当する購入者" value={namedCount} hint="実名で表示" />
        <Stat label="傘下代理店が担当する購入者" value={anonymousCount} hint="匿名ノードで表示" />
      </div>

      {!map || map.agents.length === 0 ? (
        <EmptyState title="表示できるデータがありません" />
      ) : (
        <div className="rounded-xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
          <CommerceMapTree map={map} />
        </div>
      )}
    </>
  );
}
