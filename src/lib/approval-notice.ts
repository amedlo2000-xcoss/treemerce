/**
 * オブザーバー申請の承認後に本人へ送るお知らせの文面と、LINE の共有 URL。
 * パスワードは文面に入れない (本人がお申し込み時に設定したもの)。
 */
export function buildApprovalNotice({
  name,
  email,
  loginUrl,
}: {
  name: string;
  email: string;
  loginUrl: string;
}): string {
  return [
    `${name} 様`,
    "TREEMERCE オブザーバー登録の承認が完了しました。",
    "下記からログインしてご利用ください。",
    "",
    "▼ログイン",
    loginUrl,
    `メールアドレス：${email}`,
    "パスワード：お申し込み時に設定したもの",
    "",
    "ログイン後のマイページで、ご自身の登録リンクの発行や報酬の確認ができます。",
  ].join("\n");
}

export function lineShareUrl(text: string): string {
  return `https://line.me/R/share?text=${encodeURIComponent(text)}`;
}
