# SwiftUI 继承字体：实现与验收

## 结论与范围

2026-10-22，在 iOS Runtime `develop@9d499edadd9d678d33899ff31c78e2c7d503f3ac` 基础上，补齐当前 Text 的环境字体读取。父容器设置的字体现在可导出字体名、实际字号及可确认的粗体/等宽特征；显式字体优先，未知作用域不猜测。

本轮是用户确认后的产品实现，不是独立 Demo 研究。按开发者明确指令在 Runtime develop 本地提交，不推送；不修改 Protocol、Host、MCP、Android、依赖、Demo 源码或工程，不修改系统 Astrolabe 安装及全局配置。

## 设计与责任

- **直接读取现有环境**：projector 已取得当前 AX 节点的 `EnvironmentValues`，读取其公开 `font` 属性。不解析 FontKey payload，不另建环境树解析器，也不创建字体节点。
- **复用解析**：显式和继承 Font 共用 projector 内部 `fontAttributes` 函数，通过现有 `fontResolutionContext` 解析。只增加一个内部共用函数，不引入策略注册、provider 框架或配置。
- **优先级与归属**：`SwiftUITextScopeProof` 在解析前记录原始 Font 的存在。即使显式值解析失败，也不能由继承字体替代；缓存附件不参与原始存在判定。只有唯一、完整原始 Text 且没有显式 Font 时才读取环境字体。
- **既有输出**：字体名与字号进入 `common.text.fontName/fontSize`；字号仍是 `scaledLogical`，不二次缩放。粗体/等宽使用既有 `ios.swiftui.text.isBold/isMonospaced`，保留在候选。来源为 `ios.swiftui.environment`，路径为 `environment/font`；同一节点的环境字体与颜色合并为一个候选。
- **既有安全边界**：读取和解析计入局部/共享访问预算；按编码后的字段字节计入 4 MiB 预算。整窗隐私门仍在 projector 之前，Core 仍只冻结 typed 值。Font 为 nil、解析字号非有限或非正数、作用域未知时不填默认字号。

本轮没有修改环境颜色 reader 的读取格式或支持范围。原附件的 `fontUnavailable` 仍表示该附件来源缺失，不因为其他来源已找到字体而抹去；节点可能保持 partial，但已确认的字体可以独立检查。

## 环境与身份

| 项目 | 本轮实际值 |
| --- | --- |
| Runtime | 上述 develop 基线加随本报告交付的实现 |
| Runtime arm64 UUID | `44E1F196-2530-33DE-B3C8-7174FE6632CF` |
| Host | `581e1f9`，源码 CLI + MCP adapter，未修改 |
| Protocol | `d6315b254cee98712fd7238069118290a379dd6a`，未修改 |
| Demo | SwiftUIInspectorTest worktree `94a35d9`；既有 README/handoff 修改保留 |
| 平台 | Xcode 27.1 / SDK 27.1；iPhone 18 Pro，iOS 27.0 `24A434` |
| Simulator UDID | `CD6AFF4C-3BD7-4DA5-AC90-7C3B542CDF47` |
| 进程 | 旧 Runtime PID 5129；字体验收 PID 16012；安全输入 PID 17840；清理后 PID 18408 |
| 契约 | 既有 23 个 MCP tools；envelope schemaVersion=4；Wire 2.0 不变 |

## 验证

### 纯策略与构建

新增两个纯策略测试，验证显式 Font 存在阻止继承、未知/多个原始 Text 不可继承；同时验证字体与颜色的优先级状态互不干扰。未增加 UI 单测。

完整 `swift test` 共 61 项、0 失败：UIKit 纯策略/事实 17、模块边界 3、ObjC 元数据 2、Core 39。iOS Simulator framework 构建通过，最终重新构建后的 arm64 UUID 未变。

2026-10-30 原子提交前，从仅包含字体改动的暂存区导出独立快照，再次通过 61 项测试及 iOS Simulator 构建。本次提交复验未重跑下面的真实 App/MCP 场景。

```sh
swift test
xcodebuild -scheme astrolabe-runtime-ios -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/astrolabe-swiftui-inherited-font-20261022.cbyw5b/RuntimeDerived build
codegraph sync
git diff --check
```

### 真实 App / MCP

先在旧 Runtime 复现行为 RED：父容器设置 18 号字体，MCP 的 canonical 字号数量为 0，预期为 1。不是把纯测试初次缺符号的编译失败当作行为 RED。

临时普通 SwiftUI 宿主页有 12 个场景，不添加 inspector modifier；宿主准备只作用于专用 Demo，产品 Runtime 不导航或触发业务动作。每个新状态先 `list_apps` 确认 compatible，再 `inspect_screen(includeSemantics:true)`，随后查找唯一 semantic 节点、读取 `runtimeSnapshot` 详情。以下结论均来自真实源码 MCP，而不是探针 JSON。

