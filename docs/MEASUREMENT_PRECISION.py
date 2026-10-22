"""测量精度分析：单轮做多少题才够。

题库已经扩充（每分测验 24 题），那么单轮是该做 12 题还是更多？
这个脚本直接回答它：在同一批合成被试上，改变每个分测验的抽题数，
看能力估计的可靠性、全量表分的离散度与估计标准误怎么变。

固定随机种子，结果可复现。合成被试来自模型自身，因此结论只说明
「在当前题目参数下题量的边际收益」，不构成对真实人群的测量精度证据。

用法：
    python3 docs/MEASUREMENT_PRECISION.py [被试数]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ALGORITHM_SELF_CHECK as core  # noqa: E402

SUBJECTS = 40
# 每个分测验的抽题数。12 是当前的施测设计，其余用于比较边际收益。
ITEMS_PER_SUBTEST = [6, 8, 12, 16, 24]


def simulate_subjects(count):
    """按当前题库参数生成合成被试的完整作答。"""
    rng = random.Random(20261022)
    subjects = []
    for _ in range(count):
        theta = rng.gauss(0.0, 1.0)
        subjects.append((theta, core.simulate(theta, rng)))
    return subjects


def correlation(xs, ys):
    """皮尔逊相关系数。"""
    n = len(xs)
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    cov = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    var_x = sum((x - mean_x) ** 2 for x in xs)
    var_y = sum((y - mean_y) ** 2 for y in ys)
    if var_x <= 0 or var_y <= 0:
        return 0.0
    return cov / math.sqrt(var_x * var_y)


def estimate_with(items_per_subtest, subjects):
    """每个分测验只取前 n 题，重新估计能力与合成分。"""
    centers, fsiqs, truths = [], [], []
    for theta, responses in subjects:
        trimmed = {}
        used = {}
        for item in core.BANK:
            sub = item['subtest']
            taken = used.get(sub, 0)
            if taken < items_per_subtest:
                trimmed[item['id']] = responses[item['id']]
                used[sub] = taken + 1
        profile = core.profile(trimmed)
        centers.append(profile['theta_center'])
        fsiqs.append(profile['fsiq'])
        truths.append(theta)
    sd_center = core.mean_sd(centers)[1]
    mean_fsiq, sd_fsiq = core.mean_sd(fsiqs)
    # 可靠度必须用「与真实能力的相关」衡量。估计值的离散度不是可靠度：
    # 模型误设时离散度会被放大，用它衡量会得出「误设反而更准」的反直觉结论。
    reliability = correlation(centers, truths)
    return {
        'thetaSD': sd_center,
        'compositeMean': mean_fsiq,
        'compositeSD': sd_fsiq,
        'reliability': reliability,
        # 换成「目标离散度为 15」时的估计标准误，用于横向比较不同题量的精度。
        'semAtTarget': 15.0 * math.sqrt(max(0.0, 1 - min(1.0, reliability ** 2))),
    }


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else SUBJECTS
    subjects = simulate_subjects(count)
    total_items = len(core.SUBTESTS)

    print(f'合成被试 {count} 名，每轮每个分测验抽 n 题（当前施测设计为 12）\n')
    header = (f'{"每分测验":>8}{"总题量":>8}{"能力可靠度":>12}{"合成分离散度":>14}'
              f'{"折合标准误":>12}{"相对 12 题的 SEM":>16}')
    print(header)
    print('-' * 72)
    baseline = None
    for n in ITEMS_PER_SUBTEST:
        result = estimate_with(n, subjects)
        if baseline is None:
            baseline = result['semAtTarget']
        ratio = result['semAtTarget'] / baseline if baseline else 0
        print(f'{n:>8}{n * total_items:>8}{result["reliability"]:>12.3f}'
              f'{result["compositeSD"]:>14.2f}{result["semAtTarget"]:>12.2f}'
              f'{ratio:>15.2f}x')

    print('\n读法：')
    print('  · 能力可靠度是估计出的能力与真实能力的相关，越高说明题量越够。')
    print('  · 折合标准误把离散度归一到目标 15 分后的估计标准误，可横向比较。')
    print('  · 「相对 12 题的 SEM」小于 1 说明比当前设计更准。')
    print('\n注意：题目区分度全部为 1.0、题量也有限时，精度会很快见顶——')
    print('      继续加题的收益递减，此时提高题目质量比增加数量更有效。')

    discrimination_sensitivity(subjects)


def discrimination_sensitivity(subjects):
    """区分度提升能带来多少精度，以及模型误设要付多少代价。

    题目的区分度全为 1.0 是当前最大的精度瓶颈。这个分析回答两件事：
      1. 如果每题区分度更高，精度能到什么水平
      2. 如果题目实际区分度更高、但估计时仍用 1.0 的参数，精度损失多少
    """
    print('\n\n区分度敏感性（题池全用，24 题/分测验）\n')
    print(f'{"情境":<34}{"能力可靠度":>12}{"折合标准误":>12}')
    print('-' * 58)
    for scale in (1.0, 1.5, 2.0, 2.5):
        # 每个被试用不同随机序列，否则模拟出的不是不同的人。
        responses = [core.simulate(theta, random.Random(20261022 + index), discrimination_scale=scale)
                     for index, (theta, _) in enumerate(subjects)]
        matched = [core.profile(r, discrimination_scale=scale)['theta_center'] for r in responses]
        truths = [theta for theta, _ in subjects]
        reliability = correlation(matched, truths)
        sem = 15.0 * math.sqrt(max(0.0, 1 - min(1.0, reliability ** 2)))
        print(f'{"实际与估计的区分度同为 " + str(scale):<34}{reliability:>12.3f}{sem:>12.2f}')

    # 误设代价：题目实际的参数与估计时用的参数不一致
    truths = [theta for theta, _ in subjects]
    for label, sim_scale, sim_offset, est_scale in (
            ('实际区分度 2.0、估计按 1.0', 2.0, 0.0, 1.0),
            ('实际难度 +1.0、估计按原难度', 1.0, 1.0, 1.0)):
        responses = [core.simulate(theta, random.Random(20261022 + index),
                                   discrimination_scale=sim_scale, difficulty_offset=sim_offset)
                     for index, (theta, _) in enumerate(subjects)]
        mismatched = [core.profile(r, discrimination_scale=est_scale)['theta_center'] for r in responses]
        reliability = correlation(mismatched, truths)
        sem = 15.0 * math.sqrt(max(0.0, 1 - min(1.0, reliability ** 2)))
        print(f'{label:<34}{reliability:>12.3f}{sem:>12.2f}')
    print('\n读法：前四行是「参数与题目都正确」时区分度提高的收益；')
    print('      后两行是模型误设的代价——题目实际参数与估计用的参数不一致时损失多少。')


if __name__ == '__main__':
    main()
