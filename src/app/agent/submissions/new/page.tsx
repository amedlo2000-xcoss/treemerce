import { MobilePageHeader, Surface } from "@/components/mobile/primitives";
import { BackLink } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";

import { SubmissionForm } from "../SubmissionForm";

/** 持込み申請の新規作成 (下書き)。画像は下書き保存後に詳細ページで追加する。 */
export default async function AgentSubmissionNewPage() {
  await requireAgentPage("/agent/submissions/new");

  return (
    <>
      <BackLink href="/agent/submissions">持込み申請</BackLink>
      <MobilePageHeader
        title="新しく申請する"
        description="まずは下書きとして保存されます。途中まででも保存できます。"
      />
      <Surface>
        <SubmissionForm />
      </Surface>
    </>
  );
}
