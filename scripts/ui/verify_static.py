#!/usr/bin/env python3
"""Static verification for the HarmonyOS delivery.

This script never claims UI runtime success. It verifies files, hashes,
contract/formula consistency and source-level invariants, and writes machine
readable evidence for ui_report.json.
"""
import hashlib
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET
from make_huawei_icons import geometry, paint

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HARMONY = os.path.join(ROOT, "harmony")
ETS = os.path.join(HARMONY, "entry", "src", "main", "ets")
MEDIA = os.path.join(HARMONY, "entry", "src", "main", "resources", "base", "media")
RAW = os.path.join(HARMONY, "entry", "src", "main", "resources", "rawfile")
EVIDENCE = os.path.join(ROOT, "tests", "ui", "evidence")
CASES = os.path.join(ROOT, "tests", "ui", "ui_cases.json")
CONTRACT = os.path.join(ROOT, "tests", "ui", "ui_contract.json")
FIXTURES = os.path.join(ROOT, "tests", "ui", "fixtures.json")
MANIFEST = os.path.join(ROOT, "tests", "ui", "assets_manifest.json")

checks = []


def check(check_id, ok, detail, evidence=None, result=None):
    if result is None:
        result = "PASS" if ok else "FAIL"
    checks.append({
        "id": check_id,
        "result": result,
        "detail": detail,
        "evidence": evidence or [],
    })
    return ok


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def source_files():
    found = {}
    for root, _, files in os.walk(ETS):
        for name in files:
            if name.endswith(".ets"):
                path = os.path.join(root, name)
                found[os.path.relpath(path, ETS).replace("\\", "/")] = read(path)
    return found


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def ets_fingerprint(files):
    digest = hashlib.sha256()
    for name in sorted(files):
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(files[name].encode("utf-8"))
        digest.update(b"\0")
    return digest.hexdigest()


def verify_assets():
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    icons = manifest.get("icons", {})
    required_icons = {'mouse', 'pip', 'device_phone', 'device_tv'}
    check("assets.icon-keys", len(icons) == 25 and required_icons <= icons.keys(),
          f"25 semantic keys including mouse, PiP, phone and TV, got {len(icons)}")
    total = 0
    failures = []
    for key, variants in icons.items():
        if len(variants) != 4:
            failures.append(f"{key}: variants={len(variants)}")
        for variant, item in variants.items():
            total += 1
            path = os.path.join(MEDIA, os.path.basename(item["file"]))
            if not os.path.exists(path):
                failures.append(f"{key}/{variant}: missing")
                continue
            if sha256(path) != item["sha256"]:
                failures.append(f"{key}/{variant}: sha256")
                continue
            try:
                tree = ET.parse(path)
            except ET.ParseError as error:
                failures.append(f"{key}/{variant}: xml {error}")
                continue
            root = tree.getroot()
            if root.get("viewBox") != item.get("viewBox"):
                failures.append(f"{key}/{variant}: viewBox")
            source_info = item.get('source', {})
            source = os.path.join(ROOT, source_info.get('file', ''))
            if not os.path.isfile(source) or sha256(source) != source_info.get('sha256'):
                failures.append(f"{key}/{variant}: source hash")
                continue
            original = ET.parse(source).getroot()
            if geometry(root) != geometry(original):
                failures.append(f"{key}/{variant}: official geometry")
            original.set('viewBox', item['viewBox'])
            paint(original, item['color'])
            if ET.tostring(root) != ET.tostring(original):
                failures.append(f"{key}/{variant}: theme colour or mask")
    check("assets.100-hashes", total == 100 and not failures,
          f"checked {total}; failures={failures[:8]}", ["tests/ui/assets_manifest.json"])
    check("assets.source-svg", manifest.get('style') == 'official_huawei_exported_svg',
          "official SVG sources, paths and masks checked for all 100 theme variants")

    # Duplicate/stray files would make resource mapping ambiguous.
    svg_files = {name for name in os.listdir(MEDIA) if name.endswith(".svg")}
    managed = {os.path.basename(item['file']) for variants in icons.values() for item in variants.values()}
    standalone = {'account_avatar_placeholder.svg', 'keyboard_add.svg', 'keyboard_backspace.svg',
                  'remote_unlock_fingerprint.svg', 'toolbar_fullscreen.svg'}
    check("assets.media-count", len(managed) == 100 and svg_files == (managed | standalone),
          f"media svg count={len(svg_files)}, including {len(standalone)} standalone SVGs")

    tab_failures = []
    for key in ['devices', 'assist', 'settings']:
        for variant in ['light', 'dark']:
            name = f'{key}_{variant}.svg'
            expected = ET.parse(os.path.join(MEDIA, name)).getroot()
            expected.attrib.pop('width', None)
            expected.attrib.pop('height', None)
            path = os.path.join(RAW, 'tab-icons', name)
            if not os.path.isfile(path) or ET.tostring(ET.parse(path).getroot()) != ET.tostring(expected):
                tab_failures.append(name)
    check('assets.tab-svg', not tab_failures,
          f'native tab SVG paths and theme colours preserved; no fixed dimensions; failures={tab_failures}')

    baseline = json.load(open(os.path.join(RAW, "baseline_manifest.json"), encoding="utf-8"))
    check("visual.baseline-not-approved",
          baseline.get("approved") is False and baseline.get("status") == "VISUAL_REVIEW_PENDING",
          "no self-approved native baseline")
    check("resources.rawfile-location",
          not os.path.exists(os.path.join(HARMONY, "entry", "src", "main", "resources", "base", "rawfile"))
          and os.path.isdir(RAW),
          "rawfile must be a child of resources/, not resources/base/")


