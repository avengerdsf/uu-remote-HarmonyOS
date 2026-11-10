# UI 验收数据

- `ui_contract.json`：机器可读界面规格与原生组件标识。
- `fixtures.json`：附录 C 的固定测试数据。
- `ui_cases.json`：附录 D 的 44 条用例。
- `assets_manifest.json`：华为官方 SVG 的来源、几何与主题资源哈希。
- `evidence/static_report.json`：静态检查证据，不是 UI 运行结果。
- `ui_report.json` 和 `ui_report.summary.md`：由 `scripts/ui/make_report.py` 生成的本地验收报告及摘要。
- `evidence/arkts_compile.json`：当前 Windows / DevEco Studio 26 / API 26 的构建指纹、警告数与签名 HAP 哈希。
- `evidence/native_runtime_regression.json`：Phone、Pad、PC 的原生回归结果、源码指纹和安装包哈希；包括生产服务的控制偏好持久化验证。
- `evidence/session-input-regression.json`：主控输入协议、真实 WebRTC 数据通道、三端页面输入、两种架构核心及安装包一致性的专项证据，包含真实电脑互通的待验证范围。
- `evidence/session-neutral-material-regression.json`：phone、pad、pc 各 9 项远控回归、40vp 中性菜单材质、白色／深色／明暗交界文字及 21 张运行截图；真实 Windows 输入互通单独验收。
- `evidence/session-button-spacing-regression.json`：三端按钮组的 8vp 实测间距、菜单 8vp 留白、四项可视高度、堆叠定位、材质、图标及扩展回归，包含日志、截图和构建指纹。
- `evidence/session-contrast-mouse-regression.json`：三端悬浮前景可读性、华为鼠标 SVG、展开与收起交互及同包安装的 12 项专项回归，包含 27 张原始运行截图。
- `evidence/floating-feedback-regression.json`：三端悬浮触摸反馈与相邻交互 54 项回归、3 项窗口快照复测、同包安装及按压恢复证据，包含横竖屏菜单底距与顶部胶囊截图。
- `evidence/session-touch-files-20261108/`：触屏绝对落点、光标与热点、虚拟鼠标、Windows 目录通道分流、焦点异常及真实接管专项，包含三端 UI、MatePad 真机、双架构指纹和未通过记录。
- `evidence/screenshots/`：使用 mock 数据采集的设置、搜索、远控与滚动条截图。

原生回归与附录 D 的 44 条用例分别记录。HarmonyOS 7 Pad、真实账号与远端互通仍待验证。

远控回归覆盖多级菜单在窗口内向上避让、真实父菜单内容堆叠、逐级返回、画质／分辨率／帧率／色彩选择、选中标记和只读禁用状态。菜单正常、选中、禁用与危险操作的色彩另以三端截图检查。Tab 回归记录三端材质能力、248×56vp 尺寸和系统手势区底距。

运行：

```bash
python3 -B scripts/ui/verify_static.py
python3 -B scripts/ui/make_report.py
```

禁止把静态检查或编译成功计入 UI 用例通过率。
