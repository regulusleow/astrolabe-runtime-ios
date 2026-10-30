# SwiftUI 自定义 RGB 继承色：首个增量切片

## 结论与范围

2026-10-30，按用户选择的增量路线，补齐当前 Text 的自定义 sRGB 继承色及 Color 构造器 alpha。继续沿用 `common.text.color`，不新增 Wire 字段、MCP 工具或 UI Graph 节点。

本轮开始时，Runtime develop 基线为 `9d499edadd9d678d33899ff31c78e2c7d503f3ac`，工作区已有未提交的[继承字体实现](2026-10-22-swiftui-inherited-font.md)。这些改动及文档保留，不计为本轮新增。按开发者明确指令，将继承字体与本轮 RGB 实现拆为两个独立的 Runtime develop 本地提交，不推送；字体提交为 `45f8aae7e07163e3fa01f7eff87da4834bd5a4c1`。Host、Protocol、Android、依赖、Demo 源码/工程、系统 Astrolabe 安装及全局配置均未改动。

这不是完整前景样式支持：secondary、tint、渐变，以及继承路径中的 `Color.opacity()` 包裹仍保留缺失。Color 构造器的 `opacity:` 参数与 `Color.opacity()` 是不同 provider，不能混称全部透明度表达式已支持。

## 实现与设计取舍

- 复用现有 `SwiftUIEnvironmentColorReader`，在现有 `SwiftUITextMetadataPolicy` 中收口精确类型白名单。不创建通用 ShapeStyle 框架、插件注册、配置或新的对象模型。
- 原系统纯色 `SwiftUI.ColorBox<SwiftUI.SystemColorType>` 保留；新增实际核实的 `SwiftUI.ColorBox<SwiftUI.ResolvedColorProvider>`。不按 `ColorBox` 前缀或 `AnyColorBox` 基类放行未知 provider。
- 读取器只替换原有类型判断，仍走原来的对象身份校验和公开 `Color.resolve(in:)`，复用已有 RGBA 投影、typed 候选及冻结链路。以后添加其他样式，仍需独立证明其类型、语义和输出，不扩大本片含义。
- 原来的 `before=nil`、singleton 32 字节格式、最多 8 个 FontKey/after 检查、循环/预算限制、首个前景条目解析或拒绝不回退等条件不变。
- 显式 Color 的存在仍阻止继承替代，即使其值无法导出。RGBA 必须有限且位于 [0,1]，不把越界值截断为看似准确的颜色。
- 隐私门仍在 projector 之前；不新增正常路径日志、不求值 body 或执行 UI 业务动作。颜色是解析后的样式 RGBA，不是与背景合成后的截图像素。

代码增量仅三处：读取器的一条类型判断、既有 metadata policy 中的纯判断函数、一个包含 8 条断言的纯策略测试。RGB 实现不改动字体 projector；原 metadata/test 中的字体改动保留并独立提交，既有字体验收文档补充本地提交状态与提交复验记录。

## 环境与产物身份

| 项目 | 本轮实际值 |
| --- | --- |
| 平台 | Xcode 27.1 / SDK 27.1；iPhone 18 Pro，iOS 27.0 `24A434` |
| Simulator UDID | `CD6AFF4C-3BD7-4DA5-AC90-7C3B542CDF47` |
| 基线 Runtime arm64 UUID | `5E964F1E-7916-3EE8-B4C7-7924E39AEB38`，重新构建的本轮起始工作区，包含既有字体修改 |
| 新 Runtime arm64 UUID | `F2D20023-B5B5-35D2-827A-1EB2FA498F32`，最终重建后不变 |
| 进程 | 基线 PID 85978；颜色验收 PID 87664；安全输入 PID 88510；清理后 PID 89199 |
| Host | `581e1f97784c0c562ca7a28c1f42d79620f24e01`，源码 CLI + MCP adapter |
| Protocol | `d6315b254cee98712fd7238069118290a379dd6a`，未修改 |
| Demo | SwiftUIInspectorTest 既有 worktree；README/handoff 改动保留，未改源码/工程 |
| MCP | 既有 23 tools；envelope schemaVersion=4；Wire 2.0 不变 |

普通构造值在实际模拟器中的只读 metadata 观测：RGB、构造器 alpha 均为 `ResolvedColorProvider` / `AnyColorBox`；Color.opacity、secondary、tint、gradient 是不同类型。该观测仅证明格式线索，不代替下面的真实产品验收。

## 测试与真实 App 验收

先保留两个实际行为 RED：基线 Runtime 的真实 MCP 中，“RGB：直接继承”的 canonical 颜色数量为 0、预期 1；纯策略只允许旧系统 provider 时，新增 ResolvedColorProvider 断言失败。后者已实际编译运行，不是缺符号编译失败。

最终完整 `swift test` 共 62 项、0 失败：UIKit 纯策略/事实 18、模块边界 3、ObjC 元数据 2、Core 39。iOS Simulator framework 构建通过；没有新增 UI 单测。