def formula_rects(width, height, font_scale):
    compact = width < 600
    medium = width < 840
    mode = "compact" if compact else ("medium" if medium else "expanded")
    nav = 0  # bottom navigation on every breakpoint, no side rail/sidebar
    padding = 16 if compact else 24
    header = max(56 if compact else 64, 32 * font_scale + 16)
    search_h = max(48, 24 * font_scale + 24)
    body = min(width - 2 * padding, 1200)
    body_x = (width - body) / 2
    if compact:
        columns = 1
    else:
        columns = max(1, min(4, math.floor((body + 16) / (264 * min(font_scale, 1.5) + 16))))
    card_w = (body - 16 * (columns - 1)) / columns
    card_top = max(48, 42 * font_scale)
    status = max(20, 20 * font_scale)
    button = max(48, 24 * font_scale + 24)
    card_h = 32 + card_top + 12 + status + 16 + button
    search_y = header + padding
    grid_y = header + padding + search_h + 16
    connect_y = grid_y + 16 + card_top + 12 + status + 16
    bottom_h = max(64, 24 + 4 + 16 * font_scale + 16)
    return {
        "mode": mode,
        "columns": columns,
        "devices.search": [body_x, search_y, body, search_h],
        "device.demo-win-01.card": [body_x, grid_y, card_w, card_h],
        "device.demo-win-01.connect": [body_x + 16, connect_y, card_w - 32, button],
        "app.bottomNav": [0, height - bottom_h, width, bottom_h],
    }


def close(a, b, epsilon=0.75):
    return abs(a - b) <= epsilon


