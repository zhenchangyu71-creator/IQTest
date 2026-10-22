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


def estimate_with(items_per_subtest, subjects):
    """每个分测验只取前 n 题，重新估计能力与合成分。"""
    centers, fsiqs = [], []
    for _theta, responses in subjects:
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
    _, sd_center = core.mean_sd(centers)
    mean_fsiq, sd_fsiq = core.mean_sd(fsiqs)
    return {
        'thetaSD': sd_center,
        'compositeMean': mean_fsiq,
        'compositeSD': sd_fsiq,
        # 合成被试的真实能力标准差为 1，可靠性相关即估计对真实的还原程度。
        'reliability': sd_center,
        # 换成「目标离散度为 15」时的估计标准误，用于横向比较不同题量的精度。
        'semAtTarget': 15.0 * math.sqrt(max(0.0, 1 - min(1.0, sd_center ** 2))),
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


if __name__ == '__main__':
    main()
