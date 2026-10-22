"""算法自检：用题目参数生成合成被试，检查换算链路的统计性质。

合成数据由模型自身生成，因此这项检查只能验证「算法实现与标定的自洽性」，
不能验证模型对真实人群的效度。它回答的问题是：

  1. 借用 Pearson 反推的斜率（指数分 2.75、全量表分 0.72），在本项目当前的
     题目参数下，是否真的让合成分的标准差落在 15 附近？
  2. 分测验的独立估计加经验贝叶斯收缩，会不会把能力分布压窄或拉偏？
  3. 由能力参数反推出的尺度分之和，其离散度是否与斜率的推导前提一致？

若第 1 项明显偏离 15，说明斜率与题目参数不再匹配，需要用自己的数据重新标定。

用法：python3 docs/ALGORITHM_SELF_CHECK.py
"""
import json
import math
import os
import random
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'IQTest', 'Resources')
MODEL = json.load(open(os.path.join(ROOT, 'WechslerIQModel.json')))
BANK = json.load(open(os.path.join(ROOT, 'Wechsler.json')))
PARAMS = {p['itemID']: p for p in MODEL['items']}
# 换算标定参数与 Swift 生产代码共用同一份文件，避免两处副本各改各的。
CALIBRATION = json.load(open(os.path.join(ROOT, 'ScoringCalibration.json')))

SUBTESTS = ['block', 'similarities', 'digitspan', 'matrix', 'vocabulary',
            'arithmetic', 'symbolsearch', 'visualpuzzle', 'information', 'coding']
DOMAIN = {'similarities': 'verbal', 'vocabulary': 'verbal', 'information': 'verbal',
          'block': 'perceptual', 'matrix': 'perceptual', 'visualpuzzle': 'perceptual',
          'digitspan': 'memory', 'arithmetic': 'memory',
          'symbolsearch': 'speed', 'coding': 'speed'}
SHRINKAGE_SD = CALIBRATION['shrinkageSD']
INDEX_SLOPE = CALIBRATION['indexSlope']
FULL_SCALE_SLOPE = CALIBRATION['fullScaleSlope']
COMPOSITE_RANGE = (CALIBRATION['compositeRangeLower'], CALIBRATION['compositeRangeUpper'])


def sigmoid(x):
    return 1 / (1 + math.exp(-x)) if x >= 0 else math.exp(x) / (1 + math.exp(x))


