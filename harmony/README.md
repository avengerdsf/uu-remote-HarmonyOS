# HarmonyOS 工程

本工程是 [VallierDev/uu-remote-linux](https://github.com/VallierDev/uu-remote-linux) 的 HarmonyOS 移植，采用 Stage 模型、ArkTS/ArkUI、Rust 核心和 C++ N-API 桥接。工程兼容 SDK 6.1.0（API 23），目标 SDK 26.0.0。打包包含 `arm64-v8a` 与 `x86_64`。

## 从源码构建

1. 安装带目标 SDK 和 Native SDK 的 DevEco Studio 与 `devecocli`。设置 `DEVECO_HOME` 指向 DevEco Studio 安装目录。
2. 安装 Rust 及两个交叉编译目标。

   ```sh
   rustup target add aarch64-unknown-linux-ohos x86_64-unknown-linux-ohos
   ```

   将 `RUSTUP_HOME` 指向刚安装目标的工具链目录。默认安装通常位于 Windows 的 `%USERPROFILE%\.rustup` 或 Linux 的 `~/.rustup`。

3. 在仓库根目录运行构建。Windows 脚本先交叉编译 Rust，再调用 DevEco CLI。

   ```powershell
   .\scripts\harmony\build-hap.ps1 -BuildMode release
   ```

   也可以先执行 `scripts/harmony/build-native.sh`（将 `OHOS_NDK_HOME` 指向 SDK 的 `native` 目录），再从 `harmony/` 运行 `devecocli build --modules entry --build-mode release`。原生库生成到 `harmony/entry/src/main/cpp/libs/<abi>/libuu_core.a`。

4. 在 `harmony/entry/build/default/outputs/default/` 查找 `entry-default-unsigned.hap`。要安装到设备，在 DevEco Studio 打开 `harmony/`，为 `default` 产品配置自己的签名后构建和安装。

## 测试

用 `devecocli build --modules entry@ohosTest --build-mode debug` 构建测试包。测试用例通过 `ServiceHub` 注入模拟服务。应用正常启动时使用原生服务。

参见 [项目 README](../README.md)、[许可证](../LICENSE) 和 [第三方资源说明](../NOTICE.md)。
