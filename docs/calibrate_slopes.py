"""用真实作答数据重新标定合成分斜率。

背景：生产代码借用的斜率（指数分 2.75、全量表分 0.72）是**为韦氏题库标定**的，
其前提是「尺度分之和的离散度与韦氏题库相同（≈20.8）」。本项目每个分测验只有 12 题、
区分度全为 1.0，能力估计被压窄，该前提不成立——合成被试自检显示实际离散度与目标 15 分不符。

本脚本把自检里那套流程原样跑一遍，但换成真实作答：估计能力参数、换算尺度分、
实测尺度分之和的离散度，据此反推「让合成分标准差回到 15」的斜率。

不依赖 numpy/scipy，纯 Python。

用法：
    python3 docs/calibrate_slopes.py <calibration_export 产出的目录> [--synthetic N]

    --synthetic N  不读真实数据，改用 N 个合成被试跑同一流程。
                   真值已知，用来检验脚本本身是否正确。

退出码：0 成功；1 数据不足或输入有误。
"""
import csv
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ALGORITHM_SELF_CHECK as core  # noqa: E402

CALIBRATION_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                                'IQTest', 'Resources', 'ScoringCalibration.json')
# 目标：合成分的标准差回到量表定义上的 15。
TARGET_SD = 15.0


def read_csv(path):
    if not os.path.exists(path):
        return None
    with open(path, newline='', encoding='utf-8') as handle:
        return list(csv.DictReader(handle))


def synthetic_subjects(count):
    import random
    rng = random.Random(core.SEED if hasattr(core, 'SEED') else 20261022)
    subjects = []
    for _ in range(count):
        theta = rng.gauss(0.0, 1.0)
        responses = core.simulate(theta, rng)
        subjects.append((f'synthetic-{len(subjects):03d}', responses, theta))
    return subjects


def real_subjects(directory):
    responses = read_csv(os.path.join(directory, 'responses.csv'))
    persons = read_csv(os.path.join(directory, 'persons.csv'))
    if not responses or not persons:
        return None, '缺少 responses.csv 或 persons.csv，请先运行 calibration_export.py。'

    complete = {}
    for person in persons:
        if person.get('completion') != 'completed':
            continue
        answered = int(person.get('items_answered') or 0)
        total = int(person.get('items_total') or 0)
        if total > 0 and answered == total:
            complete[person['person_id']] = True
    if not complete:
        return None, '没有完整作答的记录，无法标定（超时与中断会污染离散度估计）。'

    grouped = {}
    for row in responses:
        pid = row['person_id']
        if pid not in complete:
            continue
        if row.get('outcome') != 'answered':
            continue
        grouped.setdefault(pid, {})[row['item_id']] = int(row['score'])
    if not grouped:
        return None, '完整记录中没有可用的作答。'

    subjects = []
    for pid, scores in sorted(grouped.items()):
        if len(scores) < len(core.BANK):
            continue
        subjects.append((pid, scores, None))
    if not subjects:
        return None, '没有覆盖全部题目的完整记录。'
    return subjects, None


