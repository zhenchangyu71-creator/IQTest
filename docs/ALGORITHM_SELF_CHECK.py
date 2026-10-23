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
        # 与 Swift 端同一套保守近似：3PL 的严格导数是 a(p-c)(1-p)/(1-c)，
        # 这里少除了 (1-c)，信息被低估、标准误被高估、区间偏宽。
        # 换成严格公式会让「领域差异显著」的判定明显变多，故暂不采用，
        # 详见 docs/WECHSLER_STYLE_SCORING.md 的「标准误与区间」。
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


def scaled_parameter(item_id, scale, difficulty_offset=0.0):
    """缩放区分度、平移难度，用于敏感性与误设代价分析。"""
    parameter = PARAMS[item_id]
    if scale == 1.0 and difficulty_offset == 0.0:
        return parameter
    return {'itemID': parameter['itemID'],
            'discrimination': parameter['discrimination'] * scale,
            'thresholds': [t + difficulty_offset for t in parameter['thresholds']]}


def simulate(theta, rng, discrimination_scale=1.0, difficulty_offset=0.0, per_subtest=0):
    """按题目参数为能力 theta 的被试生成一次作答。

    per_subtest > 0 时，每个分测验只随机取该数量的题作答，模拟真实一轮练习
    （每分测验 12 题）的施测情形；0 表示对全部题目作答——那是上界情形，
    用来检验斜率与参数是否自洽，不是使用者实际会遇到的输出。
    """
    responses = {}
    if per_subtest > 0:
        for sub in SUBTESTS:
            pool = [it for it in BANK if it['subtest'] == sub]
            for item in rng.sample(pool, per_subtest):
                p = prob(item, scaled_parameter(item['id'], discrimination_scale, difficulty_offset), theta)
                options = list(p.keys())
                weights = [p[o] for o in options]
                responses[item['id']] = rng.choices(options, weights=weights)[0]
        return responses
    # 默认路径保持原有的随机消耗顺序，既有基线才继续有效。
    for item in BANK:
        p = prob(item, scaled_parameter(item['id'], discrimination_scale, difficulty_offset), theta)
        options = list(p.keys())
        weights = [p[o] for o in options]
        responses[item['id']] = rng.choices(options, weights=weights)[0]
    return responses


