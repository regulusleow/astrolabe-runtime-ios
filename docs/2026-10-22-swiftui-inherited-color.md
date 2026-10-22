# SwiftUI 继承文字颜色：受限接入与验收

本文记录首次接入的历史范围；后续 FontKey 链式查找及新产物验收见 [字体与继承颜色组合](2026-10-22-swiftui-font-color-chain.md)。

## 结论与范围

2026-10-22，在 iOS Runtime 的 `develop` 分支接入当前 Text 环境中的已确认系统纯色。只扩展内部读取路径，复用现有 typed 属性、语义候选、冻结详情及 Host 检查工具；不改 Protocol、Host、MCP、Android，不新增依赖或业务埋点。本轮不推送、不修改系统 Astrolabe 安装。

这不是完整继承样式恢复：仅启用已验证的 iOS 27.0 私有布局，环境头部必须是可证明有效的单条 ForegroundStyleKey。其他排布、渐变、secondary、未知 provider 保留缺失，不填默认色。

## 架构与策略

- [SwiftUIEnvironmentColorReader](../Sources/AstrolabeRuntimeUIKit/SwiftUIEnvironmentColorReader.swift)：独立内部只读 adapter，仅负责已确认环境条目到 `RuntimeSemanticTextField` 的投影；不认识窗口选择、传输或 Host 输出。
- [SwiftUITextAttachmentProjector](../Sources/AstrolabeRuntimeUIKit/SwiftUITextAttachmentProjector.swift)：继续负责原始 Text 作用域证明、候选与 canonical 属性、局部/共享预算。只有 role=text、唯一完整原始 Text 且不存在显式 Color 时才尝试环境读取。
- [SwiftUITextScopeProof](../Sources/AstrolabeRuntimeUIKit/UIKitSemanticTraversalBudget.swift)：记录显式 Color 的“存在”，不是只记录导出成功；显式色非法、越界或无法解析时仍禁止继承替换。
- [UIKitSemanticAccessibilityCollector](../Sources/AstrolabeRuntimeUIKit/UIKitSemanticAccessibilityCollector.swift)：复用公开事实判断的语义角色；现有整窗隐私门在 projector 之前生效。Core 冻结缓存与请求分派不变。

不新增通用 Strategy/插件注册框架；平台私有布局留在单个 reader，既有 projector 组合它。将来扩展其他已证实布局时，不需要修改 Wire、Host 或窗口生命周期。

读取约束：

1. OS 必须为 27.0，相关值与引用表示必须为 8 字节。
2. 环境来自当前 AX 节点，反射链为 `_plist → elements.some → storage`；拒绝非空 `before`，不递归环境图。
3. storage 必须只有 1 条、lastOffset=0、nextOffset=32、alignMask=7、容量至少 32 字节、buffer 对齐；单次最多复制 4 个机器字。
4. 使用本进程 `vm_read_overwrite` 读取有界字节，拒绝不可读或短拷贝；value metadata 必须是 `Optional<AnyShapeStyle>`，key metadata 名称必须精确匹配 SwiftUI 的 ForegroundStyleKey。
5. 仅接受实际 `ColorBox<SystemColorType>` / `AnyColorBox`；按已核对的 frozen 单引用表示构建 Color，并核实 provider 对象身份，再用当前节点环境调用公开 `Color.resolve(in:)`。
6. RGBA 必须全部有限且位于 [0,1]；不截断扩展色域，不执行未知 ShapeStyle、body、AttributeGraph 或绘制闭包。

字段复用 `common.text.color`，新增候选来源为 `ios.swiftui.environment`；保留具体字段路径。原附件的 `colorUnavailable` 仍表示该附件来源缺失，不抹除其诊断；已证实环境色可单独通过颜色检查，整个节点仍可能为 partial。

环境读取计入原有局部/共享访问预算与输出字节预算。预算 issue 在环境读取后统一汇总；安全输入或安全扫描不完整时，不进入附件和环境读取。缓存只保存 typed 值，不保存环境、Color/provider 或活对象。

## 验证产物

