# Astrolabe Runtime for iOS

[English](README.md) | 简体中文

Astrolabe Runtime for iOS 在开发期间向 Astrolabe Host 暴露 UIKit 和 Core Animation
检查数据。Release 构建不会编译 Runtime 激活逻辑。

当前 Package 版本：`2.0.0`。

## 环境要求

- iOS 15 或更高版本
- 支持 Swift 5.9 或更高版本的 Xcode
- Astrolabe Host 工具

## 安装

在 Xcode 中添加以下 Package：

```text
https://github.com/regulusleow/astrolabe-runtime-ios
```

将 `AstrolabeRuntime` Product 链接到 App Target。

## 接入

在当前 Scene 生命周期中启动和停止 Runtime。

Objective-C：

```objc
@import AstrolabeRuntime;

- (void)sceneDidBecomeActive:(UIScene *)scene {
#if DEBUG
    [ASTRuntime start];
#endif
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
#if DEBUG
    [ASTRuntime stop];
#endif
}
```

Swift：

```swift
func sceneDidBecomeActive(_ scene: UIScene) {
#if DEBUG
    ASTRuntime.start()
#endif
}

func sceneDidEnterBackground(_ scene: UIScene) {
#if DEBUG
    ASTRuntime.stop()
#endif
}
```

Objective-C 代码需要处理启动失败时，可以使用 `startWithCompletion:`。需要自定义端口、请求限制或
检查授权时，可以使用 `UIKitRuntimeLifecycle`。

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
| `AstrolabeRuntimeCore` | iOS SDK 使用的协议服务、路由、Session、Transport、节点注册表和平台无关补丁协调。 |
| `AstrolabeRuntimeUIKit` | UIKit 和 Core Animation 采集、属性映射、Auto Layout、无障碍信息及白名单内的修改操作。 |
| `AstrolabeRuntime` | 公共 `ASTRuntime` 外观接口、SDK 元数据、生命周期和依赖组装。 |
| `AstrolabeRuntimeObjC` | 最小化的 Objective-C Runtime 元数据适配器。 |

该 Package 实现 `astrolabe-protocol` 定义的平台无关 Wire Protocol。iOS 特有的数据采集、映射、
生命周期和端口选择保留在本仓库中。

## 开发

运行兼容 macOS 的测试和 Release 构建：

```bash
npm ci
npm test
swift test --parallel
swift build -c release --product AstrolabeRuntime
```

在 iOS 模拟器中运行 UIKit 和集成测试：

```bash
xcodebuild \
  -scheme astrolabe-runtime-ios \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  test
```

## 安全性

Runtime 仅监听 Loopback TCP Endpoint，并且在 Release 构建中不可用。USB Transport 同样依赖
usbmux 强制执行的主机与设备配对机制。请勿分发包含敏感运行时数据的 Debug 构建。

临时修改仅限 Runtime 自身维护的补丁能力清单中声明的属性。Runtime 不会暴露任意 Selector、方法调用或业务操作。

## 许可证

Astrolabe Runtime for iOS 使用 [Apache License 2.0](LICENSE) 许可。
