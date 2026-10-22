"""诊断门禁：检查标定状态与题库难度是否相对基线发生劣化。

背景：换算斜率是借用的、题目参数是启发式设定的，这两点都很容易被一次「顺手的小改动」
悄悄改坏，而没有人察觉。本脚本用固定种子、固定规模的一组合成被试跑一遍关键指标，
与基线文件比对，偏差超容差就以非零退出码失败。

确定性来源：合成被试由固定随机种子生成，能力模型是确定性的，
所以每次运行得到的数字完全相同——比对的是精确值，不是统计噪声。

用法：
    python3 docs/run_diagnostics.py              # 与基线比对
    python3 docs/run_diagnostics.py --json       # 机器可读输出
    python3 docs/run_diagnostics.py --update     # 重新建立基线（改动参数后需显式执行）

退出码：0 全部通过；1 存在劣化项；2 运行失败。
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ALGORITHM_SELF_CHECK as core  # noqa: E402

BASELINE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'diagnostics_baseline.json')
# 合成被试数量固定，保证结果确定；样本少会让离散度估计偏粗，因此用中等规模。
SUBJECTS = 60
SEED = 20261022

# 允许相对基线的漂移。数值取略大于「更换合成被试规模」带来的波动，
# 以免小改动被误报；但任何有实质影响的参数或换算改动都会超出。
TOLERANCE = {
    'compositeSD': 0.6,
    'difficultyMean': 0.4,
    'difficultySD': 0.4,
    'compositeMean': 1.5,
}


def measure():
    """跑一遍固定样本，得出关键指标。"""
    import random
    rng = random.Random(SEED)
    results = []
    for _ in range(SUBJECTS):
        theta = rng.gauss(0.0, 1.0)
        results.append((theta, core.profile(core.simulate(theta, rng))))

    centers = [p['theta_center'] for _, p in results]
    fsiqs = [p['fsiq'] for _, p in results]
    _, sd_composite = core.mean_sd(fsiqs)
    mean_composite = core.mean_sd(fsiqs)[0]

    # θ=0 时各分测验的预期得分率，用于难度整齐度
    baseline_rates = {}
    for sub in core.SUBTESTS:
        items = [it for it in core.BANK if it['subtest'] == sub]
        earned = 0.0
        max_total = 0
        for item in items:
            probabilities = core.prob(item, core.PARAMS[item['id']], 0.0)
            earned += sum(score * p for score, p in probabilities.items())
            max_total += max(item['optionScores'])
        baseline_rates[sub] = earned / max_total if max_total else 0.0
    rates = list(baseline_rates.values())
    # 极差对中间层的变化不敏感（max 与 min 都不动就不变），所以同时看均值与标准差。
    spread = (max(rates) - min(rates)) * 100
    mean_rate = sum(rates) / len(rates) * 100
    sd_rate = core.mean_sd(rates)[1] * 100

    # 题目参数指纹：任何一道题的阈值或区分度变动都会改变它。
    fingerprint_source = json.dumps(
        [[item['itemID'], item['thresholds'], item['discrimination']]
         for item in core.MODEL['items']], sort_keys=True)
    fingerprint = hashlib.sha256(fingerprint_source.encode('utf-8')).hexdigest()[:16]

    return {
        'compositeSD': round(sd_composite, 3),
        'compositeMean': round(mean_composite, 3),
        'difficultyMean': round(mean_rate, 3),
        'difficultySD': round(sd_rate, 3),
        'difficultySpread': round(spread, 2),
        'parameterFingerprint': fingerprint,
        'reliability': round(core.mean_sd(centers)[1] / core.mean_sd([t for t, _ in results])[1], 4),
        'subjects': SUBJECTS,
        'seed': SEED,
    }


def load_baseline():
    if not os.path.exists(BASELINE_PATH):
        return None
    with open(BASELINE_PATH, encoding='utf-8') as handle:
        return json.load(handle)


def compare(current, baseline):
    findings = []
    for key, tolerance in TOLERANCE.items():
        if key not in baseline:
            continue
        delta = current[key] - baseline[key]
        status = 'OK' if abs(delta) <= tolerance else '劣化'
        findings.append({
            'metric': key,
            'current': current[key],
            'baseline': baseline[key],
            'delta': round(delta, 3),
            'tolerance': tolerance,
            'status': status,
        })
    # 题目参数指纹做精确比对：任何一道题的阈值或区分度变动都会被抓到。
    if 'parameterFingerprint' in baseline:
        changed = current['parameterFingerprint'] != baseline['parameterFingerprint']
        findings.append({
            'metric': 'parameterFingerprint',
            'current': current['parameterFingerprint'],
            'baseline': baseline['parameterFingerprint'],
            'delta': '有变化' if changed else '无变化',
            'tolerance': '精确',
            'status': '劣化' if changed else 'OK',
        })
    return findings


def main():
    args = sys.argv[1:]
    as_json = '--json' in args
    update = '--update' in args

    current = measure()
    baseline = load_baseline()

    if baseline is None or update:
        with open(BASELINE_PATH, 'w', encoding='utf-8') as handle:
            json.dump(current, handle, ensure_ascii=False, indent=2)
        if as_json:
            print(json.dumps({'status': 'baseline_written', 'baseline': current},
                             ensure_ascii=False, indent=2))
        else:
            print('已建立基线：' + BASELINE_PATH)
            for key, value in current.items():
                print(f'   {key:<18}{value}')
        return 0

    findings = compare(current, baseline)
    failed = [f for f in findings if f['status'] != 'OK']

    if as_json:
        print(json.dumps({'status': 'failed' if failed else 'ok',
                          'current': current, 'findings': findings},
                         ensure_ascii=False, indent=2))
    else:
        print('诊断门禁：标定与难度指标相对基线的漂移\n')
        print(f'{"指标":<22}{"当前":>12}{"基线":>12}{"偏差":>10}{"容差":>8}  结论')
        print('-' * 76)
        for finding in findings:
            delta = finding['delta']
            if isinstance(delta, str):
                delta_text = delta
            else:
                delta_text = f'{delta:.2f}'
            current_text = str(finding['current'])
            baseline_text = str(finding['baseline'])
            if len(current_text) > 12:
                current_text = current_text[:12] + '…'
            if len(baseline_text) > 12:
                baseline_text = baseline_text[:12] + '…'
            print(f'{finding["metric"]:<22}{current_text:>12}{baseline_text:>12}'
                  f'{delta_text:>10}{str(finding["tolerance"]):>8}  {finding["status"]}')
        print()
        if failed:
            print('有指标超出容差。如果这是有意改动，请执行 --update 重新建立基线，')
            print('并在提交说明里写清改动原因。')
        else:
            print('全部指标在容差内。')

    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