def verify_contract():
    contract = json.load(open(CONTRACT, encoding="utf-8"))
    cases = json.load(open(CASES, encoding="utf-8"))["cases"]
    fixtures = json.load(open(FIXTURES, encoding="utf-8"))
    check("contract.version", contract.get("contractVersion") == "1.0.0",
          f"contractVersion={contract.get('contractVersion')}")
    check("contract.pages", len(contract.get("pages", [])) == 9,
          f"pages={len(contract.get('pages', []))}")
    check("contract.cases", len(cases) == 44, f"cases={len(cases)}")
    check("contract.fixtures", len(fixtures.get("devices", [])) == 3,
          "three synthetic devices")
    for name, path in [
        ("ui_contract.json", CONTRACT),
        ("fixtures.json", FIXTURES),
        ("ui_cases.json", CASES),
    ]:
        raw = os.path.join(RAW, name)
        check(f"contract.rawfile-{name}", os.path.exists(raw) and sha256(raw) == sha256(path),
              f"{name} packaged copy matches tests/ui")

    failures = []
    for case in cases:
        expected = case.get("expected")
        if not expected or not case.get("viewportVp") or case.get("page") != "devices.page":
            continue
        width, height = case["viewportVp"]
        scale = case.get("fontScale", 1)
        computed = formula_rects(width, height, scale)
        if expected.get("mode") != computed["mode"]:
            failures.append(f"{case['id']}: mode {expected.get('mode')} != {computed['mode']}")
        if expected.get("columns") != computed["columns"]:
            failures.append(f"{case['id']}: columns {expected.get('columns')} != {computed['columns']}")
        for key in ["devices.search", "device.demo-win-01.card", "device.demo-win-01.connect", "app.bottomNav"]:
            want = expected.get(key)
            got = computed.get(key)
            if want is None and got is None:
                continue
            if want is None or got is None:
                failures.append(f"{case['id']}: {key} presence")
                continue
            if not all(close(a, b) for a, b in zip(want, got)):
                failures.append(f"{case['id']}: {key} {want} != {[round(v, 2) for v in got]}")
    check("contract.layout-formulas", not failures,
          "all DEV/SETTINGS expected rectangles match the documented formulas",
          [f"failures={failures[:6]}"])

    settings = contract.get('settings', {})
    settings_source = read(os.path.join(ETS, 'pages', 'SettingsPage.ets'))
    check("contract.settings-split",
          settings.get('navigationMode') == 'Auto'
          and settings.get('navBarWidth') == '32%'
          and settings.get('navBarWidthRangeVp') == [224, 320]
          and settings.get('minContentWidthVp') == 320
          and all(value in settings_source for value in [
              '.mode(NavigationMode.Auto)', ".navBarWidth('32%')",
              '.navBarWidthRange({ minWidth: 224, maxWidth: 320 })', '.minContentWidth(320)']),
          "native Navigation Auto owns stack/split layout, with a bounded navigation pane")


