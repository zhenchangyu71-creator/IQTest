"""从真实作答数据标定题目参数（难度与区分度）。

为什么需要它：当前所有题目的区分度都被设为 1.0，意味着每道题只区分「会不会」，
不区分「擅长到什么程度」。[精度分析](MEASUREMENT_PRECISION.py) 显示，即使把题池全部用上，
能力可靠度也只有 0.70、折合标准误 10.7 分（韦氏对应约 0.96 与 3.0）。
差距在题目质量，不在题目数量——而题目参数只能从真实数据里估出来。

方法：联合极大似然（JMLE）交替优化。
  1. 给定题目参数，用网格 + 局部细化估计每个被试的能力 θ（先验 N(0,1)）
  2. 给定 θ，先用 Rasch 式闭式解更新难度 b，再细化
  3. 给定 θ 与 b，用一维网格搜索更新区分度 a
  4. 迭代若干轮

部分得分题（0/1/2 分）按嵌套 Rasch 处理：「至少得 1 分」与「得满分」两层各自作为二分类项，
与生产代码 Fisher 信息的处理方式一致。

速度靠预计算概率表：同一道题对所有被试、同一 θ 网格的概率只算一次，
之后所有似然评估都是查表与取对数。

用法：
    python3 docs/fit_item_parameters.py <calibration_export 产出的目录> [选项]

    --rounds N     迭代轮数（默认 4）
    --out 文件      标定结果写出的 JSON（默认只打印摘要）
    --synthetic N  不读真实数据，改用 N 个合成被试跑同一流程（真值已知，用于检验脚本本身）
    --perturb       标定前把题目参数随机扰动，用来检验能否收敛回真值

退出码：0 成功；1 输入有误。
"""
import argparse
import csv
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ALGORITHM_SELF_CHECK as core  # noqa: E402

THETA_GRID = [-4.0 + 0.05 * i for i in range(161)]   # 161 点，覆盖 ±4
B_STEP = 0.05
B_RANGE = 2.0                                         # b 在当前值 ±2.0 内搜索
A_GRID = [0.3 + 0.15 * i for i in range(15)]          # 0.3 ~ 2.4
SIGMA_PRIOR = 1.0                                       # 能力先验 N(0,1)


def sigmoid(x):
    return 1.0 / (1.0 + math.exp(-x)) if x >= 0 else math.exp(x) / (1.0 + math.exp(x))


def item_layers(item):
    """把一道题拆成若干二分类层。

    普通题是一层；部分得分题是「至少得 1 分」与「得满分」两层。
    返回 (层列表, 每层满分时的分值)。
    """
    scores = item['optionScores']
    top = max(scores)
    recall = item.get('presentation') == 'digits'
    options = len(scores)
    guess_any = 0.0 if recall else sum(1 for s in scores if s > 0) / options
    guess_full = 0.0 if recall else sum(1 for s in scores if s == top) / options
    if top == 2 and 1 in scores:
        return [(guess_any, 1.0), (guess_full, 1.0)], 2
    return [(guess_full, 1.0)], top


def layer_probability(guessing, threshold, discrimination, theta):
    return guessing + (1 - guessing) * sigmoid(discrimination * (theta - threshold))


def load_bank_layers():
    """从题库 JSON 读出每题的分值结构与猜测率。"""
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'IQTest', 'Resources')
    bank = json.load(open(os.path.join(root, 'Wechsler.json'), encoding='utf-8'))
    out = {}
    for item in bank:
        scores = item['optionScores']
        top = max(scores)
        recall = item.get('presentation') == 'digits'
        options = len(scores)
        guess_any = 0.0 if recall else sum(1 for s in scores if s > 0) / options
        guess_full = 0.0 if recall else sum(1 for s in scores if s == top) / options
        if top == 2 and 1 in scores:
            layers = [(guess_any, 1), (guess_full, 1)]
        else:
            layers = [(guess_full, 1)]
        out[item['id']] = {'layers': layers}
    return out


