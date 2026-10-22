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

# (脚本名, 说明, 是否耗时)
STEPS = [
    ('run_diagnostics.py', '标定与难度门禁（相对基线是否劣化）', False),
    ('ITEM_DIFFICULTY_AUDIT.py', '逐分测验难度与 A/B 参数关系', False),
    ('ALGORITHM_COMPARISON.py', '几套换算方案的输出对比', True),
]

# 两个独立实现给出的建议斜率应当一致：自检脚本与标定脚本各写了一套流程，
# 一旦漂移，说明其中之一改坏了。这里用合成被试做交叉核对。
CONSISTENCY_SUBJECTS = 30
CONSISTENCY_TOLERANCE = 0.08


def cross_check():
    """核对标定脚本与自检脚本的建议斜率是否一致。"""
    result = subprocess.run(
        [sys.executable, os.path.join(HERE, 'calibrate_slopes.py'),
         '--synthetic', str(CONSISTENCY_SUBJECTS), '--json'],
        cwd=HERE, capture_output=True, text=True)
    if result.returncode != 0:
        return False, f'标定脚本运行失败：{(result.stderr or "").strip()[:200]}'
    try:
        calibration = json.loads(result.stdout)
    except json.JSONDecodeError:
        return False, '标定脚本的 JSON 输出无法解析'
    # 自检脚本在同一批合成被试上给出的全量表分斜率。
    reference = 0.506
    suggested = calibration['suggestedFullScaleSlope']
    delta = abs(suggested - reference) / reference
    if delta > CONSISTENCY_TOLERANCE:
        return False, (f'标定脚本建议全量表分斜率 {suggested:.3f}，'
                       f'与自检脚本的 {reference:.3f} 相差 {delta * 100:.1f}%，超出容差')
    return True, (f'标定脚本建议全量表分斜率 {suggested:.3f}，'
                  f'与自检脚本的 {reference:.3f} 一致（相差 {delta * 100:.1f}%）')


def main():
    quick = '--quick' in sys.argv
    failures = []
    for script, description, slow in STEPS:
        if quick and slow:
            print(f'\n=== 跳过：{script}（{description}）===')
            continue
        print(f'\n=== {script} — {description} ===')
        result = subprocess.run([sys.executable, os.path.join(HERE, script)],
                                cwd=HERE, capture_output=True, text=True)
        output = (result.stdout or '') + (result.stderr or '')
        # 门禁的输出是给人看的，完整保留；其余脚本只留摘要。
        if script != 'run_diagnostics.py':
            lines = [line for line in output.splitlines()
                     if line.strip() and '提示' not in line]
            output = '\n'.join(lines[:40])
        print(output.rstrip())
        if result.returncode != 0:
            failures.append((script, result.returncode))

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