2026-10-30 原子提交前，继承字体已独立提交，再次通过包含本轮 RGB 增量的 62 项测试及 iOS Simulator 构建，CodeGraph 已同步。本次提交复验未重跑下面的真实 App/MCP 场景。

```sh
swift test
xcodebuild -scheme astrolabe-runtime-ios -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/astrolabe-swiftui-rgb-20261030.cQQSb9/RuntimeDerived build
codegraph sync
git diff --check
```

真实验收使用独立普通 SwiftUI 临时宿主页，不添加 inspector modifier。宿主准备仅作用于专用 Demo，产品 Runtime 不导航或触发 UI 事件。每个新状态均先 `list_apps` 确认 compatible，再 `inspect_screen(includeSemantics:true)`；查找唯一 semantic 节点并读取 `detailSource=runtimeSnapshot` 的详情。

| 场景 | 实际结果 |
| --- | --- |
| 直接继承自定义 RGB | 导出约 `[0.2, 0.3, 0.4, 1]`，误差小于 1e-6 |
| font 与 RGB 两种修饰顺序 | 颜色正确，字号仍为 18；字体 4 字段与颜色合并为一个环境候选 |
| 外层红色、内层自定义 RGB | 采用内层约 `[0.6, 0.2, 0.1, 1]` |
| 外层 RGB、内层系统蓝 | 采用内层蓝色；系统色随深浅色更新 |
| 显式蓝色 / 显式 RGB | 原路径结果保留，不产生环境颜色候选 |
| Color 构造器 alpha=0.5 / 0 | RGBA 的 alpha 分别为 0.5 / 0，RGB 分量保留；透明文字仍可有 AX 语义，不因此声称视觉可见 |
| 显式或继承的越界颜色 | 不导出 canonical 色，不回退到外层有效色，不截断分量 |
| 内层渐变、secondary、tint；未知 locale 格式；Color.opacity 包裹 | 均保留颜色缺失；外层有 RGB 也不补填 |
| 浅色与深色 | 每个外观 17 场景通过：10 个有色场景、7 个拒绝场景；RGB 保持常量，系统红/蓝实际变化 |
| 深色抓取后读取旧浅色详情 | 17 份旧 canonical 属性和完整 semanticContext 均不变 |
| 既有工具检查 | 系统红色的 `check_style(textColor=#FF383C)` 通过；自定义 RGB 通过真实 MCP 的 RGBA 数值断言，不冒称做了截图像素比色 |
| 实际填入虚构内容的 SecureField | 3 个显式/继承 RGB 和字体节点均无 Text/环境候选及 common.text 属性，返回 secureInputContext；完整捕获及详情 JSON 均无虚构原文 |

关键 Host 快照：基线失败 `316E0475-56F9-4885-BCFD-8E41F93D7C59`；新浅色 `85A10128-A39E-4293-887A-2DF3D33BE4E3`；新深色 `EE2EC539-9681-4BD2-AF22-E66D22F5861D`；安全输入 `E56E88A9-2188-4793-ACC6-AA67D27EDEA1`；清理后 `7A13878B-4A47-4E9B-9FA8-89630575C04F`。这些仅记录历史身份，不保证缓存 TTL 后仍可查询。

原始 JSON、脚本、截图及日志保存在 `/tmp/astrolabe-swiftui-rgb-20261030.cQQSb9`，不提交抓取产物。主要记录为 `pre-existing.patch`、`color-metadata.json`、`product-red.log`、`policy-red.log`、`rgb-product-accept-summary.json`、`rgb-privacy-summary.json`、`rgb-clean-summary.json`、`final-runtime-tests.log`、`final-runtime-build.log`。

## 审查、清理与剩余范围

一次独立只读增量审查未发现阻塞项，已核对精确类型判断、原有身份/格式校验、隐私、预算、冻结路径及既有字体改动保留。源码审查不替代运行验收。临时 fixture 编译保留 sysroot warning，不宣称全部构建无警告。

最终重启 Demo 移除 RGBFixture/SecureRGBFixture 及其他临时探针，只通过单次启动环境加载新 Runtime。PID 89199 的映像确认无临时模块；恢复 light、content_size=large，留在前台“样式”页。首抓验证原有两条继承红色、标题 28、正文 17。

后续切片仍需开发 secondary、tint、渐变及 Color.opacity 继承包裹；也未验证任意其他 Color provider、所有色彩空间、真机、其他系统及预算故障注入。未重跑未修改的 Host/Protocol/Android 全套测试，不把本片宣称为完整前景样式支持。

公开解析依据：[Color.resolve(in:)](https://developer.apple.com/documentation/swiftui/color/resolve(in:)) 与 [Color.Resolved](https://developer.apple.com/documentation/swiftui/color/resolved)。调用格式和实际结果以上述 SDK 构建、模拟器及真实 MCP 证据为准。