def response_vectors(csv_rows, item_ids, layers_by_id):
    """每个被试对每道题的实际得分（按层拆分的 0/1 观测）。

    层数必须按题库的实际结构判断，不能看「满分是否为 2 分」——
    常识题是纯两分制（满分 2 分但没有 1 分选项），只有一层。
    """
    persons = {}
    for row in csv_rows:
        pid = row['person_id']
        item_id = row['item_id']
        if item_id not in item_ids:
            continue
        score = int(row['score'])
        if len(layers_by_id.get(item_id, {}).get('layers', [(0, 1)])) > 1:
            # 部分得分题：拆成「至少 1 分」与「得满分」两层
            persons.setdefault(pid, {})[item_id] = (1 if score >= 1 else 0, 1 if score == 2 else 0)
        else:
            persons.setdefault(pid, {})[item_id] = (1 if score >= 1 else 0,)
    return persons


def estimate_theta(observations, item_table, item_index):
    """给定题目参数，用网格 + 局部细化估计能力 θ。"""
    best = (None, -1e18)
    for theta in THETA_GRID:
        log_lik = 0.0
        for item_id, observed in observations.items():
            entry = item_table[item_id]
            for layer_index, outcome in enumerate(observed):
                threshold = entry['thresholds'][min(layer_index, len(entry['thresholds']) - 1)]
                guessing = entry['layers'][layer_index][0]
                p = layer_probability(guessing, threshold, entry['discrimination'], theta)
                p = min(max(p, 1e-9), 1 - 1e-9)
                log_lik += math.log(p) if outcome else math.log(1 - p)
        log_lik -= theta * theta / (2 * SIGMA_PRIOR * SIGMA_PRIOR)
        if log_lik > best[1]:
            best = (theta, log_lik)
    return best[0]


def update_item_parameters(item_table, persons, rounds):
    """交替优化：先更新 θ，再更新 b 与 a。"""
    thetas = {pid: 0.0 for pid in persons}
    for _round in range(rounds):
        # 1) 更新被试能力
        for pid, observations in persons.items():
            thetas[pid] = estimate_theta(observations, item_table, None)
        # 2) 更新题目难度与区分度
        for item_id, entry in item_table.items():
            # obs 必须取该被试在这道题上的观测，而不是该被试的整张作答表。
            observers = [(pid, obs[item_id]) for pid, obs in persons.items() if item_id in obs]
            if not observers:
                continue
            entry['thresholds'] = _refine_threshold(entry, observers, thetas)
            entry['discrimination'] = _refine_discrimination(entry, observers, thetas)
    return thetas


def _log_likelihood(entry, threshold, discrimination, observers, thetas):
    total = 0.0
    for pid, observed in observers:
        theta = thetas[pid]
        for layer_index, outcome in enumerate(observed):
            guessing = entry['layers'][layer_index][0]
            p = layer_probability(guessing, threshold, discrimination, theta)
            p = min(max(p, 1e-9), 1 - 1e-9)
            total += math.log(p) if outcome else math.log(1 - p)
    return total


def _refine_threshold(entry, observers, thetas):
    """在当前阈值附近搜索最优 b。"""
    base = entry['thresholds'][0]
    best = (base, -1e18)
    steps = int(B_RANGE / B_STEP)
    for step in range(-steps, steps + 1):
        candidate = round(base + step * B_STEP, 4)
        value = _log_likelihood(entry, candidate, entry['discrimination'], observers, thetas)
        if value > best[1]:
            best = (candidate, value)
    # 多层题目逐层更新，第二层跟随第一层的偏移
    if len(entry['thresholds']) > 1:
        gap = entry['thresholds'][1] - entry['thresholds'][0]
        return [best[0], round(best[0] + gap, 4)]
    return [best[0]]


