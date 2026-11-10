#!/usr/bin/env python3
"""Apply theme colours to official exported SVGs without changing geometry."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCES = Path(__file__).with_name('huawei')
MEDIA = ROOT / 'harmony/entry/src/main/resources/base/media'
RAW = ROOT / 'harmony/entry/src/main/resources/rawfile'
WEBSITE = 'https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/'
SVG = '{http://www.w3.org/2000/svg}'
ET.register_namespace('', SVG[1:-1])
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
ICONS = {
    'devices': 'ohos_ic_public_device_matebook', 'assist': 'hand_tap',
    'settings': 'gearshape', 'refresh': 'arrow_clockwise', 'search': 'magnifyingglass',
    'more': 'ohos_ic_public_more', 'back': 'chevron_left', 'chevron': 'chevron_right',
    'keyboard': 'keyboard', 'cursor': 'hand_point_up_tap_fill', 'quality': 'hd_square_fill',
    'folder': 'folder', 'terminal': 'keyboard', 'clipboard': 'text_clipboard',
    'close': 'xmark', 'check': 'checkmark', 'volume': 'speaker_wave_2',
    'host': 'ohos_ic_public_cast_mirror',
    'rotate': 'rectangle_portrait_rotate',
    'pointer': 'arrow_up_left', 'drag': 'hand_draw', 'mouse': 'mouse',
    'pip': 'smal_window_playback',
    'device_phone': 'ohos_ic_public_device_phone',
    'device_tv': 'ohos_ic_public_device_smartscreen',
}
COLORS = {'light': '#182431', 'dark': '#F1F3F5',
          'selected_light': '#0A59F7', 'selected_dark': '#8AB4FF'}


def paint(node, color):
    if node.tag == SVG + 'defs':
        return
    if node.tag in {SVG + 'path', SVG + 'circle', SVG + 'ellipse', SVG + 'polygon', SVG + 'use'}:
        if node.get('fill') != 'none':
            node.set('fill', color)
    for child in node:
        paint(child, color)


def geometry(node):
    if node.tag == SVG + 'defs':
        return ET.tostring(node, encoding='unicode')
    return [node.tag, {k: v for k, v in node.attrib.items() if k not in {'fill', 'viewBox'}},
            [geometry(child) for child in node]]


def main():
    manifest = {'schemaVersion': '1.2.0', 'style': 'official_huawei_exported_svg',
                'source': 'Huawei HarmonyOS Symbol SVG export and DevEco SDK system SVG resources',
                'origin': 'Official SVG paths, proportions and masks preserved; theme colours only',
                'icons': {}}
    for key, name in ICONS.items():
        source = SOURCES / (name + '.svg')
        raw = source.read_bytes()
        original = ET.fromstring(raw)
        source_info = {'file': str(source.relative_to(ROOT)).replace('\\', '/'),
                       'sha256': hashlib.sha256(raw).hexdigest(), 'name': name,
                       'origin': ('DevEco SDK API 26 HMSymbolVF.ttf smal_window_playback U+F068D, unmodified glyph outline exported as SVG'
                                  if name == 'smal_window_playback' else 'DevEco SDK API 26 HMSymbolVF.ttf mouse U+F03A6, unmodified glyph outline exported as SVG'
                                  if name == 'mouse' else 'DevEco SDK API 26 system resource SVG'
                                  if name.startswith('ohos_') else WEBSITE)}
        manifest['icons'][key] = {}
        for variant, color in COLORS.items():
            tree = ET.fromstring(raw)
            tree.set('viewBox', tree.get('viewBox', f"0 0 {tree.get('width')} {tree.get('height')}"))
            paint(tree, color)
            assert geometry(tree) == geometry(original), (key, variant, 'geometry changed')
            body = ET.tostring(tree, encoding='utf-8') + b'\n'
            filename = f'{key}_{variant}.svg'
            (MEDIA / filename).write_bytes(body)
            if key in {'devices', 'assist', 'settings'} and variant in {'light', 'dark'}:
                tab_icon = ET.fromstring(body)
                tab_icon.attrib.pop('width', None)
                tab_icon.attrib.pop('height', None)
                tab_icons = RAW / 'tab-icons'
                tab_icons.mkdir(exist_ok=True)
                (tab_icons / filename).write_bytes(ET.tostring(tab_icon, encoding='utf-8') + b'\n')
            manifest['icons'][key][variant] = {'file': 'assets/' + filename,
                'sha256': hashlib.sha256(body).hexdigest(), 'source': source_info,
                'viewBox': tree.get('viewBox'), 'color': color}
    text = json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'
    (RAW / 'assets_manifest.json').write_text(text, encoding='utf-8', newline='\n')
    (ROOT / 'tests/ui/assets_manifest.json').write_text(text, encoding='utf-8', newline='\n')
    print(f'Verified and themed {len(ICONS) * len(COLORS)} official SVG resources')


if __name__ == '__main__':
    main()
