# Mac App Store 截图

## 可上传文件

- `final/01-task-status.png`：运行、完成与中断状态
- `final/02-official-usage.png`：官方周用量本机同步
- `final/03-customize.png`：布局与模块设置

三张图片均为 2880×1800 PNG（16:10），使用应用内置演示数据，不包含真实账号、对话、文件路径或工作区内容。

## 可复现流程

1. 使用 `--demo --ignore-codex-foreground` 启动临时签名的沙盒 App，捕获展开面板。
2. 使用 `--demo --settings-demo --ignore-codex-foreground` 捕获设置面板。
3. 运行 `swift scripts/make_app_store_screenshots.swift` 生成最终截图。

正式名称确认后，需要检查截图中是否出现旧名称；当前三张图没有展示产品名称，不需重做。