def profile(responses, discrimination_scale=1.0):
    """与 Swift 端 WechslerProfileScorer 同一套流程。"""
    # 只纳入有作答的题目，便于分析不同题量下的表现。
    evidence = [(it, scaled_parameter(it['id'], discrimination_scale), responses[it['id']])
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


def theta_grid(count=21, half=2.5):
    """固定的能力网格：等距、关于 0 对称，缩放到实现标准差正好为 1。

    用固定网格代替随机抽样，去掉「抽到哪些 θ」带来的波动：
    60 个随机 θ 的实现标准差在 0.88–0.93 之间摆动，会让同一个量给出
    相差 5% 以上的离散度，而斜率改动带来的变化往往只有 2–4%。
    网格把能力这一维的噪声固定下来，剩下的只是题目抽样的抖动。
    """
    step = 2 * half / (count - 1)
    raw = [-half + step * i for i in range(count)]
    _, sd = mean_sd(raw)
    return [value / sd for value in raw]


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


def main():
    as_json = '--json' in sys.argv
    per_subtest = 0
    grid_repeats = 0
    positional = []
    skip_next = False
    for index, arg in enumerate(sys.argv[1:]):
        if skip_next:
            skip_next = False
            continue
        if arg == '--per-subtest' and index + 2 <= len(sys.argv):
            per_subtest = int(sys.argv[index + 2])
            skip_next = True
            continue
        if arg == '--grid' and index + 2 <= len(sys.argv):
            grid_repeats = int(sys.argv[index + 2])
            skip_next = True
            continue
        if arg.startswith('-'):
            continue
        positional.append(arg)
    count = int(positional[0]) if positional else 120
    rng = random.Random(20261022)

    if grid_repeats > 0:
        # 固定能力网格，每个能力点重复若干次后取平均：
        # 离散度只反映能力点之间的差异，不掺入同一能力下的抖动。
        results = []
        for theta in theta_grid():
            runs = [profile(simulate(theta, rng, per_subtest=per_subtest))
                    for _ in range(grid_repeats)]
            results.append((theta, {
                'theta_center': sum(r['theta_center'] for r in runs) / len(runs),
                'scaled': {sub: sum(r['scaled'][sub] for r in runs) / len(runs)
                           for sub in runs[0]['scaled']},
                'fsiq': sum(r['fsiq'] for r in runs) / len(runs),
                'indices': {dom: sum(r['indices'][dom] for r in runs) / len(runs)
                            for dom in runs[0]['indices']},
                'sum_scaled': sum(r['sum_scaled'] for r in runs) / len(runs),
            }))
    else:
        results = []
        for _ in range(count):
            theta = rng.gauss(0.0, 1.0)
            results.append((theta, profile(simulate(theta, rng, per_subtest=per_subtest))))

    true_thetas = [t for t, _ in results]
    centers = [p['theta_center'] for _, p in results]
    sums = [p['sum_scaled'] for _, p in results]
    fsiqs = [p['fsiq'] for _, p in results]
    _, sd_sum = mean_sd(sums)
    _, sd_fsiq = mean_sd(fsiqs)
    mean_center, sd_center = mean_sd(centers)
    _, sd_true = mean_sd(true_thetas)
    # 两个量回答不同问题，不能混用：
    #   reliability  估计值与真实能力的相关——衡量「测得准不准」
    #   attenuation  估计值离散度 / 真实离散度——衡量「换算刻度要还原多少」
    # 去衰减用后者：经验贝叶斯收缩把能力位置向中心压缩（这是设计如此，为了压噪），
    # 换算成量表分时需要把这个压缩还原回来。
    reliability = correlation(centers, true_thetas)
    attenuation = sd_center / sd_true if sd_true > 0 else float('inf')

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
        # 反推斜率前先把离散度归一化到「真实能力标准差为 1」的情形：
        # 尺度分之和的离散度正比于能力估计的离散度，样本里的能力离散度
        # 小于构造值时要按比例还原，否则斜率会被算小。
        domain_slope[dom] = 15 * sd_true / sd if sd > 0 else float('inf')
    suggested_full_scale_slope = 15 * sd_true / sd_sum if sd_sum > 0 else float('inf')

    if as_json:
        print(json.dumps({
            'subjects': count,
            'gridRepeats': grid_repeats,
            'perSubtest': per_subtest,
            'setting': 'admin' if per_subtest > 0 else 'all-items',
            'thetaTrueSD': round(sd_true, 4),
            'compositeSDRaw': round(sd_fsiq, 3),
            'compositeSD': round(sd_fsiq / sd_true, 3) if sd_true > 0 else None,
            'estimatedCenterMean': mean_center,
            'estimatedCenterSD': sd_center,
            'reliability': reliability,
            'attenuation': attenuation,
            'scaledScoreSD': 3 * sd_center,
            'scaledSumSD': round(sd_sum, 3),
            'scaledSumSDNormalized': round(sd_sum / sd_true, 3) if sd_true > 0 else None,
            'compositeMean': round(mean_sd(fsiqs)[0], 3),
            'targetCompositeSD': 15,
            'inCalibration': (13 <= sd_fsiq / sd_true <= 17) if sd_true > 0 else None,
            'domainScaledSumSD': domain_sd,
            'domainScaledSumSDNormalized': {dom: round(value / sd_true, 3)
                                            for dom, value in domain_sd.items()} if sd_true > 0 else None,
            'suggestedFullScaleSlope': round(suggested_full_scale_slope, 4),
            'suggestedIndexSlope': round(sum(domain_slope.values()) / len(domain_slope), 4),
            'suggestedIndexSlopeByDomain': {dom: round(value, 4) for dom, value in domain_slope.items()},
            'currentFullScaleSlope': FULL_SCALE_SLOPE,
            'currentIndexSlope': INDEX_SLOPE,
            'note': '合成数据来自模型自身，只验证算法与标定的自洽性，不构成对真实人群的效度证据。',
        }, ensure_ascii=False, indent=2))
        return

    if grid_repeats > 0:
        print(f'能力抽样：固定网格 21 点，每点 {grid_repeats} 次取平均'
              f'（网格的实现标准差为 1，无需再做归一化）')
    else:
        print(f'合成被试数：{count}（能力 θ ~ N(0,1)）')
    if per_subtest > 0:
        print(f'施测情形：每分测验 {per_subtest} 题，共 {per_subtest * len(SUBTESTS)} 题——真实一轮练习的情形')
        print('           下面的离散度是使用者实际会遇到的量。')
    else:
        print('施测情形：全部题目作答——这是上界，用来检验斜率与参数是否自洽，')
        print('           不是使用者实际会遇到的量（那要用 --per-subtest 12 复算）。')
    print()

    print('1) 能力参数还原')
    print(f'   真实 θ 的标准差            {sd_true:.3f}（按构造应为 1.000）')
    print(f'   估计中心的均值              {mean_center:+.3f}')
    print(f'   估计中心的标准差            {sd_center:.3f}（收缩会压窄，估计值应略小于 1）')
    print(f'   估计中心与真实 θ 的相关      {correlation(centers, true_thetas):.4f}（这才是可靠度）\n')

    # 有限样本里真实 θ 的实现标准差不会正好等于 1（抽样波动，120 个样本约 0.90），
    # 直接用样本标准差会把这份波动算进离散度。下面统一按 θ 的实现标准差归一化，
    # 得到的才是「真实人群能力标准差为 1 时」输出的离散度。
    norm = (lambda value: value / sd_true) if sd_true > 0 else (lambda value: float('nan'))

    print('2) 尺度分之和的离散度（斜率 0.72 的推导前提）')
    if grid_repeats > 0:
        print(f'   真实 θ 的标准差                {sd_true:.3f}（固定网格，构造值 1.000）')
    else:
        print(f'   真实 θ 的样本标准差            {sd_true:.3f}（构造值 1.000，有限样本的抽样波动）')
    print(f'   Σs 的标准差（原始）             {sd_sum:.2f}')
    print(f'   Σs 的标准差（归一化）           {norm(sd_sum):.2f}（韦氏手册对应约 20.8）')
    print(f'   若按 0.72 折算，合成分标准差     {FULL_SCALE_SLOPE * norm(sd_sum):.2f}（目标 15）\n')

    print('3) 合成分的分布')
    mean_fsiq, _ = mean_sd(fsiqs)
    print(f'   全量表分均值                   {mean_fsiq:.2f}（目标 100）')
    print(f'   全量表分标准差（原始）           {sd_fsiq:.2f}')
    print(f'   全量表分标准差（归一化）         {norm(sd_fsiq):.2f}（目标 15）')
    verdict = '一致' if 13 <= norm(sd_fsiq) <= 17 else '偏离目标，需重新标定斜率'
    print(f'   结论：{verdict}\n')

    print('4) 各领域指数分的离散度')
    for dom in ['verbal', 'perceptual', 'memory', 'speed']:
        print(f'   {dom:11s} Σs 标准差 {norm(domain_sd[dom]):6.2f}   折算出的指数分标准差 {INDEX_SLOPE * norm(domain_sd[dom]):6.2f}')

    print('\n5) 若改用本题库自己的数据标定（尚未实施的方案）')
    print(f'   能力估计的可靠性相关 r       {reliability:.3f}')
    print(f'   能力估计的离散度（相对真实值）  {attenuation:.3f}（收缩把位置向中心压）')
    print(f'   归一化后尺度分的实际标准差      {3 * norm(sd_center):.2f}（量表定义应为 3.00）')
    print(f'   归一化后 Σs（十个分测验）标准差 {norm(sd_sum):.2f}')
    print(f'   → 建议的全量表分斜率          {suggested_full_scale_slope:.3f}（当前借用 0.72）')
    for dom in ['verbal', 'perceptual', 'memory', 'speed']:
        print(f'   → {dom:11s} 指数分斜率 {domain_slope[dom]:.3f}（当前借用 2.75）')
    print(f'   → 指数分斜率建议取各域平均     {sum(domain_slope.values()) / len(domain_slope):.3f}')
    print('\n   注意：以上斜率来自合成被试，模型参数若有误，去衰减因子会被高估，')
    print('         导致过度放大。正式标定必须用真实样本重做。')

    print('\n提示：以上结论只说明「算法与当前题目参数自洽」。题目参数本身未经拟合，')
    print('      合成被试也来自同一模型，因此这里无法检验模型对真实人群的效度。')


if __name__ == '__main__':
    main()
