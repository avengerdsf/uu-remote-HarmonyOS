# 图标来源

界面图标使用华为官网 HarmonyOS Symbol 的“复制 SVG”导出文件，以及 DevEco SDK API 26 的系统图标资源。

- 官网：<https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/>
- 原始 SVG：`scripts/ui/huawei/`。
- 主题资源生成：`python -B scripts/ui/make_huawei_icons.py`。
- 来源、原始文件 SHA256、主题文件 SHA256：`tests/ui/assets_manifest.json`。
- 生成和校验会比较原始路径、尺寸比例及遮罩，仅调整主题颜色并补充对应尺寸的 viewBox。

应用图标组合 `ohos_ic_public_device_matebook.svg` 与 `arrow_up_left.svg` 的原始轮廓，采用蓝色渐变背景；源文件为 `scripts/ui/app-icon.svg`，来源与哈希记录为 `scripts/ui/app-icon-sources.json`。生成器为 `scripts/ui/make_app_icon.cjs`。生产 PNG 为 1024×1024 满出血图，圆角由系统裁切；设计预览使用独立遮罩。

| 界面用途 | 官方资源 |
| --- | --- |
| 电脑设备 | ohos_ic_public_device_matebook.svg |
| 手机和移动设备 | ohos_ic_public_device_phone.svg |
| 电视设备 | ohos_ic_public_device_smartscreen.svg |
| 远程协助 | hand_tap.svg |
| 设置 | gearshape.svg |
| 刷新 | arrow_clockwise.svg |
| 搜索 | magnifyingglass.svg |
| 更多 | ohos_ic_public_more.svg |
| 返回 / 前进 | chevron_left.svg / chevron_right.svg |
| 键盘 / 终端输入 | keyboard.svg |
| 输入模式 | hand_point_up_tap_fill.svg |
| 画质 | hd_square_fill.svg |
| 文件 | folder.svg |
| 剪贴板 | text_clipboard.svg |
| 关闭 / 确认 | xmark.svg / checkmark.svg |
| 音量 | speaker_wave_2.svg |
| 屏幕共享 | ohos_ic_public_cast_mirror.svg |
| 横竖屏切换 | rectangle_portrait_rotate.svg |
| 虚拟鼠标指针 / 移动 | arrow_up_left.svg |
| 虚拟鼠标收起入口 | mouse.svg（SDK 官方 mouse，U+F03A6） |
| 虚拟鼠标拖动锁定 | hand_draw.svg |
| 虚拟鼠标左右键 | hand_tap.svg |
| 虚拟鼠标滚轮 / 收起 | chevron_right.svg（组件旋转） |
| 画中画 | smal_window_playback.svg（SDK 官方小窗播放，U+F068D） |
| 隐藏全部控件 | ohos_full_screen.svg（DevEco SDK 预览器资源，工程内名为 toolbar_fullscreen.svg） |

`ohos_ic_public_*` 文件取自 DevEco SDK 的 `openharmony/previewer/common/resources/resources/base/media/`；除下述鼠标图标外，其余文件来自上述华为官网。发布时遵循各来源的使用条款。

`mouse.svg` 保留 SDK 的 `openharmony/previewer/common/bin/fonts/HMSymbolVF.ttf` 中 `mouse` 字形的完整轮廓，仅将字体坐标转换为 SVG 坐标。官方资源索引为 `resources/entry/resources.txt` 中的 `mouse` / `0xF03A6`。源字体 SHA-256：`63a0afa17a4a51e3bdbb5752f4cee99355ba79365131fe24181d56e0237c450c`。主题生成器只调整填充色，校验轮廓不变。

`smal_window_playback.svg` 使用同一 SDK 字体的 `smal_window_playback` / `0xF068D` 原始轮廓。应用图标采用 `app_layered_icon.json`、不透明纯色背景与透明前景；HDS 处理应用内圆角，桌面由系统裁切。配置依据为华为《配置应用图标和名称》《（推荐）分层图标处理》。
