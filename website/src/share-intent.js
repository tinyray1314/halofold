const WEBSITE_URL = "https://halofold.aitiny.top/";

const xShareCopy = {
  zh: "推荐给正在用 Codex 的朋友：Halofold 会在任务完成时用声音提醒你，不用再反复盯进度。",
  en: "If you use Codex on macOS, try Halofold—it tells you by voice when a task is done, so you don't have to keep watching the progress.",
};

export function getXShareUrl(locale = "zh") {
  const text = xShareCopy[locale] ?? xShareCopy.zh;
  const query = new URLSearchParams({ text, url: WEBSITE_URL });
  return `https://twitter.com/intent/tweet?${query.toString()}`;
}