def _refine_discrimination(entry, observers, thetas):
    best = (entry['discrimination'], -1e18)
    for candidate in A_GRID:
        value = _log_likelihood(entry, entry['thresholds'][0], candidate, observers, thetas)
        if value > best[1]:
            best = (candidate, value)
    return best[0]


def summarize(table, truth=None):
    print('\n标定结果摘要')
    by_subtest = {}
    for item_id, entry in table.items():
        by_subtest.setdefault(entry['subtest'], []).append(entry)
    print(f'{"分测验":<14}{"题数":>5}{"区分度均值":>13}{"区分度范围":>18}{"难度范围":>18}')
    for subtest in sorted(by_subtest):
        entries = by_subtest[subtest]
        discriminations = [e['discrimination'] for e in entries]
        difficulties = [e['thresholds'][0] for e in entries]
        print(f'{subtest:<14}{len(entries):>5}'
              f'{sum(discriminations) / len(discriminations):>13.2f}'
              f'{min(discriminations):>8.2f}–{max(discriminations):<9.2f}'
              f'{min(difficulties):>8.2f}–{max(difficulties):<9.2f}')
    if truth:
        errors = []
        for item_id, entry in table.items():
            true_entry = truth.get(item_id)
            if not true_entry:
                continue
            errors.append(abs(entry['thresholds'][0] - true_entry['thresholds'][0]))
        if errors:
            print(f'\n与真值的难度绝对误差：均值 {sum(errors) / len(errors):.3f}'
                  f'，最大 {max(errors):.3f}')



def run_study(counts, rounds):
    """样本量研究：标定 240 题的 (a, b) 需要多少被试。

    合成被试真值已知，因此可以直接量出标定误差随样本量的变化。
    被试是嵌套的：前 N 个被试与前 M 个（M<N）完全相同，因此不同样本量的结果可比。
    """
    rng = random.Random(20261022)
    truth = {item_id: {'thresholds': list(entry['thresholds']),
                     'discrimination': entry['discrimination']}
             for item_id, entry in core.PARAMS.items()}
    subjects = []
    for _ in range(max(counts)):
        theta = rng.gauss(0.0, 1.0)
        subjects.append(core.simulate(theta, rng))

    bank_layers = load_bank_layers()
    print(f'{"被试数":>8}{"难度误差":>12}{"难度最大误差":>14}{"区分度误差":>13}{"撞边界的题":>12}')
    print('-' * 60)
    for count in counts:
        people = {}
        for index in range(count):
            responses = subjects[index]
            people[f's{index:04d}'] = {
                item_id: (1 if score >= 1 else 0,) +
                ((1 if score == 2 else 0,) if len(bank_layers[item_id]['layers']) > 1 else ())
                for item_id, score in responses.items()}
        table = {}
        for item_id in people[f's{index:04d}']:
            table[item_id] = {'subtest': item_id.rsplit('-', 1)[0],
                              'thresholds': list(core.PARAMS[item_id]['thresholds']),
                              'discrimination': core.PARAMS[item_id]['discrimination'],
                              'layers': bank_layers[item_id]['layers']}
        update_item_parameters(table, people, rounds)
        difficulty_errors, discrimination_errors, at_boundary = [], [], 0
        for item_id, entry in table.items():
            true_entry = truth[item_id]
            difficulty_errors.append(abs(entry['thresholds'][0] - true_entry['thresholds'][0]))
            discrimination_errors.append(abs(entry['discrimination'] - true_entry['discrimination']))
            if entry['discrimination'] in (A_GRID[0], A_GRID[-1]):
                at_boundary += 1
        print(f'{count:>8}{sum(difficulty_errors) / len(difficulty_errors):>12.3f}'
              f'{max(difficulty_errors):>14.3f}'
              f'{sum(discrimination_errors) / len(discrimination_errors):>13.3f}'
              f'{at_boundary:>12}')

    print('\n读法：难度误差是标定难度与真值的平均绝对差；区分度误差同理。')
    print('      「撞边界的题」指区分度被推到搜索区间端点的题目数——')
    print('      题目越多而样本越少，区分度就越不可辨识（区分度与难度互相补偿）。')
    print('      这一列比误差更早暴露「样本不够」：撞边界的题越多，标定结果越不可信。')


