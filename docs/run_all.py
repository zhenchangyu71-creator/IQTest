"""一次跑完全部诊断，汇总结果。

改动题目参数、换算公式或标定文件之后，跑这一个命令即可：
它按顺序执行门禁与三份诊断报告，退出码反映门禁是否通过。

用法：
    python3 docs/run_all.py            # 跑全部
    python3 docs/run_all.py --quick    # 跳过耗时最长的方案对比

退出码：0 全部通过；1 门禁发现劣化；2 运行失败。
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# (脚本路径, 说明, 是否耗时)。路径相对仓库根。
STEPS = [
    ('docs/run_diagnostics.py', '标定与难度门禁（相对基线是否劣化）', False),
    ('docs/ITEM_DIFFICULTY_AUDIT.py', '逐分测验难度与 A/B 参数关系', False),
    ('tools/check_generator_consistency.py', '题库与生成器是否还对得上', False),
    ('docs/MEASUREMENT_PRECISION.py', '测量精度与区分度敏感性', True),
    ('docs/ALGORITHM_COMPARISON.py', '几套换算方案的输出对比', True),
]

# 两个独立实现给出的建议斜率应当一致：自检脚本与标定脚本各写了一套流程，
# 一旦漂移，说明其中之一改坏了。这里用合成被试做交叉核对。
CONSISTENCY_SUBJECTS = 30
CONSISTENCY_TOLERANCE = 0.02


def _run_json(script, *args):
    """跑一个脚本并解析它的 JSON 输出，失败时返回 None。"""
    result = subprocess.run(
        [sys.executable, os.path.join(HERE, script), *args],
        cwd=HERE, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def cross_check():
    """核对标定脚本与自检脚本的建议斜率是否一致。

    两个脚本必须都真的跑起来再比。拿一个写死的常数当「自检脚本的值」，
    只会发现标定脚本的改动，发现不了自检脚本自己的改动——那正是最该被发现的情况。
    两者用同一随机种子生成同一批合成被试，结果应当一致。
    """
    calibration = _run_json('calibrate_slopes.py', '--synthetic',
                             str(CONSISTENCY_SUBJECTS), '--json')
    if calibration is None:
        return False, '标定脚本运行失败或输出无法解析'
    self_check = _run_json('ALGORITHM_SELF_CHECK.py',
                            str(CONSISTENCY_SUBJECTS), '--json')
    if self_check is None:
        return False, '自检脚本运行失败或输出无法解析'
    suggested = calibration['suggestedFullScaleSlope']
    reference = self_check['suggestedFullScaleSlope']
    delta = abs(suggested - reference) / reference
    if delta > CONSISTENCY_TOLERANCE:
        return False, (f'标定脚本建议全量表分斜率 {suggested:.4f}，'
                       f'自检脚本为 {reference:.4f}，相差 {delta * 100:.2f}%，超出容差')
    return True, (f'两个独立实现在同一批合成被试上一致：'
                  f'全量表分斜率 {suggested:.4f}（相差 {delta * 100:.2f}%）')


def roundtrip_check():
    """核对真实标定路径的端到端可用性。

    真实数据要走「应用导出 → calibration_export.py → csv → 标定脚本」这条链，
    而这条链此前从未被验证过：它两处逻辑（要求覆盖全部 480 题、把 None 送进相关系数）
    会让真实数据永远无法参与标定，而表面看不出来。
    """
    result = subprocess.run(
        [sys.executable, os.path.join(HERE, 'calibrate_slopes.py'), '--selfcheck', '40'],
        cwd=HERE, capture_output=True, text=True)
    message = (result.stdout or '').strip() or (result.stderr or '').strip()[:200]
    return result.returncode == 0, message


def main():
    quick = '--quick' in sys.argv
    failures = []
    for script, description, slow in STEPS:
        if quick and slow:
            print(f'\n=== 跳过：{script}（{description}）===')
            continue
        print(f'\n=== {script} — {description} ===')
        result = subprocess.run([sys.executable, os.path.join(ROOT, script)],
                                cwd=HERE, capture_output=True, text=True)
        output = (result.stdout or '') + (result.stderr or '')
        # 门禁的输出是给人看的，完整保留；其余脚本只留摘要。
        if script != 'docs/run_diagnostics.py':
            lines = [line for line in output.splitlines()
                     if line.strip() and '提示' not in line]
            output = '\n'.join(lines[:40])
        print(output.rstrip())
        if result.returncode != 0:
            failures.append((script, result.returncode))

    print('\n=== 真实标定路径的端到端自检 ===')
    ok, message = roundtrip_check()
    print(message)
    if not ok:
        failures.append(('calibrate_slopes.py 端到端自检', 1))

    print('\n=== 一致性核对：标定脚本 vs 自检脚本 ===')
    ok, message = cross_check()
    print(message)
    if not ok:
        failures.append(('calibrate_slopes.py 一致性核对', 1))

    print('\n' + '=' * 60)
    if failures:
        print('有步骤未通过：')
        for script, code in failures:
            print(f'   {script}（退出码 {code}）')
        print('\n若改动是有意的，先确认门禁报告里的指标变化符合预期，')
        print('再执行 `python3 docs/run_diagnostics.py --update` 重建基线。')
        return 1
    print('全部诊断通过。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
