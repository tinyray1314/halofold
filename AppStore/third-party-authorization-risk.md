# 第三方服务授权风险

核对日期：2026-08-13

## 已确认事实

1. 当前 App 在用户明确选择 `.codex` 文件夹后，程序化解析本机 SQLite/JSONL 数据，以展示 Codex 任务标题、状态、Token 和官方周用量事件。
2. App 不调用 OpenAI 网络接口、不读取凭据、不绕过 rate limit，也不把内容发送给开发者。
3. OpenAI 个人用户《Terms of Use》在 “What you cannot do” 中禁止自动或程序化提取 data 或 Output，并禁止逆向工程服务的底层组件。
4. Apple App Review Guideline 5.2.2 要求：App 使用、访问、展示第三方服务内容时，应确保该服务条款明确允许；Apple 要求时需要提供授权。
5. 未找到公开的 OpenAI/Codex 文档，明确许可第三方商业 App 解析 `.codex/state_5.sqlite` 与 rollout JSONL；也未找到公开稳定的 Codex 周用量 API。

## 判断

这是发布授权风险，不是沙盒或隐私实现问题。用户对本机文件的系统授权可以证明用户同意访问，但不能替代第三方服务条款要求的许可。

现有实现可能被解释为：

- 较温和解释：只处理用户设备上的用户自有工作记录和状态元数据，不属于从服务自动提取；
- 较严格解释：任务内容和用量来自 Codex 服务，程序化解析仍落入禁止条款，并且 Apple 可要求第三方授权证明。

在没有 OpenAI 书面许可或公开支持接口前，不能把“符合第三方条款”标记为已验证。

## 可选路径

### A. 取得 OpenAI 书面许可后提交（推荐）

- 保留全部 Codex 状态和官方周用量功能。
- 向 OpenAI 说明只读、本机、无凭据、无网络上传的实现，并请求允许第三方 Mac App 使用这些本机数据字段。
- 收到许可后把证据保存在发布档案，必要时提供给 Apple。

### B. 按现有实现直接提交

- 产品功能保持不变。
- 接受 Apple 5.2.2 要求补充授权、拒审，以及第三方条款争议风险。
- 审核备注必须如实描述本机读取方式，不能隐藏或伪装数据来源。

### C. 重构为不直接读取 Codex 的通用状态中枢

- 移除 `.codex` 解析和官方周用量。
- 改为用户或其他工具主动写入本 App 自有格式/公开接口。
- 第三方授权风险显著降低，但第一版核心价值和“必须保留官方周用量”的既定要求将不再成立。

## 官方依据

- OpenAI Terms of Use: https://openai.com/policies/terms-of-use/
- Apple App Review Guidelines 5.2.2: https://developer.apple.com/app-store/review/guidelines/

本文是产品发布风险记录，不是法律意见。