def main():
    parser = argparse.ArgumentParser(description='从真实作答数据标定题目参数')
    parser.add_argument('directory', nargs='?', help='calibration_export 产出的目录')
    parser.add_argument('--rounds', type=int, default=4)
    parser.add_argument('--out')
    parser.add_argument('--synthetic', type=int)
    parser.add_argument('--perturb', action='store_true')
    parser.add_argument('--study', help='逗号分隔的样本量列表，做样本量研究')
    args = parser.parse_args()

    params_by_id = {p['itemID']: p for p in core.PARAMS.values()}
    bank_layers = load_bank_layers()

    if args.study:
        counts = [int(x) for x in args.study.split(',')]
        print(f'样本量研究（{args.rounds} 轮迭代）\n')
        run_study(counts, args.rounds)
        return 0

    if args.synthetic is not None:
        count = args.synthetic
        rng = random.Random(20261022)
        persons = {}
        truth = {item_id: {'thresholds': list(entry['thresholds']),
                           'discrimination': entry['discrimination']}
                 for item_id, entry in core.PARAMS.items()}
        for index in range(count):
            theta = rng.gauss(0.0, 1.0)
            responses = core.simulate(theta, rng)
            pid = f's{index:04d}'
            persons[pid] = {item_id: (1 if score >= 1 else 0,) +
                            ((1 if score == 2 else 0,) if len(bank_layers[item_id]['layers']) > 1 else ())
                            for item_id, score in responses.items()}
        print(f'使用 {count} 个合成被试（真值已知）')
    else:
        if not args.directory:
            parser.print_help()
            return 1
        responses_path = os.path.join(args.directory, 'responses.csv')
        items_path = os.path.join(args.directory, 'items.csv')
        if not os.path.exists(responses_path):
            print('缺少 responses.csv，请先运行 calibration_export.py')
            return 1
        with open(responses_path, newline='', encoding='utf-8') as handle:
            response_rows = list(csv.DictReader(handle))
        with open(items_path, newline='', encoding='utf-8') as handle:
            item_rows = list(csv.DictReader(handle))
        item_ids = {row['item_id'] for row in item_rows}
        persons = response_vectors(response_rows, item_ids, bank_layers)
        truth = None
        print(f'使用真实作答：{len(persons)} 名被试，{len(item_ids)} 道题')

    table = {}
    for item_id in persons[next(iter(persons))]:
        entry = core.PARAMS[item_id]
        table[item_id] = {'subtest': item_id.rsplit('-', 1)[0],
                          'thresholds': list(entry['thresholds']),
                          'discrimination': entry['discrimination'],
                          'layers': bank_layers[item_id]['layers']}
    if args.perturb:
        rng = random.Random(7)
        for entry in table.values():
            entry['thresholds'] = [round(t + rng.uniform(-1.5, 1.5), 4) for t in entry['thresholds']]
            entry['discrimination'] = round(rng.uniform(0.4, 2.0), 3)
        print('起点已随机扰动，用于检验收敛性')

    print(f'标定中（{args.rounds} 轮）…')
    thetas = update_item_parameters(table, persons, args.rounds)
    summarize(table, truth if args.synthetic else None)

    if args.out:
        payload = {
            'version': 'irt-calibrated-v1',
            'bankVersion': core.CALIBRATION.get('bankVersion', ''),
            'subjects': len(persons),
            'items': [{'itemID': item_id,
                       'discrimination': round(entry['discrimination'], 4),
                       'thresholds': [round(t, 4) for t in entry['thresholds']]}
                      for item_id, entry in sorted(table.items())],
        }
        with open(args.out, 'w', encoding='utf-8') as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write('\n')
        print(f'\n已写出 {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
