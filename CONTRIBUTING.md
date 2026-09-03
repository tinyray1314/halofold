# Contributing to Halofold

感谢你愿意参与 Halofold。这个项目优先考虑本地隐私、低打扰体验和清晰可维护的实现。

## 提交问题前

- 搜索现有 Issue，避免重复。
- Bug 请写清 macOS 版本、Mac 芯片类型、Halofold 版本、复现步骤和预期结果。
- 截图、日志和示例数据中请移除用户名、路径、对话内容、访问令牌与其他个人信息。
- 安全问题不要创建公开 Issue，请按 [安全政策](SECURITY.md) 私下报告。

## 本地开发

项目要求 macOS 14 或更高版本，并使用 Swift Package Manager：

```bash
swift test
swift run CodexIsland
```

视觉检查可以使用独立演示模式：

```bash
swift run CodexIsland --demo
```

官网位于 `website/`：

```bash
cd website
npm install
npm run build
npm run test:sites
```

## Pull Request

1. 每个 PR 聚焦一个明确问题，并说明用户体验的变化。
2. 为逻辑变化补充或更新测试；提交前运行 `swift test`。
3. 不要提交真实的 `~/.codex` 数据、构建产物、凭据或个人日志。
4. 涉及提醒、权限或数据读取时，说明隐私边界和失败时的表现。
5. UI 变化请附前后截图；文案变化请同步中英文和本地化资源。

小型修复可直接提交 PR。较大的产品或架构变化建议先创建 Issue 对齐范围。
