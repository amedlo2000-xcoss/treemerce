import { MobilePageHeader, Surface } from "@/components/mobile/primitives";
import { BackLink } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import { loadCatalogCategories } from "@/lib/catalog-categories";

import { SubmissionForm } from "../SubmissionForm";

/** 持込み申請の新規作成 (下書き)。画像は下書き保存後に詳細ページで追加する。 */
export default async function AgentSubmissionNewPage() {
  const { supabase } = await requireAgentPage("/agent/submissions/new");
  const categories = await loadCatalogCategories(supabase);

  return (
    <>
      <BackLink href="/agent/submissions">持込み申請</BackLink>
      <MobilePageHeader
        title="新しく申請する"
        description="まずは下書きとして保存されます。途中まででも保存できます。"
      />
      <Surface>
        <SubmissionForm categories={categories} />
      </Surface>
    </>
  );
}