def measure(subjects):
    """对每个被试跑一遍剖面估计，收集关键量。"""
    thetas, scaled_sums, fsiqs = [], [], []
    # 域内的尺度分之和（不是合成分——合成分已乘过斜率，再除一次会双重缩放）
    domain_scaled = {d: [] for d in ['verbal', 'perceptual', 'memory', 'speed']}
    truths = []
    for _pid, responses, true_theta in subjects:
        profile = core.profile(responses)
        thetas.append(profile['theta_center'])
        truths.append(true_theta)
        scaled_sums.append(profile['sum_scaled'])
        fsiqs.append(profile['fsiq'])
        for domain in domain_scaled:
            members = [s for s in core.SUBTESTS if core.DOMAIN[s] == domain]
            domain_scaled[domain].append(sum(profile['scaled'][s] for s in members))
    return {
        'thetaSD': core.mean_sd(thetas)[1],
        # 可靠度用「与真实能力的相关」衡量，不是估计值的离散度：
        # 模型误设时离散度会被放大，用离散度衡量会得出「误设反而更准」的反直觉结论。
        'reliability': core.correlation(thetas, truths) if truths else None,
        # 合成被试有真值时，θ 的实现标准差未必正好是 1，反推斜率前要按它归一化。
        'trueThetaSD': core.mean_sd(truths)[1] if truths else None,
        'scaledSumSD': core.mean_sd(scaled_sums)[1],
        'compositeSD': core.mean_sd(fsiqs)[1],
        'domainScaledSD': {d: core.mean_sd(v)[1] for d, v in domain_scaled.items() if v},
    }


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    as_json = '--json' in sys.argv
    synthetic = None
    if '--synthetic' in sys.argv:
        index = sys.argv.index('--synthetic')
        synthetic = int(sys.argv[index + 1]) if index + 1 < len(sys.argv) else 60

    calibration = json.load(open(CALIBRATION_PATH, encoding='utf-8'))

    if synthetic is not None:
        subjects = synthetic_subjects(synthetic)
        source = f'合成被试 {synthetic} 个（真值已知，用于检验脚本本身）'
    else:
        if not args:
            print(__doc__)
            return 1
        subjects, error = real_subjects(args[0])
        if subjects is None:
            print(error)
            return 1
        source = f'真实作答 {len(subjects)} 名被试（来自 {args[0]}）'

    measured = measure(subjects)
    theta_sd = measured['thetaSD']
    reliability = measured.get('reliability')
    scaled_sum_sd = measured['scaledSumSD']
    composite_sd = measured['compositeSD']

    # 标定的目标是让合成分的标准差等于 15，也就是「刻度」对齐韦氏的量表定义。
    # 反推方式是：目标 SD ÷ 尺度分之和在真实能力分布下的离散度。
    #
    # 合成被试有真值：θ 的实现标准差未必正好是 1（有限样本的抽样波动），
    # 先按它归一化——这一支与 ALGORITHM_SELF_CHECK.py 是同一个口径，
    # 两者的结果可以直接对照。
    # 真实作答没有真值，只能采用先验假设「真实人群的能力标准差为 1」：
    # 这个假设未经任何常模验证，脚本会把它写在输出里。
    true_theta_sd = measured.get('trueThetaSD')
    if true_theta_sd:
        normalization = true_theta_sd
        basis = f'合成被试的 θ 实现标准差 {normalization:.3f}'
    else:
        normalization = 1.0
        basis = '先验假设真实人群的能力标准差为 1.000（未经常模验证）'

    suggested_full_scale = TARGET_SD * normalization / scaled_sum_sd
    suggested_index = {}
    for domain, sd in measured['domainScaledSD'].items():
        suggested_index[domain] = TARGET_SD * normalization / sd
    mean_index = sum(suggested_index.values()) / len(suggested_index)

    if as_json:
        print(json.dumps({
            'source': source,
            'thetaSD': round(theta_sd, 4),
            'normalization': round(normalization, 4),
            'normalizationBasis': basis,
            'scaledSumSD': round(scaled_sum_sd, 3),
            'compositeSD': round(composite_sd, 3),
            'targetCompositeSD': TARGET_SD,
            'suggestedFullScaleSlope': round(suggested_full_scale, 4),
            'suggestedIndexSlope': round(mean_index, 4),
            'suggestedIndexSlopeByDomain': {k: round(v, 4) for k, v in suggested_index.items()},
            'currentFullScaleSlope': calibration['fullScaleSlope'],
            'currentIndexSlope': calibration['indexSlope'],
        }, ensure_ascii=False, indent=2))
        return 0

    print(f'标定来源：{source}\n')
    print('实测结果')
    print(f'   能力参数的标准差            {theta_sd:.3f}（收缩压窄后的估计值离散度）')
    print(f'   归一化依据                  {basis}')
    print(f'   尺度分之和的标准差          {scaled_sum_sd:.2f}（归一化后 {scaled_sum_sd / normalization:.2f}）')
    print(f'   当前合成分的标准差          {composite_sd:.2f}（目标 {TARGET_SD:.0f}）')
    print()
    print('建议的换算斜率')
    print(f'   全量表分                    {suggested_full_scale:.3f}'
          f'（当前借用 {calibration["fullScaleSlope"]}）')
    for domain in ['verbal', 'perceptual', 'memory', 'speed']:
        print(f'   {domain:11s} 指数分          {suggested_index[domain]:.3f}'
              f'（当前借用 {calibration["indexSlope"]}）')
    print(f'   指数分（各域平均）          {mean_index:.3f}')

    if synthetic is not None:
        print('\n合成被试下，脚本的输出应当接近「让合成分标准差等于 15」的解析解。')
        print(f'   当前合成分标准差 {composite_sd:.2f}，目标 {TARGET_SD:.0f}，'
              f'故建议斜率约为当前借用值的 {calibration["fullScaleSlope"] / suggested_full_scale:.2f} 倍。')

    print('\n下一步：')
    print('  1. 确认合成分标准差已接近 15 后，把建议值写入')
    print('     IQTest/Resources/ScoringCalibration.json，并更新 scoringVersion 字符串。')
    print('  2. 跑 python3 docs/run_diagnostics.py --update 重建基线。')
    print('  3. 跑完整单元测试与 UI 测试，确认换算改动没有破坏既有行为。')
    print('  4. 真实数据下做这一步之前，先用 items.csv 的初值做一次题目参数拟合；')
    print('     参数未拟合时，本次标定只是在当前参数下把刻度摆正，不是真正校准。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
