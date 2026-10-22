"""四套换算方案在同一批作答场景下的输出对比。

对比对象：

  旧单参数模型   100 + 15 × θ（θ 为全部项目的后验均值），项目重构前的输出方式
  早期收缩版     分测验向「总体能力」收缩。实现中发现的缺陷版本：
                 总体能力在聚合后比子测验平均更极端，会把领域差异抹平
  当前剖面       分测验各自独立估计 + 向「信息加权的中心」做经验贝叶斯收缩，
                 斜率借用自 Pearson 官方示例报告
  重新标定后     在当前剖面基础上对能力估计去衰减，并按本项目实测离散度重新标定斜率
                 （尚未实施，列出以展示标定的效果）

本脚本回答的问题是「几套方案在同一份作答上分别给出什么」，不是「哪一套更准」——
后者需要与正式量表的配对数据，本项目没有。

用法：python3 docs/ALGORITHM_COMPARISON.py
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ALGORITHM_SELF_CHECK as core  # noqa: E402

BANK = core.BANK
PARAMS = core.PARAMS
SUBTESTS = core.SUBTESTS
DOMAIN = core.DOMAIN
DOMAINS = ['verbal', 'perceptual', 'memory', 'speed']

# 借用值（当前生产代码使用）来自唯一真源；自检建议值尚未实施
CALIBRATION = core.CALIBRATION
BORROWED_INDEX_SLOPE = CALIBRATION['indexSlope']
BORROWED_FULL_SCALE_SLOPE = CALIBRATION['fullScaleSlope']
SUGGESTED_INDEX_SLOPE = 1.977
SUGGESTED_FULL_SCALE_SLOPE = 0.492
# 自检在 200 个合成被试上测得的可靠性相关
RELIABILITY = 0.761
ATTENUATION = 1 / RELIABILITY

COMPOSITE_RANGE = (CALIBRATION['compositeRangeLower'], CALIBRATION['compositeRangeUpper'])
LEGACY_SUBTEST_PRIOR_SD = 0.75
SHRINKAGE_SD = CALIBRATION['shrinkageSD']


def clamp(value):
    return max(COMPOSITE_RANGE[0], min(COMPOSITE_RANGE[1], value))


def scaled_of(theta):
    return min(19, max(1, round(10 + 3 * theta)))


def subtest_estimates(responses, mode):
    """返回 {分测验: (尺度分, 标准误)} 与总体能力 θ。"""
    evidence = [(it, PARAMS[it['id']], responses[it['id']]) for it in BANK]
    global_theta = core.posterior_mean(evidence)

    independent = []
    for sub in SUBTESTS:
        subset = [e for e in evidence if e[0]['subtest'] == sub]
        theta = core.posterior_mean(subset)
        error = core.standard_error([e[0] for e in subset], theta)
        independent.append((sub, theta, error))

    if mode == 'legacy_shrink':
        # 向总体能力收缩：这是实现过程中被否掉的版本。
        final = []
        for sub, theta, error in independent:
            subset = [e for e in evidence if e[0]['subtest'] == sub]
            shrunk = core.posterior_mean(subset, prior_mean=global_theta,
                                         prior_sd=LEGACY_SUBTEST_PRIOR_SD)
            final.append((sub, shrunk, error))
    else:
        # 信息加权的中心 + 经验贝叶斯收缩
        weights = [1 / max(error ** 2, 1e-6) for _, _, error in independent]
        total = sum(weights)
        center = sum(theta * w for (_, theta, _), w in zip(independent, weights)) / total
        center_weight = 1 / (SHRINKAGE_SD ** 2)
        final = []
        for (sub, theta, error), w in zip(independent, weights):
            shrunk = (w * theta + center_weight * center) / (w + center_weight)
            final.append((sub, shrunk, error))

    scaled = {sub: scaled_of(theta) for sub, theta, _ in final}
    errors = {sub: error for sub, _, error in final}
    return global_theta, scaled, errors


def composites(scaled, mode):
    """返回 (全量表分, {域: 指数分})。"""
    if mode == 'recalibrated':
        index_slope = SUGGESTED_INDEX_SLOPE * ATTENUATION
        full_scale_slope = SUGGESTED_FULL_SCALE_SLOPE * ATTENUATION
    else:
        index_slope = BORROWED_INDEX_SLOPE
        full_scale_slope = BORROWED_FULL_SCALE_SLOPE

    total = sum(scaled.values())
    fsiq = clamp(round(100 + full_scale_slope * (total - 10 * len(scaled))))
    indices = {}
    for domain in DOMAINS:
        members = [s for s in SUBTESTS if DOMAIN[s] == domain]
        sum_scaled = sum(scaled[s] for s in members)
        indices[domain] = clamp(round(100 + index_slope * (sum_scaled - 10 * len(members))))
    return fsiq, indices


def run(responses, mode):
    global_theta, scaled, _ = subtest_estimates(responses, mode)
    fsiq, indices = composites(scaled, mode)
    return {'legacy': round(100 + 15 * global_theta), 'profile': fsiq, 'indices': indices}


def scenarios():
    rng = random.Random(20261022)
    perfect = {it['id']: max(it['optionScores']) for it in BANK}
    wrong = {it['id']: 0 for it in BANK}
    random_answers = {it['id']: rng.choices(it['optionScores'],
                                            weights=[1.0 / len(it['optionScores'])] * len(it['optionScores']))[0]
                       for it in BANK}
    # 回忆题自由输入，乱答几乎必错，这里按实际作答行为构造。
    for it in BANK:
        if it.get('presentation') == 'digits':
            random_answers[it['id']] = 0
    eighty = {it['id']: (max(it['optionScores']) if i % 5 != 0 else 0)
              for i, it in enumerate(BANK)}
    half = {it['id']: (max(it['optionScores']) if i % 2 == 0 else 0)
            for i, it in enumerate(BANK)}
    skewed = {it['id']: (max(it['optionScores'])
                         if DOMAIN[it['subtest']] == 'verbal' else 0) for it in BANK}
    return [
        ('全部答对', perfect),
        ('约八成正确', eighty),
        ('约五成正确', half),
        ('随机作答', random_answers),
        ('全部答错', wrong),
        ('言语全对、其余全错', skewed),
    ]


def main():
    print('各方案在同一份作答上的输出（韦氏合成分的可用范围是 55–145）\n')
    header = f'{"场景":<20}{"旧单参数":>9}{"早期收缩版":>12}{"当前剖面":>10}{"重新标定后":>12}'
    print(header)
    print('-' * len(header.encode('utf-8').decode('utf-8')))

    for label, responses in scenarios():
        legacy_shrink = run(responses, 'legacy_shrink')
        current = run(responses, 'current')
        recalibrated = run(responses, 'recalibrated')
        global_theta, _, _ = subtest_estimates(responses, 'current')
        legacy = round(100 + 15 * global_theta)
        print(f'{label:<20}{legacy:>9}{legacy_shrink["profile"]:>12}'
              f'{current["profile"]:>10}{recalibrated["profile"]:>12}')

    print('\n\n各方案下的领域指数分（言语 / 知觉 / 记忆 / 速度）\n')
    for label, responses in scenarios():
        print(f'— {label}')
        for mode, name in (('legacy_shrink', '早期收缩版'), ('current', '当前剖面'), ('recalibrated', '重新标定后')):
            result = run(responses, mode)
            values = ' / '.join(f'{result["indices"][d]:>3}' for d in DOMAINS)
            print(f'    {name:<12} {values}')
        print()


if __name__ == '__main__':
    main()
