/**
 * LINE 公式アカウントの設定 (公開してよい情報なので定数で持つ)。
 * 画面で使う LINE の URL・アカウント名はすべてここから参照する。
 */

/** 公式アカウント「5D PLUS COMMUNITY」の友だち追加 URL */
export const LINE_ADD_FRIEND_URL = "https://lin.ee/O1SnEdA";

/** 公式アカウント名 */
export const LINE_OFFICIAL_ACCOUNT_NAME = "5D PLUS COMMUNITY";

/** 運営が公式アカウントのチャットを開く (LINE Official Account Manager のチャット) */
export const LINE_OA_CHAT_URL = "https://chat.line.biz/";

/** LINE のブランドカラー */
export const LINE_GREEN = "#06C755";

/** 個人の LINE で文面を共有する URL */
export function lineShareUrl(text: string): string {
  return `https://line.me/R/share?text=${encodeURIComponent(text)}`;
}