| 项目 | 本轮实际产物 |
| --- | --- |
| Runtime 基线 | `db429f060ef1d9976bf9fb40a2b1f4e238779577` + 本报告随附的实现修改 |
| Host | `581e1f9`，源码 CLI + MCP adapter，未修改 |
| Protocol | `d6315b254cee98712fd7238069118290a379dd6a`，未修改 |
| Demo | SwiftUIInspectorTest `94a35d9`，既有 worktree 的 README/handoff 改动保留；未改源码或工程 |
| 环境 | Xcode 27.1 / SDK 27.1；iPhone 18 Pro，iOS 27.0 `24A434` |
| Simulator UDID | `CD6AFF4C-3BD7-4DA5-AC90-7C3B542CDF47` |
| 最终 Runtime arm64 UUID | `5DF3BE05-82B5-32DF-97AA-D0ECAC797A72` |
| 最终验收进程 | PID 85413；清理临时页后重启为新进程，见下方清理记录 |
| MCP 契约 | 既有 23 tools；Host 输出 envelope schemaVersion=4；Wire 2.0 未改 |

最终构建命令：

```sh
swift test
xcodebuild -scheme astrolabe-runtime-ios -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/astrolabe-swiftui-color-20261022.Rc3NFZ/RuntimeDerivedFinal build
codegraph sync
```

`swift test` 共 58 项、0 失败（UIKit target 的纯策略/事实测试 14，模块边界 3，ObjC 元数据 2，Core 39）。iOS Simulator 构建通过。未新增或运行 UI 单测；UIKit/SwiftUI 活对象行为通过运行中的 App 和真实源码 MCP 验证。

## 产品链路验收

每个新状态均先 `list_apps` 确认 compatible，再 `inspect_screen(includeSemantics:true)`，随后 `find_nodes`、`inspect_node`、必要的 `check_style`。详情均为 `detailSource=runtimeSnapshot`，未用探针 JSON 代替产品输出。

| 场景 | 实际结果 |
| --- | --- |
| 旧 Runtime 基线 | “继承红色文本”无 canonical `common.text.color` |
| 浅色，两条继承红色 Text | 均为 sRGB `[1, 0.2196078300, 0.2352941036, 1]`，等于独立公开 Color.red 解析值；`check_style(textColor=#FF383C)` 通过 |
| 深色，两条继承红色 Text | 均为 sRGB `[1, 0.2588235438, 0.2705882490, 1]`，随环境更新 |
| 深色后查询旧浅色详情 | 原浅色 canonical 值与全部候选不变；不是重新抓当前颜色 |
| secondary / tint 按钮 / 默认正文 | 不猜测 canonical 颜色，不产生环境颜色候选 |
| 原有字号与富文本边界 | 标题 28、正文 17 scaledLogical；富文本没有伪造统一字号或颜色 |
| 临时宿主页，父环境红色 | 直接继承红色可读；显式蓝色仍为 `[0, 0.5333333611, 1, 1]`，不会被父红色覆盖 |
| 原始显式自定义 RGB | 原路径仍导出约 `[0.2, 0.3, 0.4, 1]`，不经过新增 reader |
| 显式扩展值 red=2、green=-0.1 | 无 canonical 色；保留原始附件 `colorOutOfRange`，无环境候选 |
| 显式渐变与 secondary | 无 canonical 色，未知原始样式仍报告 unsupportedLayout / ambiguousTextScope |
| 填入虚构内容的 SecureField | 整窗原始附件与环境候选均关闭，含显式蓝色的节点也不导出色；返回 `secureInputContext`，捕获与详情 JSON 无虚构输入原文 |

最终产物的关键 Host 快照：

- 浅色 `9FF8A36B-50B5-4A20-9E64-A9D0FCB35006`，深色 `C8794622-3B9D-498B-91C2-18AA1F7A36BE`。
- 恢复浅色 `5FF7AE02-EF67-4ACD-8931-D85AD54C0A01`。
- 显式/非法/渐变边界 `CF018942-8D2A-4046-96C2-74DCB3238689`。
- 安全输入 `1C92E8E2-4FC9-4BE6-9D73-A3D41669D79A`。

这些是不透明的历史验收标识，不保证超出缓存 TTL 后仍可查询。原始 JSON、脚本、截图及构建日志仅在本机临时目录保存，不提交抓取产物：