def normal_cdf(z):
    x = abs(z) * 0.7071067811865476
    t = 1.0 / (1.0 + 0.3275911 * x)
    poly = (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
    return 0.5 * (1 + (1 if z >= 0 else -1) * (1 - poly * math.exp(-x * x)))


def prob(item, param, theta):
    scores, n = item['optionScores'], len(item['optionScores'])
    recall = item.get('presentation') == 'digits'
    top = max(scores)
    c_full = 0.0 if recall else sum(1 for s in scores if s == top) / n
    a = param['discrimination']
    if len(param['thresholds']) == 2:
        c_any = 0.0 if recall else sum(1 for s in scores if s > 0) / n
        p_any = c_any + (1 - c_any) * sigmoid(a * (theta - param['thresholds'][0]))
        p_full = c_full + (1 - c_full) * sigmoid(a * (theta - param['thresholds'][1]))
        return {0: 1 - p_any, 1: p_any - p_full, 2: p_full}
    p_full = c_full + (1 - c_full) * sigmoid(a * (theta - param['thresholds'][0]))
    return {0: 1 - p_full, top: p_full}


def fisher(item, param, theta):
    scores, n = item['optionScores'], len(item['optionScores'])
    recall = item.get('presentation') == 'digits'
    top = max(scores)
    c_full = 0.0 if recall else sum(1 for s in scores if s == top) / n
    a = param['discrimination']

    def info(c, b):
        s = sigmoid(a * (theta - b))
        p = c + (1 - c) * s
        if not (0 < p < 1):
            return 0.0
        d = a * (p - c) * (1 - p)
        return d * d / (p * (1 - p))

    if len(param['thresholds']) == 2:
        c_any = 0.0 if recall else sum(1 for s in scores if s > 0) / n
        return info(c_any, param['thresholds'][0]) + info(c_full, param['thresholds'][1])
    return info(c_full, param['thresholds'][0])


def posterior_mean(evidence, step=0.05, prior_mean=None, prior_sd=None):
    """EAP。step 仅用于加速本自检脚本；生产代码使用 0.025。

    prior_mean / prior_sd 默认 N(0,1)；给出时改用该先验（网格随之平移，保持对称）。
    """
    pm = 0.0 if prior_mean is None else prior_mean
    ps = 1.0 if prior_sd is None else prior_sd
    for radius in (6.0, 10.0, 14.0, 18.0):
        steps = int(radius / step)
        grid = [pm - radius + i * step for i in range(2 * steps + 1)]
        # 网格必须关于先验均值对称，否则后验会被截断并产生系统性偏差。
        assert abs(grid[0] + grid[-1] - 2 * pm) < step, f'网格不对称：{grid[0]} .. {grid[-1]}'
        logs = []
        for theta in grid:
            lw = -((theta - pm) / ps) ** 2 / 2
            for item, param, score in evidence:
                lw += math.log(max(1e-14, prob(item, param, theta).get(score, 0.0)))
            logs.append(lw)
        peak = max(logs)
        weights = [math.exp(l - peak) for l in logs]
        total = sum(weights)
        edge = sum(w for t, w in zip(grid, weights) if abs(t - pm) >= radius - 0.5) / total
        if edge < 1e-8:
            return sum(t * w for t, w in zip(grid, weights)) / total
    raise RuntimeError('no convergence')


def standard_error(items, theta):
    info = sum(fisher(it, PARAMS[it['id']], theta) for it in items)
    return float('inf') if info <= 1e-9 else 1.0 / math.sqrt(info)


def simulate(theta, rng):
    """按题目参数为能力 theta 的被试生成一次作答。"""
    responses = {}
    for item in BANK:
        p = prob(item, PARAMS[item['id']], theta)
        options = list(p.keys())
        weights = [p[o] for o in options]
        responses[item['id']] = rng.choices(options, weights=weights)[0]
    return responses


def profile(responses):
    """与 Swift 端 WechslerProfileScorer 同一套流程。"""
    # 只纳入有作答的题目，便于分析不同题量下的表现。
    evidence = [(it, PARAMS[it['id']], responses[it['id']])
                for it in BANK if it['id'] in responses]
    indep = []
    for sub in SUBTESTS:
        subset = [e for e in evidence if e[0]['subtest'] == sub]
        theta = posterior_mean(subset)
        indep.append((sub, theta, standard_error([e[0] for e in subset], theta)))
    weights = [1 / max(se ** 2, 1e-6) for _, _, se in indep]
    total = sum(weights)
    center = sum(t * w for (_, t, _), w in zip(indep, weights)) / total
    center_weight = 1 / (SHRINKAGE_SD ** 2)
    scaled, errors = {}, {}
    for (sub, theta, se), w in zip(indep, weights):
        final = (w * theta + center_weight * center) / (w + center_weight)
        scaled[sub] = min(19, max(1, round(10 + 3 * final)))
        errors[sub] = se
    total_s = sum(scaled.values())
    fsiq = max(COMPOSITE_RANGE[0], min(COMPOSITE_RANGE[1],
                                      round(100 + FULL_SCALE_SLOPE * (total_s - 100))))
    indices = {}
    for dom in ['verbal', 'perceptual', 'memory', 'speed']:
        members = [s for s in SUBTESTS if DOMAIN[s] == dom]
        sum_s = sum(scaled[s] for s in members)
        score = max(COMPOSITE_RANGE[0], min(COMPOSITE_RANGE[1],
                                            round(100 + INDEX_SLOPE * (sum_s - 10 * len(members)))))
        indices[dom] = score
    return {'theta_center': center, 'scaled': scaled, 'fsiq': fsiq, 'indices': indices,
            'sum_scaled': total_s}


def mean_sd(values):
    n = len(values)
    m = sum(values) / n
    var = sum((v - m) ** 2 for v in values) / (n - 1)
    return m, math.sqrt(var)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    count = int(args[0]) if args else 120
    as_json = '--json' in sys.argv
    rng = random.Random(20261022)

    results = []
    for _ in range(count):
        theta = rng.gauss(0.0, 1.0)
        results.append((theta, profile(simulate(theta, rng))))

    true_thetas = [t for t, _ in results]
    centers = [p['theta_center'] for _, p in results]
    sums = [p['sum_scaled'] for _, p in results]
    fsiqs = [p['fsiq'] for _, p in results]
    _, sd_sum = mean_sd(sums)
    _, sd_fsiq = mean_sd(fsiqs)
    mean_center, sd_center = mean_sd(centers)
    _, sd_true = mean_sd(true_thetas)
    reliability = sd_center / sd_true
    attenuation = 1 / reliability if reliability > 0 else float('inf')

    domain_sums = {dom: [] for dom in ['verbal', 'perceptual', 'memory', 'speed']}
    for _, p in results:
        for dom in domain_sums:
            members = [s for s in SUBTESTS if DOMAIN[s] == dom]
            domain_sums[dom].append(sum(p['scaled'][s] for s in members))
    domain_sd = {}
    domain_slope = {}
    for dom, values in domain_sums.items():
        _, sd = mean_sd(values)
        domain_sd[dom] = sd
        domain_slope[dom] = 15 / (sd * attenuation)

    if as_json:
        print(json.dumps({
            'subjects': count,
            'thetaTrueSD': sd_true,
            'estimatedCenterMean': mean_center,
            'estimatedCenterSD': sd_center,
            'reliability': reliability,
            'attenuation': attenuation,
            'scaledScoreSD': 3 * sd_center,
            'scaledSumSD': sd_sum,
            'compositeMean': mean_sd(fsiqs)[0],
            'compositeSD': sd_fsiq,
            'targetCompositeSD': 15,
            'inCalibration': 13 <= sd_fsiq <= 17,
            'domainScaledSumSD': domain_sd,
            'suggestedFullScaleSlope': 15 / (sd_sum * attenuation),
            'suggestedIndexSlope': sum(domain_slope.values()) / len(domain_slope),
            'suggestedIndexSlopeByDomain': domain_slope,
            'currentFullScaleSlope': FULL_SCALE_SLOPE,
            'currentIndexSlope': INDEX_SLOPE,
            'note': '合成数据来自模型自身，只验证算法与标定的自洽性，不构成对真实人群的效度证据。',
        }, ensure_ascii=False, indent=2))
        return

    print(f'合成被试数：{count}（能力 θ ~ N(0,1)）\n')

    print('1) 能力参数还原')
    print(f'   真实 θ 的标准差            {sd_true:.3f}（按构造应为 1.000）')
    print(f'   估计中心的均值              {mean_center:+.3f}')
    print(f'   估计中心的标准差            {sd_center:.3f}（收缩会压窄，估计值应略小于 1）')
    corr = (sum((t - sum(true_thetas) / count) * (c - mean_center)
                 for t, c in zip(true_thetas, centers))
            / count) / (sd_true * sd_center)
    print(f'   估计中心与真实 θ 的相关      {corr:.4f}\n')

    print('2) 尺度分之和的离散度（斜率 0.72 的推导前提）')
    print(f'   Σs 的标准差                  {sd_sum:.2f}（韦氏手册对应约 20.8）')
    print(f'   若按 0.72 折算，合成分标准差  {FULL_SCALE_SLOPE * sd_sum:.2f}（目标 15）\n')

    print('3) 合成分的分布')
    mean_fsiq, _ = mean_sd(fsiqs)
    print(f'   全量表分均值                 {mean_fsiq:.2f}（目标 100）')
    print(f'   全量表分标准差               {sd_fsiq:.2f}（目标 15）')
    verdict = '一致' if 13 <= sd_fsiq <= 17 else '偏离目标，需重新标定斜率'
    print(f'   结论：{verdict}\n')

    print('4) 各领域指数分的离散度')
    for dom in ['verbal', 'perceptual', 'memory', 'speed']:
        print(f'   {dom:11s} Σs 标准差 {domain_sd[dom]:6.2f}   折算出的指数分标准差 {INDEX_SLOPE * domain_sd[dom]:6.2f}')

    print('\n5) 若改用本题库自己的数据标定（尚未实施的方案）')
    print(f'   能力估计的可靠性相关 r       {reliability:.3f}')
    print(f'   当前尺度分的实际标准差        {3 * sd_center:.2f}（量表定义应为 3.00）')
    print(f'   去衰减因子 1/r                {attenuation:.3f}')
    print(f'   去衰减后 Σs（十个分测验）标准差 {sd_sum * attenuation:.2f}')
    print(f'   → 建议的全量表分斜率         {15 / (sd_sum * attenuation):.3f}（当前借用 0.72）')
    for dom in ['verbal', 'perceptual', 'memory', 'speed']:
        print(f'   → {dom:11s} 指数分斜率 {domain_slope[dom]:.3f}（当前借用 2.75）')
    print(f'   → 指数分斜率建议取各域平均    {sum(domain_slope.values()) / len(domain_slope):.3f}')
    print('\n   注意：以上斜率来自合成被试，模型参数若有误，去衰减因子会被高估，')
    print('         导致过度放大。正式标定必须用真实样本重做。')

    print('\n提示：以上结论只说明「算法与当前题目参数自洽」。题目参数本身未经拟合，')
    print('      合成被试也来自同一模型，因此这里无法检验模型对真实人群的效度。')


if __name__ == '__main__':
    main()
