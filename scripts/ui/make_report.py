#!/usr/bin/env python3
"""Summarize recorded builds and native UI runs without inferring test passes."""
import hashlib
import json
import subprocess
from pathlib import Path
from verify_static import ets_fingerprint, source_files

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'tests/ui/evidence'


def read_json(path, default):
    return json.loads(path.read_text(encoding='utf-8')) if path.is_file() else default


def tree_fingerprint(root, pattern, text=False):
    digest = hashlib.sha256()
    for path in sorted(root.rglob(pattern), key=lambda p: p.relative_to(root).as_posix()):
        if path.is_file():
            digest.update(path.relative_to(root).as_posix().encode())
            digest.update(b'\0')
            digest.update(path.read_text(encoding='utf-8').encode() if text else path.read_bytes())
            digest.update(b'\0')
    return digest.hexdigest()


def main():
    cases = read_json(ROOT / 'tests/ui/ui_cases.json', {'cases': []})['cases']
    contract_path = ROOT / 'tests/ui/ui_contract.json'
    contract = read_json(contract_path, {})
    static = read_json(EVIDENCE / 'static_report.json', {})
    build = read_json(EVIDENCE / 'arkts_compile.json', {})
    runtime = read_json(EVIDENCE / 'native_runtime_regression.json', {})
    fingerprint = ets_fingerprint(source_files())
    fingerprints = {
        'etsFingerprint': fingerprint,
        'testFingerprint': tree_fingerprint(ROOT / 'harmony/entry/src/ohosTest/ets', '*.ets', True),
        'resourcesFingerprint': tree_fingerprint(ROOT / 'harmony/entry/src/main/resources', '*'),
    }
    build_current = build.get('result') == 'PASS' and all(build.get(key) == value for key, value in fingerprints.items())
    for name in ['artifact', 'testArtifact']:
        artifact = build.get(name, {})
        path = ROOT / artifact.get('file', '')
        build_current = build_current and path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == artifact.get('sha256')
    runtime_current = (build_current and all(runtime.get(key) == value for key, value in fingerprints.items())
                       and runtime.get('artifactSha256') == build.get('artifact', {}).get('sha256')
                       and runtime.get('testArtifactSha256') == build.get('testArtifact', {}).get('sha256'))
    runs = [run for run in runtime.get('runs', []) if run.get('stage') == 'full'] if runtime_current else []
    passed = sum(run.get('passed', 0) for run in runs)
    failed = sum(run.get('failure', 0) + run.get('error', 0) for run in runs)
    success = build_current and len(runs) == 3 and all(run.get('result') == 'PASS' for run in runs)
    try:
        commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        commit = None
    limitations = [
        'UI 运行测试使用 MockSessionService，控制偏好另以 NativeSessionService 验证服务重建后的持久化；真实账号、信令、音视频及远端工具互通未在本组 UI 测试中验证。',
        'Phone、PC 使用 HarmonyOS 7 / API 26；Pad 使用 HarmonyOS 6.1.1 / API 24 镜像。',
        '44 条 UiAcceptance 计划用例未逐项执行；MultiDeviceRegression 的运行结果单独统计。',
        '视觉基准仍待用户确认；静态检查不计入运行测试通过数。',
    ]
    report = {
        'schemaVersion': '1.0.0', 'exampleOnly': False,
        'status': 'REGRESSION_PASS' if success else 'REGRESSION_INCOMPLETE',
        'build': {'sourceCommit': commit, 'worktreeDirty': True,
                  'hapSha256': build.get('artifact', {}).get('sha256'),
                  **fingerprints, 'evidenceMatchesSources': build_current},
        'environment': {'type': 'NATIVE_EMULATORS', 'platforms': runtime.get('platforms', []),
                        'service': runtime.get('service'), 'locale': 'zh-CN'},
        'contract': {'version': contract.get('contractVersion'),
                     'sha256': hashlib.sha256(contract_path.read_bytes()).hexdigest()},
        'observations': [],
        'checks': [{'id': case['id'], 'actual': None, 'result': 'NOT_RUN',
                    'reason': 'UiAcceptance planned case not individually executed in this run',
                    'evidenceRefs': []} for case in cases],
        'summary': {'planned': len(cases), 'passed': 0, 'failed': 0, 'notRun': len(cases), 'blocked': 0},
        'regressionSummary': {'suite': 'MultiDeviceRegression', 'sourcesMatch': runtime_current,
                              'deviceRuns': len(runs), 'passed': passed, 'failed': failed},
        'nativeRuntimeRegression': runtime,
        'buildChecks': [{'id': 'arkts-compile', 'command': build.get('command'),
                         'result': 'PASS' if build_current else 'NOT_RUN',
                         'compiler': build.get('compiler'),
                         'evidenceRefs': ['tests/ui/evidence/arkts_compile.json']}],
        'staticChecks': static.get('checks', []),
        'staticSummary': {'passed': static.get('passed', 0), 'failed': static.get('failed', 0),
                          'notRun': static.get('notRun', 0)},
        'visualStatus': 'VISUAL_REVIEW_PENDING', 'limitations': limitations,
    }
    (ROOT / 'tests/ui/ui_report.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    compiler = build.get('compiler', {})
    lines = ['# UI 验收摘要', '',
             f"- 编译：{'通过' if build_current else '证据未匹配当前源码'}；错误 {compiler.get('errors', '未知')}，警告 {compiler.get('warnings', '未知')}",
             f'- MultiDeviceRegression：{len(runs)} 个设备环境，{passed} 通过，{failed} 失败',
             f"- 静态检查：{static.get('passed', 0)} 通过，{static.get('failed', 0)} 失败，{static.get('notRun', 0)} 未运行",
             f'- UiAcceptance 计划用例：{len(cases)} 未逐项运行',
             '- 视觉状态：VISUAL_REVIEW_PENDING', '', '## 设备运行结果', '']
    lines += [f"- {run['device']}：{run.get('passed', 0)}/{run.get('tests', 0)} 通过，失败 {run.get('failure', 0)}，错误 {run.get('error', 0)}" for run in runs]
    lines += ['', '## 验证范围', ''] + ['- ' + item for item in limitations]
    (ROOT / 'tests/ui/ui_report.summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps({'status': report['status'], **report['regressionSummary']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