def verify_sources(files):
    expected_pages = {
        "LoginPage.ets": "login.page",
        "DevicesPage.ets": "devices.page",
        "AssistancePage.ets": "assist.page",
        "SessionPage.ets": "session.page",
        "FilesPage.ets": "files.page",
        "TerminalPage.ets": "terminal.page",
        "PortMapPage.ets": "portmap.page",
        "SettingsPage.ets": "settings.page",
        "HostPage.ets": "host.page",
    }
    missing = [name for name in expected_pages if f"pages/{name}" not in files]
    check("source.pages", not missing, f"missing pages={missing}")
    for name, root_id in expected_pages.items():
        content = files.get(f"pages/{name}", "")
        check(f"source.{root_id}", f"'{root_id}'" in content, f"{name} root id")
    check("source.single-entry", sum(content.count("@Entry") for content in files.values()) == 1,
          "@Entry appears exactly once (Index.ets)")

    # Import resolution.
    unresolved = []
    for name, content in files.items():
        base = os.path.dirname(os.path.join(ETS, name))
        for target in re.findall(r"from\s+'(\.[^']+)'", content):
            resolved = os.path.normpath(os.path.join(base, target))
            if not (os.path.exists(resolved + ".ets") or os.path.exists(os.path.join(resolved, "Index.ets"))):
                unresolved.append(f"{name} -> {target}")
    check("source.imports", not unresolved, f"unresolved={unresolved[:6]}")

    # All contract IDs must appear somewhere in source (literal or template).
    contract = json.load(open(CONTRACT, encoding="utf-8"))
    all_text = "\n".join(files.values())
    ids = set(contract.get("commonIds", []))
    for page in contract.get("pages", []):
        ids.add(page["id"])
        ids.update(page.get("tree", []))
    missing_ids = []
    for item in sorted(ids):
        if item.startswith("device.{") or item.startswith("transfer.{"):
            prefix = item.split("{")[0]
            suffix = item.split("}")[1]
            if prefix not in all_text or suffix not in all_text:
                missing_ids.append(item)
        elif item.startswith("app.nav.") and "app.nav.${" in all_text:
            # The three navigation entries are one template with a shared ID.
            continue
        elif item in ('session.more.back.1', 'session.more.back.2') and \
                ".id('session.more.back.' + depth)" in all_text:
            continue
        elif item not in all_text:
            missing_ids.append(item)
    check("source.contract-ids", not missing_ids, f"missing={missing_ids[:10]}")

    # Duplicate literal IDs.
    literal = re.findall(r"\.id\('([^']+)'\)", all_text)
    duplicates = sorted({value for value in literal if literal.count(value) > 1})
    check("source.unique-ids", not duplicates, f"duplicates={duplicates}")

    # Minimal control characters must not be accepted by assist; view-only blocks input.
    assist = files.get("pages/AssistancePage.ets", "")
    check("source.assist-validation", "\\u0000-\\u001F" in assist, "control-character validation present")
    session = files.get("pages/SessionPage.ets", "")
    check("source.view-only", "viewOnly" in session and "releaseAllInput" in session,
          "view-only checks and releaseAllInput present")
    check("source.xcomponent-surface",
          "libraryname: ''" not in session
          and "as XComponentContext" not in session
          and "getXComponentSurfaceId" in session
          and "id.length === 0" in session,
          "surface id comes from XComponentController with an empty-id guard; no empty libraryname")

    # TODO placeholders are not allowed as completed functionality.
    todo = re.findall(r"\b(TODO|FIXME)\b", all_text)
    check("source.no-todo", not todo, f"TODO/FIXME count={len(todo)}")

    # Release gate: mock only when BuildProfile.DEBUG.
    service_hub = files.get("services/ServiceHub.ets", "")
    check("source.mock-gate", "BuildProfile.DEBUG" in service_hub and "MockSessionService" in service_hub,
          "mock selection is debug-gated")

    # Original-client parity: the session quality panel exposes the same six
    # dimensions the official control center does.
    quality_labels = ["原画 20M", "超清 8M", "高清 2M", "4:4:4", "[144, 90, 60, 30]",
                      "分辨率", "跟随被控端", "4K · 3840×2160"]
    check("source.video-quality-panel",
          all(label in session for label in quality_labels)
          and all(token in session for token in ["setVideoQuality", "setFrameRate", "setTrueColor", "setVideoProfile"]),
          "quality/bitrate, fps, true color and resolution controls are wired")
    check("source.settings-resolution-select",
          all(value in files.get("pages/SettingsPage.ets", "") for value in [
              'Select($$.options)', "id: 'settings.resolution'", "id: 'settings.quality'",
              "id: 'settings.fps'", "id: 'settings.color'", "id($$.id + '.label')"]),
          "video settings use inline system Select controls with capability-filtered choices")
    check("source.session-menus",
          'Button({ type: ButtonType.Circle })' in files.get('components/SessionToolbar.ets', '')
          and '.onClick(() => { this.onMore(); })' in files.get('components/SessionToolbar.ets', '')
          and all(value in session for value in [".hitTestBehavior(HitTestMode.BLOCK_HIERARCHY).id('session.menu.overlay')",
              'Scroll(this.menuScrollers[depth]) {', '.accessibilitySelected(item.selected === true)', 'this.selectMenuItem(item, depth)',
              '.scrollBar(BarState.Off).clip(true)', "edgeScrollBar(this.menuScrollers[depth], 'session.menu.items.' + depth)"]),
          "native buttons in a bounded system Scroll dispatch anchored menu actions")
    check('source.session-menu-hierarchy',
          all(value in session for value in ['children?: SessionMenuGroup[]', 'private menuGroups(depth: number)',
              'this.menuPath.slice(0, depth).concat(item.id)', 'this.menuPath.slice(0, depth)',
              'private menuBack(depth: number = this.menuPath.length - 1)',
              "id('session.menu.stack')", 'this.actionMenu(this.menuGroups(depth), depth)',
              "id('session.more.back.' + depth)", "id: 'session.more.input'", "id: 'session.more.tools'",
              "id: 'session.more.clipboard'", "id: 'session.more.remote'"])
          and all(value in session for value in ["id: 'session.quality.select'", "id: 'session.fps.select'",
              "id: 'session.resolution.select'", "id: 'session.color.select'", 'children: this.videoItems()'])
          and '.bindSheet(' not in session,
          'parent content stays behind each nested layer; bounded upward placement and native back/selection are wired')
    menu_source = session.split('  menuHeader(depth: number) {', 1)[-1].split('  private notify(', 1)[0]
    check('source.session-menu-contrast',
          all(value in menu_source for value in ["$r('sys.color.font_primary')", "$r('sys.color.font_secondary')",
              "$r('sys.color.icon_primary')",
              "$r('app.color.session_error')", "$r('app.color.session_error_background')", "$r('app.color.session_selection')",
              "? 'chevron' : 'check', true, false)", "iconResource('chevron', true, false)"])
          and 'ColoringStrategy.INVERT' not in menu_source and 'BlendMode.DIFFERENCE' not in menu_source
          and 'colorInvert: false' in files.get('theme/FloatingMaterial.ets', ''),
          'remote menu text and official SVGs use neutral semantic colors with translucent selection and red destructive roles')
    check('source.inline-settings',
          all(value in files.get('pages/SettingsPage.ets', '') for value in [
              "id: 'settings.theme'", "id: 'settings.input'", "id: 'settings.files'", "id: 'settings.material'",
              'role: ButtonRole.ERROR']),
          'general settings use native Select controls in a dedicated destination, with a destructive logout button')
    check('source.session-orientation-lifecycle',
          all(value in session for value in ['getPreferredOrientation()', 'USER_ROTATION_LANDSCAPE',
              'USER_ROTATION_PORTRAIT', 'setPreferredOrientation(this.originalOrientation)',
              "win.off('windowStatusDidChange', this.onWindowStatus)"]),
          'explicit rotation saves/restores orientation and unregisters the window-status callback')
    shell = files.get("components/AppShell.ets", "")
    preference = files.get('theme/MaterialPreference.ets', '')
    tokens = files.get("model/Tokens.ets", "")
    check("source.bottom-navigation",
          "id('app.bottomNav')" in shell
          and "app.rail" not in shell and "app.sidebar" not in shell
          and "navWidth" not in shell
          and shell.count('.tabBar(this.bottomTab(') == 3
          and all(value in shell for value in ['HdsTabs({', '.barPosition(BarPosition.End)',
              '.barFloatingStyle({', 'barBottomMargin: Math.max(0, 16 - this.navigationIndicatorBottomVp)', '.barOverlap(true)',
              'materialType: hdsMaterial.MaterialType.ADAPTIVE', "@StorageProp('hdsMaterialLevel')", '.barHeight(56)',
              'barWidth: { smallWidth: 248, mediumWidth: 248, largeWidth: 248 }', '.layoutMode(LayoutMode.VERTICAL)']),
          "three native floating bottom tabs with system immersive material on every breakpoint")
    check('source.search-card-width',
          '.width(Metrics.bodyWidth(this.widthVp, Metrics.mode(this.widthVp)))' in shell
          and 'Metrics.bodyWidth(this.widthVp, this.mode())' in files.get('pages/DevicesPage.ets', ''),
          'top Search and the device card region share the same body-width calculation')
    material = files.get('theme/FloatingMaterial.ets', '')
    check('source.floating-material',
          all(value in material for value in ["deviceInfo.apiAvailable('26.0.0')", 'isImmersiveMaterialSupported()',
              'new uiMaterial.ImmersiveMaterial(', 'ImmersiveStyle.THIN',
              'interactive: true', 'lightEffect: { color: undefined }',
              'node.backgroundColor(Color.Transparent)', 'node.systemMaterial(material);',
              'node.backgroundBlurStyle(BlurStyle.NONE)', 'node.backgroundEffect({ radius: 12',
              'node.backgroundEffect({ radius: 40, saturation: 0.35',
              'colorInvert: colorInvert', 'this.navigationTitle ? immersiveMaterial(!this.session) : undefined',
              "materialColor: colorInvert ? undefined : '#B31C1D20'",
              "this.session ? '#B31C1D20' : '#33FFFFFF'", "color: $r('app.color.session_menu_tint')"])
          and re.search(r'node\.systemMaterial\(material\);\s*return;\s*}\s*node\.backgroundEffect\(', material)
          and 'applyShadow:' not in material
          and '.attributeModifier(floatingControl)' in shell,
          'Navigation title controls use supported native material; content controls use translucent fallback')
    check('source.material-preference',
          all(value in preference for value in ['hdsMaterial.getSystemMaterialTypes()', 'MaterialLevel.ADAPTIVE',
              'MaterialLevel.EXQUISITE', 'MaterialLevel.GENTLE', 'MaterialLevel.SMOOTH'])
          and "this.persist('materialPreference', preference)" in files.get('services/NativeSessionService.ets', '')
          and 'setGlobalMaterialLevel' not in preference,
          'HDS material choice is persisted, uses official levels and falls back by supported capability')
    toolbar = files.get('components/SessionToolbar.ets', '')
    check('source.session-controls-material',
          '.width(48).height(48).attributeModifier(floatingControl)' in toolbar
          and toolbar.count('ButtonType.Circle') == 3
          and toolbar.count("$r('sys.color.icon_primary')") == 3
          and all('BlendMode.DIFFERENCE' not in files.get(path, '') for path in
                  ['components/SessionToolbar.ets', 'components/VirtualMouse.ets', 'pages/SessionPage.ets'])
          and '.width(48).height(48).attributeModifier(floatingControl)' in session,
          'remote controls use semantic system icon colors eligible for monochrome material adaptation')
    mouse = files.get('components/VirtualMouse.ets', '')
    check('source.virtual-mouse-collapsed-icon',
          "iconResource('mouse', true, false)" in mouse
          and 'mouse_light' in files.get('model/Icons.ets', '')
          and 'mouse_dark' in files.get('model/Icons.ets', ''),
          'collapsed virtual mouse uses the official mouse silhouette and has both theme resources')
    check('source.session-floating-header',
          'ToolPageShell' not in session and 'this.floatingHeader()' in session
          and '.position({ x: 0, y: 0 })' in session
          and 'WithTheme({ colorMode: ThemeColorMode.DARK })' in session
          and '.attributeModifier(sessionMenuMaterial)' in session
          and 'SystemBars.apply(' in session,
          'remote video has a floating safe-area header, transparent system bars and a common dark menu context')
    settings_source = files.get('pages/SettingsPage.ets', '')
    check('source.settings-detail-groups',
          all("'settings.section." + name + "'" in settings_source
              for name in ['display', 'input', 'remote', 'clarity', 'motion', 'about'])
          and 'ListItemGroupStyle.CARD' in settings_source,
          'native item groups divide settings destinations by function')
    native = files.get('services/NativeSessionService.ets', '')
    check('source.control-position-lifecycle',
          all(value in session for value in ["from '@kit.MultimodalAwarenessKit'", "motion.on('holdingHandChanged', this.onHoldingHandChanged)",
              "motion.off('holdingHandChanged', this.onHoldingHandChanged)", 'settings.smartReachEnabled',
              'settings.controlBarPosition', '.alignItems(this.controlAlignment())'])
          and 'if (!this.settings.smartReachEnabled)' in settings_source
          and all(value in native for value in ["this.store.get('smartReachEnabled', true)",
              "this.store.get('controlBarPosition', 'center')", "this.persist('smartReachEnabled', enabled)",
              "this.persist('controlBarPosition', position)"]),
          'hand detection is capability gated and unsubscribed; manual positioning is conditional and persistent')
    check("source.devices-search-system",
          all(value in shell for value in ['Search({ value: this.query', "id('devices.search')",
              ".geometryTransition('devices.search.field')", 'duration: 260', '.margin(0)',
              'this.inlineRight - this.inlineWidth', 'onDeviceScroll(offset, atStart, state)']),
          "native Search morphs between the top field and an action anchored inline field")
    edge_scroll = files.get('components/EdgeScrollBar.ets', '')
    scroll_pages = ['Devices', 'Assistance', 'Settings', 'Files', 'PortMap', 'Terminal', 'Login', 'Host']
    check('source.native-edge-scrollbars',
          'state: BarState.On' in edge_scroll and '.translate({ x: 4 })' in edge_scroll
          and all(value in edge_scroll for value in ['@State scrolling: boolean = false',
              "on('scrollEvent', { id: this.scrollId }, this.onScroll)",
              "off('scrollEvent', { id: this.scrollId }, this.onScroll)",
              '.visibility(this.scrolling ? Visibility.Visible : Visibility.Hidden)'])
          and all('edgeScrollBar(' in files.get('pages/' + page + 'Page.ets', '') for page in scroll_pages)
          and 'padding:var(--top-inset) 0 80px 8px' in read(os.path.join(RAW, 'terminal', 'index.html')),
          'native edge scrollbars are hidden initially and at rest, with scoped scroll observers and lifecycle cleanup')
    check("source.audio-mute-wired",
          "setAudioMuted(!this.audioOn)" in session and "audio_toggle" not in session,
          "the sound button calls the native mute path instead of a local toggle")
    check("source.video-sync",
          "videoSync()" in session and "videoSettingsSync" in files.get("services/NativeSessionService.ets", ""),
          "CaptureSettingSync is surfaced to the session panel")

    keymap = files.get("model/KeyMap.ets", "")
    numpad = ["KEYCODE_NUMPAD_0", "KEYCODE_NUMPAD_9", "KEYCODE_NUMPAD_DIVIDE",
              "KEYCODE_NUMPAD_MULTIPLY", "KEYCODE_NUMPAD_ADD", "KEYCODE_NUMPAD_SUBTRACT",
              "KEYCODE_NUMPAD_ENTER", "KEYCODE_NUMPAD_DOT"]
    check("source.keymap-numpad", all(name in keymap for name in numpad),
          "numeric keypad keys are part of the HarmonyOS scan-code table")


