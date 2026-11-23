"use client";

import { useState } from "react";

import { ConfirmReasonDialog } from "@/components/ConfirmReasonDialog";
import { BUTTON_CLASS, FIELD_CLASS, Field } from "@/components/ui";
import { AGENT_RANKS, AGENT_RANK_LABELS, type AgentRank } from "@/lib/domain/rewards";

/**
 * ランクの変更 (super_admin)。変更前に「○○さんを レベル3 → レベル5 に変更します」と確認し、理由は必須。
 * ランクは紹介者として受け取る割合を決める。確定済みの報酬明細には影響しない。
 */
export function AgentRankForm({
  agentId,
  agentName,
  currentRank,
}: {
  agentId: string;
  agentName: string;
  currentRank: AgentRank;
}) {
  const [rank, setRank] = useState<AgentRank>(currentRank);

  return (
    <div className="space-y-4">
      <Field label="ランク">
        <select value={rank} onChange={(e) => setRank(e.target.value as AgentRank)} className={FIELD_CLASS}>
          {AGENT_RANKS.map((r) => (
            <option key={r} value={r}>
              {AGENT_RANK_LABELS[r]}
              {r === currentRank ? " (現在)" : ""}
            </option>
          ))}
        </select>
      </Field>

      <ConfirmReasonDialog
        triggerLabel="ランクを変更する"
        triggerClassName={BUTTON_CLASS}
        disabled={rank === currentRank}
        disabledTitle="変更後のランクを選んでください"
        sentence={`${agentName}さんを ${AGENT_RANK_LABELS[currentRank]} → ${AGENT_RANK_LABELS[rank]} に変更します`}
        note="変更後に確定する報酬から新しいランクの割合が使われます。確定済みの報酬明細は変わりません。"
        reasonLabel="変更理由 (必須・監査ログに記録されます)"
        confirmLabel="変更する"
        endpoint="/api/admin/agents/rank"
        payload={{ agent_id: agentId, rank }}
      />
    </div>
  );
}
