# Astrolabe Runtime for iOS

[English](README.md) | 简体中文

Astrolabe Runtime for iOS 在开发期间向 Astrolabe Host 暴露 UIKit 和 Core Animation
检查数据。链接 dynamic Framework 即完成全部接入；符合条件的 App 进程加载 Framework
后，Runtime 会自动启动。

当前 Package 版本：`2.1.0`。

## 环境要求

- iOS 15 或更高版本
- 支持 Swift 5.9 或更高版本的 Xcode
- Astrolabe Host 工具

## 安装

在 Xcode 中添加以下 Package：

```text
https://github.com/regulusleow/astrolabe-runtime-ios
```

只在允许暴露运行时检查数据的 App Target 中链接并嵌入 `AstrolabeRuntime` Product，例如
Debug 和内部 Beta Target。从旧静态 Product 升级的既有工程需要确认 Framework 已配置为
`Embed & Sign`。

## 接入

不需要添加任何业务代码。无需导入 Runtime module，也无需在 `AppDelegate` 或
`SceneDelegate` 中调用生命周期 API。dynamic Framework 加载后会安装进程级生命周期观察者，
在 App 启动后开启 Runtime，并在前后台切换期间保持同一个 Runtime 实例。

Runtime 不判断 `DEBUG`，也不识别业务工程的构建配置名称。只要链接并嵌入该 Product，任何构建配置
都会启用 Runtime。因此 Release 和 App Store Target 必须从依赖图和最终 App Bundle 中彻底移除
`AstrolabeRuntime`，并将最终制品扫描作为发布门禁。

## 能力

- 发现模拟器和已配对 USB 设备上的 Runtime。
- 采集 UIKit 和 Core Animation 层级。
- 获取 Frame、可见性、无障碍、文本、字体排版、颜色、边框、阴影、控件状态、图片和 Auto Layout
  元数据。
- 通过稳定的不透明标识符查询节点详情。
- 对受支持的文本、字体、颜色、Alpha、边框、圆角、阴影和已标识的 Auto Layout 约束值应用白名单内
  的内存临时表现补丁。

补丁不会修改源代码、App 二进制文件、业务模型或持久化存储。补丁在 Host 重新连接后仍然有效，并在
Runtime 停止或 App 进程退出时失效。

## 架构

| Target | 职责 |
| --- | --- |
| `AstrolabeRuntimeCore` | 协议服务、路由、Session、Transport、节点注册表和平台无关补丁协调。 |
| `AstrolabeRuntimeUIKit` | UIKit 和 Core Animation 采集、属性、布局、无障碍信息及白名单内的修改操作。 |
| `AstrolabeRuntime` | 自动安装器、进程生命周期协调、SDK 元数据和依赖组装。 |
| `AstrolabeRuntimeBootstrap` | 不暴露公共生命周期 API 的 Objective-C dynamic Framework 加载入口。 |
| `AstrolabeRuntimeObjC` | UIKit 采集使用的 Objective-C Runtime 元数据适配器。 |

该 Package 实现 `astrolabe-protocol` 定义的平台无关 Wire Protocol。iOS 特有的数据采集、映射、
生命周期和端口选择保留在本仓库中。

## 开发

运行兼容 macOS 的测试和 Release 构建：

```bash
npm ci
npm test
swift test --parallel
swift build -c release --product AstrolabeRuntime
scripts/verify-auto-start-artifact.sh
```

在 iOS 模拟器中运行 UIKit 和集成测试：

```bash
xcodebuild \
  -scheme astrolabe-runtime-ios \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  test
```

## 安全性

Runtime 仅监听 Loopback TCP Endpoint。USB Transport 同样依赖 usbmux 强制执行的主机与设备
配对机制。Runtime 内部没有构建配置门禁；如果 Framework 进入 Release 构建，它也会自动启动。
请勿分发包含 Runtime 或敏感运行时数据的构建。

临时修改仅限 Runtime 自身维护的补丁能力清单中声明的属性。Runtime 不会暴露任意 Selector、方法调用或业务操作。

## 许可证

Astrolabe Runtime for iOS 使用 [Apache License 2.0](LICENSE) 许可。
