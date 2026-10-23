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

# 允许相对基线的漂移。能力抽样用固定网格后，同一代码每次运行结果完全一致，
# 这里的容差只需容纳「等价重写」带来的浮点级差异，同时仍要能抓住
# 斜率或题目参数的小幅改动——斜率变动 2% 会让合成分离散度变动约 0.3 分。
TOLERANCE = {
    'compositeSD': 0.3,
    'adminCompositeSD': 0.15,
    'difficultyMean': 0.4,
    'difficultySD': 0.4,
    'compositeMean': 1.5,
}

# 真实施测情形：每分测验抽 12 题、一轮共 120 题，与生产环境的抽题量一致。
ADMIN_PER_SUBTEST = 12

# 能力抽样用固定网格，每个能力点重复若干次后取平均。
# 换成随机抽 60 个 θ 时，θ 的实现标准差会在 0.88–0.93 之间摆动，
# 让同一个量给出相差 5% 以上的离散度——而斜率改动带来的变化往往只有 2–4%，
# 那样门禁既会误报，也抓不住真正的漂移。固定网格把能力这一维的噪声消掉，
# 剩下的只是题目抽样的抖动（同一网格下由种子固定，重复运行结果完全一致）。
GRID_REPEATS = 5


def measure_grid(rng, per_subtest):
    """固定能力网格下的作答与换算结果。per_subtest 为 0 表示全部题目作答。"""
    results = []
    for theta in core.theta_grid():
        runs = [core.profile(core.simulate(theta, rng, per_subtest=per_subtest))
                for _ in range(GRID_REPEATS)]
        results.append((theta, {
            'theta_center': sum(r['theta_center'] for r in runs) / len(runs),
            'scaled': {sub: sum(r['scaled'][sub] for r in runs) / len(runs)
                       for sub in runs[0]['scaled']},
            'fsiq': sum(r['fsiq'] for r in runs) / len(runs),
            'indices': {dom: sum(r['indices'][dom] for r in runs) / len(runs)
                        for dom in runs[0]['indices']},
            'sum_scaled': sum(r['sum_scaled'] for r in runs) / len(runs),
        }))
    return results


def measure():
    """跑一遍固定样本，得出关键指标。"""
    import random
    rng = random.Random(SEED)
    results = measure_grid(rng, 0)

    centers = [p['theta_center'] for _, p in results]
    fsiqs = [p['fsiq'] for _, p in results]
    _, sd_composite = core.mean_sd(fsiqs)
    mean_composite = core.mean_sd(fsiqs)[0]
    # 固定网格的实现标准差正好是 1，离散度无需再归一化。

    # 真实施测口径：使用者每轮只做 120 题，这才是他们实际看到的输出离散度。
    # 用独立种子，避免与上面那组共享随机序列而互相耦合。
    admin_rng = random.Random(SEED + 1)
    admin_fsiqs = [p['fsiq'] for _, p in measure_grid(admin_rng, ADMIN_PER_SUBTEST)]
    _, sd_admin = core.mean_sd(admin_fsiqs)

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
        'adminCompositeSD': round(sd_admin, 3),
        'compositeMean': round(mean_composite, 3),
        'difficultyMean': round(mean_rate, 3),
        'difficultySD': round(sd_rate, 3),
        'difficultySpread': round(spread, 2),
        'parameterFingerprint': fingerprint,
        # 可靠度用「估计值与真实能力的相关」衡量。估计值的离散度不是可靠度：
        # 模型误设时离散度会被放大，用离散度衡量会得出「误设反而更准」的反直觉结论。
        'reliability': round(core.correlation(centers, [t for t, _ in results]), 4),
        'gridPoints': len(core.theta_grid()),
        'gridRepeats': GRID_REPEATS,
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