| 场景 | 实际结果 |
| --- | --- |
| 父容器固定字体 | 导出 18 scaledLogical 与 `.SFUI-Regular` |
| 父容器粗体等宽字体 | 导出 24、`.AppleSystemUIFontMonospaced-Bold`，候选 isBold/isMonospaced 均 true |
| 系统字体名独立校验 | 上述两个名字与独立 UIKit UIFont 查询一致，不通过产品 helper 计算期望值 |
| 继承正文与 Dynamic Type | large 为 17；extra-extra-extra-large 为 23；恢复 large 后回到 17 |
| 外层 30、内层 14 | 导出 14；固定字号不随 Dynamic Type 放大 |
| 外层 30、Text 显式 11 | 导出 11，没有环境字体候选 |
| font/foregroundStyle 两种顺序 | 均导出字体 18 与正确继承红色，环境字体和颜色属于同一个候选 |
| 显式蓝色、字体继承 | 字体仍继承 18，颜色保持蓝色，不误用父红色 |
| Text 的未知字重修饰 / AttributedString | 不把父字体提升为确定整段字体 |
| nil 重置 / 未设置环境字体 | 无 canonical 字体，不回退外层 30，也不填系统默认字号 |
| 浅色标准字号、浅色放大字号、深色放大字号 | 12 个场景在 3 个状态全部通过，颜色随深浅色变化，字体来源和覆盖规则保持正确 |
| 后续捕获后读取 12 个旧标准字号节点 | canonical 属性与完整 semanticContext 均保持原值；字体名、字号、特征及颜色不随新状态漂移 |
| 样式检查 | `check_style(fontSize=18)` 通过 |
| 实际填入虚构内容的 SecureField | 3 个显式/继承/字体颜色节点均无 Text/环境候选及 common.text 属性，返回 secureInputContext；捕获与详情 JSON 无虚构原文 |

关键 Host 快照：旧 Runtime 失败断言 `C438ABB5-EB1D-4259-A856-994D4847FBF2`；标准字号 `248916B0-A17C-4FE6-B8F5-8C9C88D68346`；放大字号 `9AF8B108-3484-486F-8869-0930813F602B`；深色放大字号 `9CB5137F-2C6F-4B43-93FA-34F27F5CEEB7`；恢复字号 `FF7C4F9F-C7FE-4817-9630-0608F3525232`；安全输入 `484BB05D-1559-4498-A24E-A6D42CE23A87`。

这些仅记录历史验收身份，不保证缓存 TTL 后仍可查询。原始 JSON、脚本、截图与日志在 `/tmp/astrolabe-swiftui-inherited-font-20261022.cbyw5b`，不提交抓取产物。主要记录为 `product-red.log`、`font-product-accept-summary.json`、`font-restored-summary.json`、`font-privacy-summary.json`、`font-clean-summary.json`、`final-runtime-tests.log`、`final-runtime-build.log`。

## 审查与收尾

一次独立只读源码审查未发现阻塞项，已核对字体存在策略、合并候选、预算结算、隐私门和冻结链路；真实 App 证据由主执行者验证。首次 framework 构建遗漏 RuntimeAttribute 的 `value:` 标签，修正后重新构建成功；失败日志保留，未计入通过。临时 fixture 编译保留 sysroot warning，不宣称所有构建均无警告。

最终重启 Demo 移除 FontFixture/SecureFontFixture 及此前临时探针，仅通过单次启动环境加载新 Runtime。PID 18408，清理后快照 `2FCE6E56-CD1A-4B68-998C-D53060CE563F`；映像中无临时模块。恢复 light、content_size=large，留在前台“样式”页，首抓确认两条继承红色、原有标题 28 与正文 17。未触碰真机、其他 App 或系统安装。

未覆盖真机、其他系统版本、预算/字节上限动态故障注入、全部字体修饰或富文本逐 run。这里的字体名是解析 Font 的 PostScript 名称，不是每个字形实际使用的 fallback 字体；isBold 也不冒充精确数值字重。未重跑未修改的 Host/Protocol/Android 全套测试。

官方依据：[EnvironmentValues.font](https://developer.apple.com/documentation/swiftui/environmentvalues/font)、[fontResolutionContext](https://developer.apple.com/documentation/swiftui/environmentvalues/fontresolutioncontext)、[Font.resolve(in:)](https://developer.apple.com/documentation/swiftui/font/resolve(in:))。实际调用与样式行为以上述 SDK 构建及运行结果为准。