- `/tmp/astrolabe-swiftui-color-20261022.Rc3NFZ`：`runtime-tests-final.log`、`runtime-build-final.log`、`product-acceptance-summary-final.json`、`boundary-acceptance-summary-final.json`、`privacy-filled-acceptance-summary-final.json` 等。
- `/tmp/astrolabe-swiftui-phase2-20261022.RqB6Lk/inherited-color-final-*.json`：本轮新调用的真实 MCP 证据，目录沿用旧验证驱动，不代表复用旧快照。

## 审查、失败记录与边界

独立只读审查发现并修复两项：显式 Color 解析失败后可能错误继承；reader 耗尽预算后漏节点级 budgetExceeded。显式颜色存在策略和 key 类型策略均有先 RED、后 GREEN 的纯逻辑回归，不构建 UI 测试替身。

研究/验证失败保留原日志，不计入产品通过：LLDB 多表达式 Swift 声明作用域不一致，改用正常编译的临时 dylib；首次 iOS 构建发现 `mach_vm_read_overwrite` 未导入，改为实际 SDK 声明的 `vm_read_overwrite`；验证脚本曾误把属性名写为 `common.text.textColor`、把 measurement 当标量，纠正后全部重跑。

临时宿主页展示/关闭由外部驱动完成，不是 Runtime 行为。UIKit dismissal 未结束时曾拒绝立即展示，待恢复主循环后再展示；首次填入驱动未找到已物化输入，未声称填入成功，后续确认 `filled=true` 再抓取。额外父 font 环境配置的早期 fixture 未导出继承色，去掉后可导出；未定位具体拒绝 guard，不扩展格式或假称通用继承已覆盖。

仍未验证真机、其他系统版本/补丁、深层或合并环境条目、自定义继承 provider、所有 SwiftUI 控件与最终合成像素。只读字节复制和格式校验不等于私有 ABI 崩溃隔离，不能保证 Swift catch 可处理 SIGTRAP。Debug/Beta 之外的成品必须排除 Runtime。

## 格式依据

- [Apple Color.resolve(in:)](https://developer.apple.com/documentation/swiftui/color/resolve(in:))：已证实 Color 的公开环境解析；不把 Resolved=Never 的 ShapeStyle resolve 当 RGBA getter。
- [Engine PropertyList.swift，7c015a79](https://github.com/nathantannar4/Engine/blob/7c015a79ed1a66d130883f4de3e420cd1af7fd88/Sources/Engine/Sources/PropertyList.swift)：提供紧凑存储布局线索；实际条目、provider 和颜色均在当前模拟器核实，未引入库依赖。
- [OpenSwiftUI ForegroundStyle.swift，1bf7ec55](https://github.com/OpenSwiftUIProject/OpenSwiftUI/blob/1bf7ec558d81340f0691b5025c206c9a9ea95253/Sources/OpenSwiftUICore/Shape/ShapeStyle/ForegroundStyle.swift)：提供键/环境语义线索；其旧布局不直接当作 Apple iOS 27 布局。

## 清理与交接

最终重启 Demo 移除临时宿主页、ColorBoundaryFixture 与 ColorProbe，仅通过单次启动环境加载最终 Runtime。浅色与 content_size=large 恢复；最终新进程的映像、compatible 状态和继承色首抓另存 `clean-process-summary-final.json`。系统安装、全局配置、真机、其他 App 不变。

清理后 Demo PID 为 86586，Host 快照为 `2BCF1C0A-EFCF-4224-B4CD-3E00D29233FF`；进程映像中没有 ColorBoundaryFixture / ColorProbe，最终 Runtime UUID 与上表一致。App 留在前台“样式”页，两条继承红色文本可检查。

变更仅在 Runtime `develop`，按开发者显式指令本地提交，不推送、合并或发布。提交前重新运行 `swift test`（58 项、0 失败）与 iOS Simulator 构建，均通过；本次提交操作未重新运行上述 MCP 场景。本轮不重新运行未修改的 Host/Protocol/Android 全套测试；不以既有历史测试数量冒充本轮结果。
