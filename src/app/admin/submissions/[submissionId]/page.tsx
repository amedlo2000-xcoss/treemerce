import Link from "next/link";
import { notFound } from "next/navigation";

import {
  SubmissionImageGallery,
  SubmissionProducerDetails,
  SubmissionProductDetails,
  SubmissionTimeline,
} from "@/components/SubmissionDetails";
import { BackLink, Badge, Card, DetailList, DetailRow, Mono, Notice, PageHeader, formatDateTime } from "@/components/ui";
import { UUID } from "@/lib/api/submission-input";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { AGENT_STATUS_LABELS, SUBMISSION_STATUS_BADGE, SUBMISSION_STATUS_LABELS } from "@/lib/domain/enums";
import type { AdminSubmissionDetail, ProducerPublicRow, SubmissionEvent } from "@/lib/domain/types";
import { findSimilarProducers } from "@/lib/producer-similarity";
import { withSignedUrls } from "@/lib/submission-images";

import { ReviewPanel } from "./ReviewPanel";

const DIFF_LABELS: Record<string, string> = {
  name: "商品名",
  category: "カテゴリ",
  description: "説明",
  desired_price: "希望販売価格",
  expected_wholesale_price: "想定卸値",
  content_volume: "内容量",
  ingredients: "原材料",
  best_before_note: "期限の目安",
  producer_name: "生産者名",
  producer_origin: "産地",
  producer_ship_from_prefecture: "発送元",
  producer_ship_lead_time: "発送目安",
  producer_contact_name: "担当者名",
  producer_contact_phone: "電話番号",
  producer_contact_email: "メール",
  images: "画像",
};

/** 再申請時に、前回の申請時点から変わった項目名を返す */
function changedSincePrevious(events: SubmissionEvent[], index: number): string[] | null {
  const current = events[index];
  if (current.to_status !== "submitted" || !current.content_snapshot) return null;
  const previous = events
    .slice(0, index)
    .reverse()
    .find((e) => e.to_status === "submitted" && e.content_snapshot);
  if (!previous?.content_snapshot) return null;
  const before = previous.content_snapshot;
  const after = current.content_snapshot;
  return Object.keys(DIFF_LABELS).filter((key) => {
    if (key === "images") {
      const ids = (v: unknown) =>
        JSON.stringify(Array.isArray(v) ? v.map((i) => (i as { id?: string }).id).sort() : []);
      return ids(before.images) !== ids(after.images);
    }
    return JSON.stringify(before[key] ?? null) !== JSON.stringify(after[key] ?? null);
  });
}

/**
 * 持込み申請の審査 (super_admin 専用)。生産者の連絡先・申請時点の内容を表示する。
 * 承認時は、申請の生産者名と似た名前の既存生産者を候補として示す。
 */
export default async function AdminSubmissionDetailPage({ params }: { params: Promise<{ submissionId: string }> }) {
  const { submissionId } = await params;
  if (!UUID.test(submissionId)) notFound();
  const { supabase } = await requireSuperAdminPage(`/admin/submissions/${submissionId}`);

  const { data, error } = await supabase.rpc("treemerce_admin_get_submission", { p_submission_id: submissionId });
  if (error || !data) notFound();
  const submission = data as AdminSubmissionDetail;
  const images = await withSignedUrls(supabase, submission.images);

  let candidates: (ProducerPublicRow & { similarity: number })[] = [];
  let otherProducers: ProducerPublicRow[] = [];
  if (submission.status === "submitted") {
    const { data: producerData } = await supabase
      .from("producers")
      .select("id, name, origin, ship_from_prefecture, ship_lead_time, is_active, is_placeholder")
      .eq("is_active", true)
      .eq("is_placeholder", false)
      .order("name");
    const producers = (producerData ?? []) as ProducerPublicRow[];
    candidates = findSimilarProducers(submission.producer_name, producers);
    const candidateIds = new Set(candidates.map((c) => c.id));
    otherProducers = producers.filter((p) => !candidateIds.has(p.id));
  }

  return (
    <>
      <BackLink href="/admin/submissions">持込み申請</BackLink>
      <PageHeader
        title={submission.name}
        description={`${submission.submission_no}・最終更新 ${formatDateTime(submission.updated_at)}`}
        action={
          <Badge tone={SUBMISSION_STATUS_BADGE[submission.status] ?? "neutral"}>
            {SUBMISSION_STATUS_LABELS[submission.status] ?? submission.status}
          </Badge>
        }
      />

      {submission.status === "approved" && submission.approved_product_id ? (
        <Notice tone={submission.product_is_published ? "info" : "warning"}>
          承認済みです。作成した商品は{submission.product_is_published ? "公開中" : "非公開 (在庫 0)"}です。{" "}
          <Link href={`/admin/products/${submission.approved_product_id}`} className="font-semibold text-brand hover:underline">
            商品の価格・在庫・公開を管理する
          </Link>
        </Notice>
      ) : null}

      <div className="space-y-5 lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(0,24rem)] lg:items-start lg:gap-6 lg:space-y-0">
        <div className="space-y-5">
          <Card title="画像">
            <SubmissionImageGallery images={images} />
          </Card>
          <Card title="商品">
            <SubmissionProductDetails submission={submission} />
          </Card>
          <Card
            title="生産者"
            description="連絡先は申請した代理店と super_admin だけが見られます (監査ログには値を記録しません)。"
          >
            <SubmissionProducerDetails submission={submission} />
          </Card>
        </div>

        <div className="space-y-5">
          <Card title="申請した代理店">
            <DetailList>
              <DetailRow
                label="代理店"
                value={
                  <Link href={`/admin/agents/${submission.agent.id}`} className="font-medium text-brand hover:underline">
                    <Mono>{submission.agent.public_id}</Mono> {submission.agent.display_name}
                  </Link>
                }
              />
              <DetailRow
                label="状態"
                value={
                  (AGENT_STATUS_LABELS as Record<string, string>)[submission.agent.status] ?? submission.agent.status
                }
              />
              <DetailRow label="申請回数" value={`${submission.revision} 回`} />
              <DetailRow label="最終申請" value={formatDateTime(submission.submitted_at)} />
            </DetailList>
          </Card>

          {submission.status === "submitted" ? (
            <Card title="審査" description="この操作は super_admin のみ実行できます。すべて監査ログに記録されます。">
              <ReviewPanel
                submission={{
                  id: submission.id,
                  name: submission.name,
                  category: submission.category,
                  desired_price: submission.desired_price,
                  producer_name: submission.producer_name,
                  producer_origin: submission.producer_origin,
                  producer_ship_from_prefecture: submission.producer_ship_from_prefecture,
                  producer_ship_lead_time: submission.producer_ship_lead_time,
                }}
                candidates={candidates}
                otherProducers={otherProducers}
                images={images}
              />
            </Card>
          ) : null}

          <Card title="履歴">
            <SubmissionTimeline
              events={submission.events}
              renderExtra={(_event, index) => {
                const changed = changedSincePrevious(submission.events, index);
                if (!changed) return null;
                return (
                  <p className="mt-1 text-[12px] text-text-secondary">
                    前回からの変更: {changed.length > 0 ? changed.map((k) => DIFF_LABELS[k]).join("、") : "なし"}
                  </p>
                );
              }}
            />
          </Card>
        </div>
      </div>
    </>
  );
}
