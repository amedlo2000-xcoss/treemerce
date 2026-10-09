import { notFound } from "next/navigation";

import { MobilePageHeader, SectionLabel, StatusPill, Surface } from "@/components/mobile/primitives";
import {
  SubmissionImageGallery,
  SubmissionProducerDetails,
  SubmissionProductDetails,
  SubmissionTimeline,
} from "@/components/SubmissionDetails";
import { BackLink, FormMessage, formatDateTime } from "@/components/ui";
import { UUID } from "@/lib/api/submission-input";
import { requireAgentPage } from "@/lib/auth/viewer";
import { SUBMISSION_STATUS_LABELS, SUBMISSION_STATUS_PILL } from "@/lib/domain/enums";
import type { MySubmissionDetail } from "@/lib/domain/types";
import { withSignedUrls } from "@/lib/submission-images";

import { SubmissionForm } from "../SubmissionForm";
import { SubmissionImagesEditor } from "./SubmissionImagesEditor";
import { WithdrawButton } from "./WithdrawButton";

const STATUS_MESSAGES: Record<string, string> = {
  draft: "下書きです。内容と画像を整えて「保存して申請する」を押してください。",
  submitted: "運営が内容を確認しています。確認が終わるまで編集はできません。",
  returned: "運営から修正のお願いがあります。内容を直して、もう一度申請してください。",
  approved: "承認されました。運営が価格・在庫を確定してから販売を始めます。",
  rejected: "今回は取り扱いを見送りました。",
  withdrawn: "この申請は取り下げ済みです。",
};

/**
 * 持込み申請の詳細 (本人のみ)。他の代理店の申請 ID は DB 側で「見つかりません」になる。
 * 下書き・差し戻しのときだけ編集・画像の追加削除・申請・取り下げができる。
 */
export default async function AgentSubmissionDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ submissionId: string }>;
  searchParams: Promise<{ created?: string; submitted?: string }>;
}) {
  const { submissionId } = await params;
  const { created, submitted } = await searchParams;
  if (!UUID.test(submissionId)) notFound();
  const { supabase } = await requireAgentPage(`/agent/submissions/${submissionId}`);

  const { data, error } = await supabase.rpc("treemerce_my_submission", { p_submission_id: submissionId });
  if (error || !data) notFound();
  const submission = data as MySubmissionDetail;
  const images = await withSignedUrls(supabase, submission.images);

  return (
    <>
      <BackLink href="/agent/submissions">持込み申請</BackLink>
      <MobilePageHeader title={submission.name} description={submission.submission_no} />

      {created ? <FormMessage tone="success">下書きを保存しました。画像を追加できます。</FormMessage> : null}
      {submitted ? <FormMessage tone="success">申請しました。運営の確認をお待ちください。</FormMessage> : null}

      <Surface>
        <div className="flex flex-wrap items-center gap-1.5">
          <StatusPill tone={SUBMISSION_STATUS_PILL[submission.status] ?? "neutral"}>
            {SUBMISSION_STATUS_LABELS[submission.status] ?? submission.status}
          </StatusPill>
          {submission.status === "approved" ? (
            <StatusPill tone={submission.product_is_published ? "success" : "neutral"}>
              {submission.product_is_published ? "販売中" : "販売準備中"}
            </StatusPill>
          ) : null}
        </div>
        <p className="mt-2 text-[14px] leading-6 text-text-primary">{STATUS_MESSAGES[submission.status]}</p>
        {submission.submitted_at ? (
          <p className="mt-1 text-[12px] text-text-secondary">
            最終申請 {formatDateTime(submission.submitted_at)}
            {submission.revision > 1 ? ` (${submission.revision} 回目)` : ""}
          </p>
        ) : null}
        {(submission.status === "returned" || submission.status === "rejected") && submission.review_reason ? (
          <div className="mt-3 rounded-2xl bg-warning-soft px-3.5 py-3">
            <p className="text-[12px] font-semibold text-text-secondary">
              {submission.status === "returned" ? "差し戻しの理由" : "却下の理由"}
            </p>
            <p className="mt-1 whitespace-pre-wrap break-words text-[14px] leading-6 text-text-primary">
              {submission.review_reason}
            </p>
          </div>
        ) : null}
      </Surface>

      {submission.editable ? (
        <>
          <div className="space-y-2">
            <SectionLabel>画像 (任意・5 枚まで)</SectionLabel>
            <Surface>
              <SubmissionImagesEditor submissionId={submission.id} images={images} />
            </Surface>
          </div>
          <div className="space-y-2">
            <SectionLabel>申請内容</SectionLabel>
            <Surface>
              <SubmissionForm key={submission.updated_at} submission={submission} />
            </Surface>
          </div>
          <WithdrawButton submissionId={submission.id} />
        </>
      ) : (
        <div className="space-y-5 md:grid md:grid-cols-2 md:items-start md:gap-6 md:space-y-0">
          <div className="space-y-5">
            <div className="space-y-2">
              <SectionLabel>画像</SectionLabel>
              <Surface>
                <SubmissionImageGallery images={images} />
              </Surface>
            </div>
            <div className="space-y-2">
              <SectionLabel>商品</SectionLabel>
              <Surface>
                <SubmissionProductDetails submission={submission} />
              </Surface>
            </div>
          </div>
          <div className="space-y-5">
            <div className="space-y-2">
              <SectionLabel>生産者</SectionLabel>
              <Surface>
                <SubmissionProducerDetails submission={submission} />
              </Surface>
            </div>
          </div>
        </div>
      )}

      <div className="space-y-2">
        <SectionLabel>履歴</SectionLabel>
        <Surface>
          <SubmissionTimeline events={submission.events} />
        </Surface>
      </div>
    </>
  );
}
