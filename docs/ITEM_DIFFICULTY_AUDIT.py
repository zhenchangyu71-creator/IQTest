"""题目难度诊断：按分测验报告预期得分率随能力的变化。

用途：把「题库整体偏难」这句观察变成可执行的复核清单——指出具体哪些分测验偏难或偏易，
以便逐题复核与难度调整。

诊断依据是模型参数文件里的启发式阈值，不是实测难度，因此结论受参数质量限制；
它的用途是指出「哪些分测验的参数与内容可能不匹配」，而不是给出真实难度。

用法：python3 docs/ITEM_DIFFICULTY_AUDIT.py
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ALGORITHM_SELF_CHECK as core  # noqa: E402

BANK = core.BANK
PARAMS = core.PARAMS
SUBTESTS = core.SUBTESTS
DOMAIN = core.DOMAIN

THETAS = [-1.0, 0.0, 1.0, 2.0]
# 韦氏各分测验在常模中位数附近的原始分大致占满分的这个比例。
# 用作参照：自编题库若明显低于它，说明中等水平使用者会被低估。
WECHSLER_TYPICAL_MEDIAN_RATIO = 0.50


def expected_score(item, theta):
    """该题在能力 theta 下的期望得分。"""
    probabilities = core.prob(item, PARAMS[item['id']], theta)
    return sum(score * p for score, p in probabilities.items())


def subtest_profile(subtest):
    items = [it for it in BANK if it['subtest'] == subtest]
    total_max = sum(max(it['optionScores']) for it in items)
    rows = []
    for theta in THETAS:
        earned = sum(expected_score(it, theta) for it in items)
        rows.append(earned / total_max)
    thresholds = [PARAMS[it['id']]['thresholds'][0] for it in items]
    return {
        'subtest': subtest,
        'domain': DOMAIN[subtest],
        'count': len(items),
        'maxScore': total_max,
        'meanThreshold': sum(thresholds) / len(thresholds),
        'rates': rows,
    }


def main():
    profiles = [subtest_profile(sub) for sub in SUBTESTS]
    print('各分测验在不同能力水平下的预期得分率\n')
    header = f'{"分测验":<14}{"域":<12}{"题数":>4}{"满分":>5}{"平均阈值":>9}  ' + \
            '  '.join(f'θ={t:+.0f}' for t in THETAS)
    print(header)
    print('-' * 78)
    for p in profiles:
        rates = '  '.join(f'{r * 100:5.1f}%' for r in p['rates'])
        print(f'{p["subtest"]:<14}{p["domain"]:<12}{p["count"]:>4}{p["maxScore"]:>5}'
              f'{p["meanThreshold"]:>9.2f}  {rates}')

    print('\n\n关键读数\n')
    at_zero = {p['subtest']: p['rates'][1] for p in profiles}
    overall = sum(p['rates'][1] * p['maxScore'] for p in profiles) / sum(p['maxScore'] for p in profiles)
    hardest = sorted(profiles, key=lambda p: p['rates'][1])[:3]
    easiest = sorted(profiles, key=lambda p: -p['rates'][1])[:3]
    print(f'   平均能力（θ=0）时题库整体预期得分率   {overall * 100:.1f}%')
    print(f'   韦氏常模中位数对应的原始分占比          约 {WECHSLER_TYPICAL_MEDIAN_RATIO * 100:.0f}%')
    gap = overall - WECHSLER_TYPICAL_MEDIAN_RATIO
    print(f'   差距                                    {gap * 100:+.1f} 个百分点')
    if gap > 0.10:
        print('   → 按当前参数，题库在「模型定义的平均能力」下比韦氏常模中位数容易得多：')
        print('     要被判为平均水平，使用者需要答对约 {:.0f}% 的题。'.format(overall * 100))
        print('     真实用户多数达不到这个比例，因此会被判为低于平均。')
        print('     根因在题目参数与真实难度的脱节（参数是启发式设定的），')
        print('     不在换算公式；修法是参数拟合与逐题难度复核。')
    print('\n   最难的三项：' + '、'.join(f'{p["subtest"]}（{p["rates"][1] * 100:.0f}%）' for p in hardest))
    print('   最易的三项：' + '、'.join(f'{p["subtest"]}（{p["rates"][1] * 100:.0f}%）' for p in easiest))

    # 同一能力下各分测验的得分率差得越开，剖面里的领域差异就越可能只是难度差异。
    spread = max(at_zero.values()) - min(at_zero.values())
    print(f'\n   θ=0 时各分测验得分率的极差            {spread * 100:.1f} 个百分点')
    print('   极差越大，说明不同分测验的难度越不齐，'
          '剖面中的「领域差异」越可能来自难度而非能力。')

    print('\n\nA/B 题组的参数一致性\n')
    model_a = json.load(open(os.path.join(core.ROOT, 'WechslerIQModel.json')))
    model_b = json.load(open(os.path.join(core.ROOT, 'WechslerIQModelB.json')))
    params_a = {p['itemID']: p for p in model_a['items']}
    params_b = {p['itemID']: p for p in model_b['items']}
    same, missing = 0, 0
    for item_id, pa in params_a.items():
        # B 组题号带 b- 前缀，按对应题号配对比较。
        pb = params_b.get('b-' + item_id)
        if pb is None:
            missing += 1
        elif pa['thresholds'] == pb['thresholds'] and pa['discrimination'] == pb['discrimination']:
            same += 1
    print(f'   A 组参数 {len(params_a)} 项，B 组 {len(params_b)} 项，无法配对的 {missing} 项')
    print(f'   按对应题号配对后，两组难度参数完全相同的有 {same} 项')
    print('   即 B 组直接沿用 A 组的难度参数，而两组题目内容不同——')
    print('   这意味着 B 组的「表面难度」被设成与 A 组一致。这不是题组等值的证据')
    print('   （等值需要真实数据），反而是需要重点复核的对象。')


if __name__ == '__main__':
    main()
