import { headers } from "next/headers";

import { PATHNAME_HEADER } from "./pathname-header";

/**
 * レイアウトのログインガードで使う戻り先。proxy.ts が渡した現在のパスが
 * prefix 配下 (例: /admin/...) ならそれを、そうでなければ prefix を返す。
 * サイト外や別の領域へは戻さない。
 */
export async function currentReturnTo(prefix: string): Promise<string> {
  const path = (await headers()).get(PATHNAME_HEADER);
  if (path && (path === prefix || path.startsWith(`${prefix}/`) || path.startsWith(`${prefix}?`))) {
    return path;
  }
  return prefix;
}
