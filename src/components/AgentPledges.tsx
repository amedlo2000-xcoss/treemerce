"use client";

/**
 * 代理店申し込み時の同意・誓約事項 (代理店規約の本文の末尾と同じ3項目)。
 * 紹介リンク (/register) と運営の代理店登録リンク (/join) の両方で使う。
 * それぞれ独立したチェックで、3つすべてにチェックしたときだけ申し込める
 * (DB には p_accept_agent_terms = true として送る)。
 * プライバシーポリシーのページはまだ無いため、リンクにしていない。
 */
export const PLEDGES = ["terms_and_privacy", "confidentiality", "incident_report"] as const;
export type Pledge = (typeof PLEDGES)[number];
export type PledgeState = Record<Pledge, boolean>;

export const NO_PLEDGES: PledgeState = {
  terms_and_privacy: false,
  confidentiality: false,
  incident_report: false,
};

export const allPledged = (state: PledgeState) => PLEDGES.every((p) => state[p]);

export function AgentPledges({
  terms,
  value,
  onChange,
}: {
  terms: { version: string; title: string };
  value: PledgeState;
  onChange: (next: PledgeState) => void;
}) {
  return (
    <fieldset className="space-y-3">
      <legend className="mb-1 text-[13px] font-semibold text-text-primary">
        申込時の同意・誓約事項 (すべてにチェックしてください)
      </legend>
      {PLEDGES.map((key) => (
        <label key={key} className="flex cursor-pointer items-start gap-3">
          <input
            type="checkbox"
            checked={value[key]}
            onChange={(e) => onChange({ ...value, [key]: e.target.checked })}
            className="mt-1 h-4 w-4 shrink-0 accent-[var(--brand)]"
          />
          <span className="text-[14px] leading-6 text-text-primary">
            {key === "terms_and_privacy" ? (
              <>
                「
                <a
                  href="/legal/agent-terms"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-semibold text-brand underline"
                >
                  オブザーバー登録および個人情報の取り扱いに関する同意規約
                </a>
                」と「プライバシーポリシー」を読み、内容を理解し、同意します。
              </>
            ) : key === "confidentiality" ? (
              "業務上知り得た個人情報・秘密情報を適切に管理し、目的外利用、無断提供・公開および漏えいを行わないことを誓約します。"
            ) : (
              "情報の漏えい、紛失、誤送信等が発生した場合、またはそのおそれを認識した場合は、直ちに運営事業者へ報告することに同意します。"
            )}
          </span>
        </label>
      ))}
      <p className="text-[12px] text-text-secondary">
        対象の規約: {terms.title} (第 {terms.version} 版)
      </p>
    </fieldset>
  );
}
