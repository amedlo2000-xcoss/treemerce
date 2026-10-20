import Link from "next/link";
import { notFound } from "next/navigation";

import { SubmissionForm } from "@/app/agent/submissions/SubmissionForm";
import { SubmissionImagesEditor } from "@/app/agent/submissions/[submissionId]/SubmissionImagesEditor";
import { WithdrawButton } from "@/app/agent/submissions/[submissionId]/WithdrawButton";
import {
  SubmissionImageGallery,
  SubmissionProducerDetails,
  SubmissionProductDetails,
  SubmissionTimeline,
} from "@/components/SubmissionDetails";
import {
  BackLink,
  Badge,
  Card,
  DetailList,
  DetailRow,
  FormMessage,
  Mono,
  Notice,
  PageHeader,
  formatDateTime,
} from "@/components/ui";
import { UUID } from "@/lib/api/submission-input";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import { loadCatalogCategories } from "@/lib/catalog-categories";
import { AGENT_STATUS_LABELS, SUBMISSION_STATUS_BADGE, SUBMISSION_STATUS_LABELS } from "@/lib/domain/enums";
import type {
  AdminSubmissionDetail,
  CatalogCategory,
  ProducerPublicRow,
  SubmissionEvent,
  SubmissionImageView,
} from "@/lib/domain/types";
import { findSimilarProducers } from "@/lib/producer-similarity";
import { withSignedUrls } from "@/lib/submission-images";

import { ReviewPanel } from "./ReviewPanel";

/** 代行の申請 (下書き・差し戻し) の編集。保存・画像・申請・取り下げは /api/admin/... を使う (0021)。 */
function ProxyEditor({
  submission,
  images,
  agentLabel,
  categories,
}: {
  submission: AdminSubmissionDetail;
  images: SubmissionImageView[];
  agentLabel: string;
  categories: CatalogCategory[];
}) {
  return (
    <div className="space-y-5">
      <Notice tone="warning">
        「{agentLabel}」の名義で代行作成した申請です。承認すると持込み元はこのオブザーバーとして記録され、あとから変更できません。
        {submission.status === "returned" ? " 差し戻しの内容を直して、もう一度申請してください。" : ""}
      </Notice>
      {submission.status === "returned" && submission.review_reason ? (
        <Card title="差し戻しの理由">
          <p className="whitespace-pre-wrap break-words text-[14px] leading-6 text-text-primary">
            {submission.review_reason}
          </p>
        </Card>
      ) : null}
      <Card title="画像 (任意・5 枚まで)">
        <SubmissionImagesEditor submissionId={submission.id} images={images} proxy />
      </Card>
      <Card title="申請内容">
        <SubmissionForm
          categories={categories}
          key={submission.updated_at}
          submission={submission}
          proxy={{ agentId: submission.agent.id, agentLabel }}
        />
      </Card>
      <WithdrawButton submissionId={submission.id} proxy />
    </div>
  );
}

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
 *
 * 運営が代行作成した申請 (0021) で下書き・差し戻しのときは、ここで内容・画像を編集し、
 * 「保存して申請する」で申請中にしてから、同じ画面の審査パネルで承認・差し戻し・却下する。
 * 代理店本人が作成した申請は、従来どおり閲覧と審査のみ (DB 側でも編集を拒否する)。
 */
export default async function AdminSubmissionDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ submissionId: string }>;
  searchParams: Promise<{ created?: string; submitted?: string }>;
}) {
  const { submissionId } = await params;
  const { created, submitted } = await searchParams;
  if (!UUID.test(submissionId)) notFound();
  const { supabase } = await requireSuperAdminPage(`/admin/submissions/${submissionId}`);

  const { data, error } = await supabase.rpc("treemerce_admin_get_submission", { p_submission_id: submissionId });
  if (error || !data) notFound();
  const submission = data as AdminSubmissionDetail;
  const [images, categories] = await Promise.all([
    withSignedUrls(supabase, submission.images),
    loadCatalogCategories(supabase),
  ]);

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

  const proxy = submission.created_via === "admin_proxy";
  const agentLabel = `${submission.agent.public_id} ${submission.agent.display_name}`;

  return (
    <>
      <BackLink href="/admin/submissions">持込み申請</BackLink>
      <PageHeader
        title={submission.name}
        description={`${submission.submission_no}・最終更新 ${formatDateTime(submission.updated_at)}`}
        action={
          <div className="flex flex-wrap items-center gap-1.5">
            {proxy ? <Badge tone="blue">運営が代行作成</Badge> : null}
            <Badge tone={SUBMISSION_STATUS_BADGE[submission.status] ?? "neutral"}>
              {SUBMISSION_STATUS_LABELS[submission.status] ?? submission.status}
            </Badge>
          </div>
        }
      />

      {created ? <FormMessage tone="success">代行の下書きを作成しました。画像を追加して申請へ進めます。</FormMessage> : null}
      {submitted ? <FormMessage tone="success">申請中にしました。下の審査パネルから承認・差し戻し・却下できます。</FormMessage> : null}

      {proxy && submission.status === "submitted" && submission.created_by_me ? (
        <Notice tone="info">
          あなたが代行作成した申請です。そのまま承認できます (承認は監査ログに「作成者本人の承認」として記録されます)。
        </Notice>
      ) : null}

      {submission.status === "approved" && submission.approved_product_id ? (
        <Notice tone={submission.product_is_published ? "info" : "warning"}>
          承認済みです。作成した商品は{submission.product_is_published ? "公開中" : "非公開 (在庫 0)"}です。{" "}
          <Link href={`/admin/products/${submission.approved_product_id}`} className="font-semibold text-brand hover:underline">
            商品の価格・在庫・公開を管理する
          </Link>
        </Notice>
      ) : null}

      <div className="space-y-5 lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(0,24rem)] lg:items-start lg:gap-6 lg:space-y-0">
        {submission.admin_editable ? (
          <ProxyEditor submission={submission} images={images} agentLabel={agentLabel} categories={categories} />
        ) : (
          <div className="space-y-5">
            <Card title="画像">
              <SubmissionImageGallery images={images} />
            </Card>
            <Card title="商品">
              <SubmissionProductDetails submission={submission} />
            </Card>
            <Card
              title="生産者"
              description="連絡先は申請したオブザーバーと super_admin だけが見られます (監査ログには値を記録しません)。"
            >
              <SubmissionProducerDetails submission={submission} />
            </Card>
          </div>
        )}

        <div className="space-y-5">
          <Card title={proxy ? "名義のオブザーバー (持込み元)" : "申請したオブザーバー"}>
            <DetailList>
              <DetailRow
                label="オブザーバー"
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
              <DetailRow label="作成" value={proxy ? "運営が代行作成 (本人は閲覧のみ)" : "オブザーバー本人"} />
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
                  category_id: submission.category_id,
                  desired_price: submission.desired_price,
                  producer_name: submission.producer_name,
                  producer_origin: submission.producer_origin,
                  producer_ship_from_prefecture: submission.producer_ship_from_prefecture,
                  producer_ship_lead_time: submission.producer_ship_lead_time,
                }}
                candidates={candidates}
                otherProducers={otherProducers}
                images={images}
                categories={categories}
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
