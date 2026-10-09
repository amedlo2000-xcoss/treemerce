import type { ReactNode } from "react";

import { isHttpUrl } from "@/lib/api/agent-profile-input";
import { AGENT_INDUSTRY_LABELS } from "@/lib/domain/enums";
import type { AgentProfile } from "@/lib/domain/types";

/**
 * 代理店の事業プロフィールの表示 (本人の MY ページと super_admin の代理店詳細で共用)。
 * このコンポーネントに渡すデータは、本人用 / super_admin 用 RPC からしか取得できない (0016)。
 * 外部リンクは DB で http(s) に限定済みだが、表示時にもう一度確認する。
 */
function ExternalLink({ url }: { url: string }) {
  if (!isHttpUrl(url)) return <span className="break-all">{url}</span>;
  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer nofollow"
      className="break-all font-medium text-brand hover:underline"
    >
      {url}
    </a>
  );
}

function Block({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="py-3">
      <dt className="text-[12px] font-semibold text-text-secondary">{label}</dt>
      <dd className="mt-1 whitespace-pre-wrap break-words text-[14px] leading-6 text-text-primary">
        {children}
      </dd>
    </div>
  );
}

const EMPTY = <span className="text-text-secondary">未入力</span>;

export function AgentProfileDetails({ profile }: { profile: AgentProfile }) {
  return (
    <dl className="divide-y divide-border-soft">
      <Block label="業種">
        {profile.industry ? (AGENT_INDUSTRY_LABELS[profile.industry] ?? profile.industry) : EMPTY}
      </Block>
      <Block label="事業内容">{profile.business_description ?? EMPTY}</Block>
      <Block label="取扱商品・サービス">{profile.offerings ?? EMPTY}</Block>
      <Block label="得意な客層・地域">{profile.target_customers ?? EMPTY}</Block>
      <Block label="活動エリア">
        {profile.activity_prefectures.length > 0 ? profile.activity_prefectures.join("、") : EMPTY}
      </Block>
      <Block label="Web サイト">
        {profile.website_url ? <ExternalLink url={profile.website_url} /> : EMPTY}
      </Block>
      <Block label="SNS">
        {profile.sns_urls.length > 0 ? (
          <ul className="space-y-1">
            {profile.sns_urls.map((url) => (
              <li key={url}>
                <ExternalLink url={url} />
              </li>
            ))}
          </ul>
        ) : (
          EMPTY
        )}
      </Block>
      <Block label="自己紹介">{profile.self_introduction ?? EMPTY}</Block>
    </dl>
  );
}
