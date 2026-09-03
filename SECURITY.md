# Security Policy

## Supported version

我们只为 GitHub Releases 中的最新版本提供安全更新。

## Report a vulnerability

请不要在公开 Issue、Discussion 或 Pull Request 中披露安全漏洞。请使用 GitHub 仓库 Security 页的 **Report a vulnerability** 私下提交报告，并包含：

- 受影响的版本和 macOS 版本；
- 可复现的最小步骤；
- 实际影响和建议修复方式；
- 已移除凭据与个人数据的截图或日志。

我们会确认收到报告，并在完成初步判断后同步处理状态。修复公开前，请避免发布可直接利用的细节。

## Security boundaries

- Halofold 不应读取或保存 Codex 登录凭据。
- 对 `~/.codex` 的访问只应用于本地状态识别，并遵守用户授予的 macOS 权限。
- Issue、测试夹具和日志不得包含真实对话、令牌、密码、验证码或恢复码。
- 当前公开 DMG 尚未经过 Apple Developer ID 公证；下载后请核对 GitHub Release 公布的 SHA-256。
