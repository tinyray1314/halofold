import {
  ArrowDown,
  Check,
  CheckCircle,
  DownloadSimple,
  QrCode,
  UsersThree,
} from "@phosphor-icons/react";
import "./product-pricing.css";

export const productNavigation = {
  zh: [
    { key: "product", label: "产品", href: "#product" },
    { key: "pricing", label: "价格", href: "#pricing" },
    { key: "download", label: "下载", href: "#download" },
  ],
  en: [
    { key: "product", label: "Product", href: "#product" },
    { key: "pricing", label: "Pricing", href: "#pricing" },
    { key: "download", label: "Download", href: "#download" },
  ],
};

export const productNavigationCopy = {
  zh: { language: "语言" },
  en: { language: "Language" },
};

const pricingCopy = {
  zh: {
    kicker: "价格",
    title: "Beta 期间，免费使用。",
    body: "Halofold 目前处于 Beta 阶段，所有现有功能免费开放。下载即可使用，不需要注册或登录。",
    badge: "Beta 版免费",
    price: "¥0",
    priceNote: "Beta 期间",
    features: ["Codex 活动与语音提醒", "本地便签", "Apple Silicon 与 Intel Mac"],
    download: "免费下载 Beta 版",
    communityKicker: "产品交流群",
    communityTitle: "一起把 Halofold 做得更好。",
    communityBody: "扫码添加作者微信，反馈问题、交流用法，也可以聊聊你希望灵动岛接下来还能做什么。",
    scan: "微信扫码添加",
    note: "添加时请备注 Halofold 或者灵动岛",
    qrAlt: "作者 Tiny 的微信二维码",
  },
  en: {
    kicker: "Pricing",
    title: "Free during beta.",
    body: "Every current Halofold feature is free during beta. Download and start using it—no registration or login required.",
    badge: "Free beta",
    price: "$0",
    priceNote: "during beta",
    features: ["Codex activity and voice alerts", "Local notes", "Apple silicon and Intel Macs"],
    download: "Download the free beta",
    communityKicker: "Product community",
    communityTitle: "Help shape what Halofold becomes.",
    communityBody: "Scan to add the creator on WeChat, share feedback, compare workflows, and tell us what the Dynamic Island should do next.",
    scan: "Scan with WeChat",
    note: "Please include “Halofold” or “灵动岛” in your request",
    qrAlt: "WeChat QR code for Tiny, the creator of Halofold",
  },
};

export function ProductPricingSection({
  locale = "zh",
  downloadUrl = "/downloads/Halofold-1.0.7.zip",
}) {
  const t = pricingCopy[locale] ?? pricingCopy.zh;

  return (
    <section id="pricing" className="product-pricing-section section" aria-labelledby="pricing-title">
      <div className="product-pricing-heading reveal">
        <span className="kicker">{t.kicker}</span>
        <h2 id="pricing-title">{t.title}</h2>
        <p>{t.body}</p>
      </div>

      <div className="product-pricing-grid reveal">
        <article className="beta-price-card">
          <div className="beta-price-topline">
            <span className="beta-badge"><CheckCircle size={16} weight="fill" aria-hidden="true" />{t.badge}</span>
            <DownloadSimple size={25} aria-hidden="true" />
          </div>

          <div className="beta-price-value">
            <strong>{t.price}</strong>
            <span>{t.priceNote}</span>
          </div>

          <ul className="beta-feature-list">
            {t.features.map((feature) => (
              <li key={feature}><Check size={17} weight="bold" aria-hidden="true" />{feature}</li>
            ))}
          </ul>

          <a className="beta-download-button" href={downloadUrl} download>
            <DownloadSimple size={19} aria-hidden="true" />
            {t.download}
            <ArrowDown size={17} aria-hidden="true" />
          </a>
        </article>

        <article className="community-card">
          <div className="community-copy">
            <span className="community-kicker"><UsersThree size={17} weight="fill" aria-hidden="true" />{t.communityKicker}</span>
            <h3>{t.communityTitle}</h3>
            <p>{t.communityBody}</p>
            <div className="community-note">
              <QrCode size={20} aria-hidden="true" />
              <div><strong>{t.scan}</strong><span>{t.note}</span></div>
            </div>
          </div>

          <figure className="community-qr">
            <div className="community-qr-frame">
              <img src="/assets/tiny-wechat-qr.png" alt={t.qrAlt} />
            </div>
            <figcaption>{t.note}</figcaption>
          </figure>
        </article>
      </div>
    </section>
  );
}
