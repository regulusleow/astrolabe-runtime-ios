# SwiftUI 字体与继承颜色组合：受限查找与验收

本文记录颜色链查找这一阶段；后续直接读取环境字体的实现与验收见 [继承字体读取](2026-10-22-swiftui-inherited-font.md)。

## 结论

2026-10-22，在 iOS Runtime `develop@9caacecec91c03724352f1e3b0a054615c2a9986` 上扩展已有环境颜色读取器，修复 3 个已复现的缺色场景：父级字体与红色组合、红色容器内设置字体、外红内蓝且内层同时设置字体。

新增能力是越过已确认的 FontKey 找到当前 Text 的继承纯色，不是读取继承字体或恢复全部 SwiftUI 样式。此前 [首次接入报告](2026-10-22-swiftui-inherited-color.md) 的单条头部限制，在本轮仅放宽为以下受限链。

只修改 Runtime 内部 reader、共用类型名策略及纯策略测试；不改 Protocol、Host、MCP、Android、依赖、Demo 源码或工程。按开发者明确指令在 develop 本地提交，不推送、合并或修改系统 Astrolabe 安装。

## 实现边界

- 复用 `SwiftUIEnvironmentColorReader` 这一私有布局 adapter。既有 projector 保留作用域证明、显式颜色优先、候选和 canonical 属性生成；collector 保留整窗隐私门，Core 保留 typed 冻结缓存。不新增通用环境解析器、策略注册框架或配置入口。
- 仅启用 iOS 27.0 已验证布局；最多检查 8 个 PropertyList Element，且仍受原有局部深度、局部/共享访问预算及输出字节预算限制。原深度上限可能更早拒绝，8 条不是可读深度保证。
- 每条均要求 `before=nil`、singleton storage、32 字节条目、已验证偏移、容量、对齐和地址边界；拒绝重复对象、未知布局或键。只沿 `after.some` 前进，不展开整个环境图。
- 先复制 3 个机器字的 header。只有精确 SwiftUI FontKey 和 `Optional<Font>` metadata 匹配才可跳过；不读取、构造或解析 Font payload。
- 首个 ForegroundStyleKey 是最终选择：仅接受既有 `Optional<AnyShapeStyle>` / `ColorBox<SystemColorType>` 布局，使用当前节点环境公开解析 Color。nil、渐变、secondary、未知 provider 或非法颜色立即拒绝，不能继续查找更外层颜色。
- 显式 Color 的“存在”仍阻止继承；显式值越界或无法解析也不能用父色补齐。RGBA 必须有限且位于 [0,1]。
- 成功仍输出 `common.text.color`，候选来源仍为 `ios.swiftui.environment`；字段路径准确包含实际经过的 `/after/some`。缓存不保留环境、Font、provider 或其他活对象。

## 验证环境与产物

| 项目 | 本轮实际值 |
| --- | --- |
| Runtime | 上述 develop 基线加本报告随附的实现 |
| Runtime arm64 UUID | `3E43535B-879B-3017-82BA-999DE1EEE9C0` |
| Host | `581e1f9`，既有源码 CLI + MCP adapter，未修改 |
| Protocol | `d6315b254cee98712fd7238069118290a379dd6a`，未修改 |
| Demo | SwiftUIInspectorTest worktree `94a35d9`，既有 README/handoff 改动保留 |
| 平台 | Xcode 27.1 / SDK 27.1；iPhone 18 Pro，iOS 27.0 `24A434` |
| Simulator UDID | `CD6AFF4C-3BD7-4DA5-AC90-7C3B542CDF47` |
| 产品验收进程 | 颜色组合 PID 2254；安全输入 PID 4767；清理后 PID 5129 |
| MCP 契约 | 既有 23 tools；envelope schemaVersion=4；Wire 2.0 不变 |

验证命令：

```sh
swift test
xcodebuild -scheme astrolabe-runtime-ios -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/astrolabe-swiftui-color-lookup-20261022.5lbl03/RuntimeDerived build
codegraph sync
git diff --check
```

`swift test` 共 59 项、0 失败：UIKit 纯策略/事实 15、模块边界 3、ObjC 元数据 2、Core 39。新增测试只验证 FontKey 类型名精确策略，不构造 UI，也不冒充私有链读取测试。iOS Simulator 构建通过，最终重新构建后 arm64 UUID 未变。

## 真实 App / MCP 验收

先通过真实 MCP 复现旧 Runtime（PID 94556）的 `font再red` 颜色缺失：断言预期 1 个 canonical 色，实际为 0。实现后，独立普通 SwiftUI 宿主页共 17 行，在新 Runtime 的浅深色状态分别抓取、查找唯一 semantic 节点并读取冻结详情。所有详情均为 `detailSource=runtimeSnapshot`；每个新状态先确认 App 前台存活、`list_apps` compatible，再 `inspect_screen(includeSemantics:true)`。

