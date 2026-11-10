# 原生库放置位置

`scripts/harmony/build-native.sh`（或 Windows 的 `build-native.ps1`）将
`libuu_core.a` 复制到 `harmony/entry/src/main/cpp/libs/arm64-v8a/libuu_core.a`。

该文件由 Rust 源码构建，被 `.gitignore` 排除，不提交到仓库。当前工作区已放置重建后的 AArch64 归档；CMake 会把它、vendored libopus 与 N-API 桥接层链接为 `libuu_core.so`。