def verify_tokens():
    base = json.load(open(os.path.join(HARMONY, "entry/src/main/resources/base/element/color.json"), encoding="utf-8"))
    dark = json.load(open(os.path.join(HARMONY, "entry/src/main/resources/dark/element/color.json"), encoding="utf-8"))
    base_map = {item["name"]: item["value"] for item in base["color"]}
    dark_map = {item["name"]: item["value"] for item in dark["color"]}
    expected_light = {
        "page_background": "#F5F6F8", "surface": "#FFFFFF", "primary_text": "#182431",
        "secondary_text": "#5F6B7A", "primary": "#0A59F7", "on_primary": "#FFFFFF",
        "border": "#D9DEE6", "error_text": "#B3261E", "success_text": "#1B6B3A",
        "warning_text": "#795400", "selection": "#E8F0FF",
    }
    expected_dark = {
        "page_background": "#121418", "surface": "#20242B", "primary_text": "#F1F3F5",
        "secondary_text": "#B4BBC4", "primary": "#8AB4FF", "on_primary": "#10233F",
        "border": "#454D59", "error_text": "#FFB4AB", "success_text": "#83D9A2",
        "warning_text": "#F4C86A", "selection": "#243D64",
    }
    bad = [key for key, value in expected_light.items() if base_map.get(key) != value]
    bad += [key for key, value in expected_dark.items() if dark_map.get(key) != value]
    check("tokens.colors", not bad, f"mismatched={bad}")

    bad_values = []
    for filename, key in [("color.json", "color"), ("float.json", "float"), ("string.json", "string")]:
        path = os.path.join(HARMONY, "entry", "src", "main", "resources", "base", "element", filename)
        for item in json.load(open(path, encoding="utf-8"))[key]:
            if not isinstance(item.get("value"), str):
                bad_values.append(f"{filename}:{item.get('name')}")
    check("resources.element-value-types", not bad_values,
          f"all element values are strings (fp/vp units), bad={bad_values[:6]}")