临时宿主页及只读布局探针仅放 `/tmp`，不链接入 Runtime 或 Demo 工程。宿主准备由外部 LLDB 驱动完成，不是产品 Runtime 的导航功能。产品结论依据真实 MCP；额外探针仅解释当时的环境布局。

| 场景 | 新 Runtime 实际结果 |
| --- | --- |
| 原先缺色的 3 个字体/颜色组合 | 均恢复正确颜色；环境候选路径包含 `/after/some` |
| 10 个继承色样本，每个外观状态 | 全部与独立公开 Color.red / Color.blue 环境解析值一致 |
| 外红内蓝、内蓝带字体 | 取最近的蓝色，不误用外层红色 |
| 显式蓝色、父环境红色 | 保留蓝色，不新增环境候选 |
| 显式颜色 red=2、green=-0.1 | 保留缺失，不回退父红色 |
| Text 自身使用 secondary 或渐变 | 保留缺失，不猜测纯色 |
| 内层容器使用 secondary 或渐变，外层为有效红色 | 无 canonical 色、无环境候选；额外探针确认第一条即不支持的 ForegroundStyleKey，后面确有有效红色，未错误回退 |
| locale 位于颜色之前 | 保留缺失；实际 LocaleKey 条目为 40 字节，说明未知布局拒绝有效，不宣称覆盖“32 字节未知键”的动态分支 |
| 已冻结浅色字体+红色节点 | `check_style(textColor=#FF383C)` 通过 |
| 深色新抓取后读取 7 个旧浅色节点 | canonical 属性和完整 semanticContext 均不变，覆盖恢复场景、显式/非法色和新增边界 |
| SecureField 实际填入虚构值后 | 3 个显式/继承/非法色节点均无 Text/环境候选、无 canonical 色，返回 `secureInputContext`；捕获与详情 JSON 不含虚构输入原文 |

红色由浅色 `[1, 0.2196078300, 0.2352941036, 1]` 变为深色 `[1, 0.2588235438, 0.2705882490, 1]`；蓝色由 `[0, 0.5333333611, 1, 1]` 变为 `[0, 0.5686274767, 1, 1]`。不是仅切换外观标志而继续读取旧值。

关键 Host 快照：

- 旧 Runtime 的失败断言：`F4617B65-1748-41CE-B16F-94ABC5BF7919`。
- 新 Runtime 浅色：`452C7703-6F16-480A-BA01-A85FAEC3F670`。
- 新 Runtime 深色：`0551F975-D1D1-497F-AB44-1259F26E86E5`。
- 已填入安全输入：`C2C40F5E-ECF9-43AA-981E-72611A48CC2A`。
- 清理后原始 Demo 样式页：`C5556173-DDC0-4905-91D6-30433B654B9B`。

标识仅记录历史证据，不保证缓存 TTL 后仍可查询。原始 JSON、脚本、截图及日志在 `/tmp/astrolabe-swiftui-color-lookup-20261022.5lbl03`，不提交抓取产物。主要文件为 `product-red-check.log`、`product-accept-summary.json`、`product-boundary-accept-summary.json`、`product-privacy-summary.json`、`product-clean-summary.json`、`final-runtime-tests.log`、`final-runtime-build.log`。

## 审查、清理与未验证项

一次独立只读源码审查未发现问题；已核对首个前景键停止规则、Font payload 不读取、内存边界、循环/访问预算、隐私门及 typed 冻结路径。源码审查和类型名纯测试不能替代上述真实 App 证据。

前置研究里首次 dark 探针仍读到浅色环境，被颜色变化断言识别，未计入深色通过；新状态重新捕获并确认颜色实际变化后才验收。纯测试早期的缺符号编译失败不算行为 RED，行为 RED 是旧 Runtime 的真实 MCP 缺色断言。

最终重启 Demo，只通过单次启动环境加载新 Runtime；PID 5129 映像无 LookupFixture、LookupProbe、ColorBoundaryFixture 或 ColorProbe。已恢复 light、content_size=large，留在前台“样式”页；首抓重新确认两条继承红色、标题字号 28 和正文字号 17。系统安装、全局配置、真机和其他 App 未变。

未对循环、8 条上限、非法指针或损坏 metadata 做真实故障注入；这些拒绝边界依据源码校验，不宣称模拟器已逐一触发。未验证真机、其他系统版本/补丁、合并 storage、非空 before、自定义继承 provider 或更深环境链。未知布局继续缺失，不增加兼容兜底。

私有 ABI 校验不等于崩溃隔离；只读字节复制也不能保证捕获所有 SIGTRAP。仅用于 Debug/Beta，不能据本轮结论宣称 SwiftUI 检查能力整体完成。未重跑未修改的 Host、Protocol、Android 全套测试。

提交前再次运行 `swift test`（59 项、0 失败）和 iOS Simulator 构建，均通过；本次提交操作未重新运行上述 MCP 场景。
