# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## Current Hero direction

- Keep the desktop first fold spacious: the marketing copy sits slightly below center in the upper area, while the product preview begins near the lower third.
- Present the central activity UI inside a front-facing MacBook display; only the upper portion is visible before the fold and the rest appears on scroll.
- Keep the left task-state rail and right reminder-settings panel visually secondary to the MacBook.
- On mobile, prioritize product readability over the hardware frame; the MacBook frame may be removed while the activity UI remains intact.

## Current Footer direction

- Match the approved dark full-bleed stage rather than a floating rounded card on white.
- Keep a subtle blue-black atmospheric background, an inset rounded top outline, and a continuous waveform feeding into the central Halofold island.
- Preserve the approved headline, download CTA, footer navigation, version details, and the highlighted Tiny author link.

## Current product-site navigation and pricing direction

- Use a conventional product-site header: Product, Pricing, Download, and Language. Do not add registration or login.
- Keep the existing feature sections as the Product story; Product points to the Hero and Pricing points to the Beta/community section.
- Pricing states that the Beta is free. Pair the price card with Tiny's WeChat QR code and instruct people to add the note “Halofold” or “灵动岛” when requesting access to the product discussion group.