def verify_build():
    cpp = os.path.join(HARMONY, "entry", "src", "main", "cpp")
    header = read(os.path.join(cpp, "include", "uu_core.h"))
    abi = read(os.path.join(ROOT, "src", "harmony", "abi.rs"))
    check("build.abi-version",
          "#define UU_CORE_ABI_VERSION 3" in header and "pub const ABI_VERSION: i32 = 3;" in abi
          and "set_audio_muted" in header and "set_audio_muted" in abi,
          "C header and Rust ABI are both version 3 with the mute callback")

    opus = os.path.join(cpp, "third_party", "opus")
    cmake = read(os.path.join(cpp, "CMakeLists.txt"))
    opus_ok = all(os.path.exists(os.path.join(opus, name)) for name in [
        "CMakeLists.txt", "COPYING", "package_version", "configure.ac",
        "Makefile.am", "silk_sources.mk", "celt_sources.mk", "include/opus.h",
    ])
    check("build.opus-vendored",
          opus_ok and "add_subdirectory(third_party/opus" in cmake
          and "OPUS_DISABLE_INTRINSICS ON" in cmake and "opus" in cmake,
          "libopus 1.4 is vendored and linked statically")

    wrappers = [
        os.path.join(HARMONY, "hvigorw"),
        os.path.join(HARMONY, "hvigorw.bat"),
        os.path.join(ROOT, "scripts", "harmony", "build-hap.ps1"),
        os.path.join(ROOT, "scripts", "harmony", "build-native.ps1"),
    ]
    check("build.deveco-wrapper",
          all(os.path.exists(path) for path in wrappers)
          and os.access(wrappers[0], os.X_OK),
          "hvigorw wrappers and PowerShell build entry points exist")

    session = read(os.path.join(ROOT, "src", "harmony", "session.rs"))
    service = read(os.path.join(ROOT, "src", "harmony", "service.rs"))
    tools = read(os.path.join(ROOT, "src", "harmony", "tools.rs"))
    wired = all(token in session for token in ["submit_audio_packet", "has_audio_decoder", "tools.forward"])
    wired = wired and all(token in service for token in ["ensure_files", "ensure_terminal", "ensure_portmap"])
    wired = wired and "channel_transport" in tools
    wired = wired and "未在此构建中启用" not in service
    check("build.audio-tools-wired", wired,
          "Opus packet callback and files/terminal/portmap service wiring present")

    video = read(os.path.join(ROOT, "src", "harmony", "video.rs"))
    input_map = read(os.path.join(ROOT, "src", "harmony", "input.rs"))
    platform = read(os.path.join(ROOT, "src", "harmony", "platform.rs"))
    pipeline = read(os.path.join(cpp, "src", "media_pipeline.cpp"))
    check("build.video-protocol-fields",
          all(token in video for token in [
              "QUALITY_ORIGINAL: u32 = 4", "QUALITY_ULTRA: u32 = 3", "QUALITY_HD: u32 = 2",
              "CHROMA_444: u32 = 3", "30, 60, 90, 144",
          ]),
          "quality tiers, 90/144 fps and 4:4:4 chroma are encoded in the shared core")
    check("build.input-field-map",
          all(token in input_map for token in [
              "kbd_press", "kbd_release", "kbd_click", "mouse_move_absolute",
              "mouse_move_relative", "mouse_scroll", "mouse_press", "mouse_release",
              "mouse_click", "text_input", "touch_down", "touch_move", "touch_up",
          ]),
          "every official CONTROL input action has a translated wire shape")
    check("build.audio-mute-gate",
          "submit_audio_packet_if_unmuted" in session
          and "fn set_audio_muted" in platform
          and "SetAudioMuted" in pipeline
          and "audioMuted_" in pipeline,
          "mute blocks packets in Rust and stops/drops native PCM")

    cargo = read(os.path.join(ROOT, "Cargo.toml"))
    check("build.ohos-target-deps",
          'target_env = "ohos"' in cargo
          and "webrtc-util = { path = \"vendor/webrtc-util\" }" in cargo
          and os.path.exists(os.path.join(ROOT, "vendor", "webrtc-util", "PATCHES.md")),
          "OHOS target excludes desktop nix; webrtc-util uses nix 0.29 with OHOS support")

    arkts_path = os.path.join(EVIDENCE, "arkts_compile.json")
    arkts = json.load(open(arkts_path, encoding="utf-8")) if os.path.exists(arkts_path) else {}
    current = ets_fingerprint(source_files())
    recorded = arkts.get("etsFingerprint")
    if arkts.get("result") == "PASS" and recorded == current and arkts.get("compiler", {}).get("errors") == 0:
        check("build.arkts-compile", True,
              "hvigor ArkTS compilation matches the current ETS sources")
    else:
        reason = ("no recorded ArkTS build for this tree"
                  if recorded != current else "recorded build reported errors")
        check("build.arkts-compile", False,
              f"ArkTS compile is NOT_RUN for the current sources: {reason}; rerun hvigorw assembleHap",
              result="NOT_RUN")


def main():
    os.makedirs(EVIDENCE, exist_ok=True)
    verify_assets()
    verify_contract()
    files = source_files()
    verify_sources(files)
    verify_tokens()
    verify_build()
    report = {
        "kind": "static_verification",
        "root": "uu-remote-linux",
        "checks": checks,
        "passed": sum(1 for item in checks if item["result"] == "PASS"),
        "failed": sum(1 for item in checks if item["result"] == "FAIL"),
        "notRun": sum(1 for item in checks if item["result"] == "NOT_RUN"),
        "note": "Static checks do not replace Hypium/UiTest runtime evidence.",
    }
    with open(os.path.join(EVIDENCE, "static_report.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    for item in checks:
        print(f"{item['result']}\t{item['id']}\t{item['detail']}")
    print(f"summary passed={report['passed']} failed={report['failed']} not_run={report['notRun']}")
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
