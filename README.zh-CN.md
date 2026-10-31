# Astrolabe Runtime for iOS

[English](README.md) | 简体中文

Astrolabe Runtime for iOS 在 Debug 开发环境向 Astrolabe Host 暴露 UIKit 和 Core Animation
检查数据，供 Agent 检查 UI。链接 dynamic Framework 即完成全部接入；符合条件的 App 进程加载 Framework
后，Runtime 会自动启动。

当前 Package 版本：`2.2.0`。

## 环境要求

- iOS 15 或更高版本
- 支持 Swift 5.9 或更高版本的 Xcode
- 已安装 [Astrolabe Host](https://github.com/regulusleow/astrolabe/blob/main/README.zh-CN.md#安装)，
  并为受支持的 AI 客户端完成配置

## 安装

在 Xcode 中添加以下 Package：

```text
https://github.com/regulusleow/astrolabe-runtime-ios
```

只在 Debug App Target 中链接并嵌入 `AstrolabeRuntime` Product。
从旧静态 Product 升级的既有工程需要确认 Framework 已配置为
`Embed & Sign`。

## 接入

不需要添加任何业务代码。无需导入 Runtime module，也无需在 `AppDelegate` 或
`SceneDelegate` 中调用生命周期 API。dynamic Framework 加载后会安装进程级生命周期观察者，
在 App 启动后开启 Runtime，并在前后台切换期间保持同一个 Runtime 实例。

Runtime 不判断 `DEBUG`，也不识别业务工程的构建配置名称。只要链接并嵌入该 Product，任何构建配置
都会启用 Runtime，因此应在业务工程的 Debug Target 中配置依赖和嵌入。

## 能力

- 发现模拟器和已配对 USB 设备上的 Runtime。
- 采集 UIKit 和 Core Animation 层级。
- 获取 Frame、可见性、无障碍、文本、字体排版、颜色、边框、阴影、控件状态、图片和 Auto Layout
  元数据。
- 通过稳定的不透明标识符查询节点详情。
- 对受支持的文本、字体、颜色、Alpha、边框、圆角、阴影和已标识的 Auto Layout 约束值应用白名单内
  的内存临时表现补丁。

SwiftUI 文本检查目前覆盖经 iOS 27.0 模拟器和 iOS 27.2 arm64 真机验证的有限路径。
这些是验证环境，不是整个 Package 的最低系统要求。上述平台的语义采集会准备 App 内的无障碍元数据，
不更改无障碍设置，也不发送状态通知。已验证的 Text attachment 支持字体和显式纯前景色；
继承纯色支持已确认的单条环境记录，包括颜色透明度和子节点覆盖。
Tint、secondary 和 tertiary 支持已在 iOS 27.0 arm64 模拟器与 iOS 27.2 arm64 真机上验证，
包括深浅色及增加对比度下的默认系统色。未知私有布局只使对应属性不可用；
UIKit 和 Core Animation 检查保留各自的平台要求。

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

运行兼容 macOS 的测试和 Debug 构建：

```bash
npm ci
npm test
swift test --parallel
swift build --product AstrolabeRuntime
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
配对机制。运行时检查数据供本地 Debug 开发使用，是否链接和加载 Framework 由业务工程的 Target 配置决定。

临时修改仅限 Runtime 自身维护的补丁能力清单中声明的属性。Runtime 不会暴露任意 Selector、方法调用或业务操作。

## 许可证

Astrolabe Runtime for iOS 使用 [Apache License 2.0](LICENSE) 许可。
