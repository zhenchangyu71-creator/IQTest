"""把历史导出转成题目参数拟合可用的数据集，并做数据质量检查。

参数拟合需要三张表：题目信息、被试信息、逐题作答。本脚本从应用导出的 JSON
（结果页或历史页的「导出 JSON」得到，格式见 docs/HISTORY_STORAGE.md）生成这三张表。

用法：
    python3 docs/calibration_export.py <导出的JSON路径> [输出目录]

输出（默认写到当前目录）：
    items.csv       题目：题号、分测验、域、满分、难度阈值、区分度、猜测率
    responses.csv   作答：被试、题号、得分、满分、状态、用时
    persons.csv     被试：日期、年龄、题组、原始分、完整度
    quality.txt     质量检查报告

拟合脚本需要的是 responses.csv 与 items.csv：前者给出每名被试在每道题上的得分，
后者给出每道题的参数初值与所属分测验。persons.csv 用来做分组与协变量分析。
"""
import csv
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ALGORITHM_SELF_CHECK as core  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'IQTest', 'Resources')
DOMAIN = {'similarities': 'verbal', 'vocabulary': 'verbal', 'information': 'verbal',
          'block': 'perceptual', 'matrix': 'perceptual', 'visualpuzzle': 'perceptual',
          'digitspan': 'memory', 'arithmetic': 'memory',
          'symbolsearch': 'speed', 'coding': 'speed'}


def load_model(path):
    model = json.load(open(path))
    return {p['itemID']: p for p in model['items']}, model.get('version', '')


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    source = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else '.'
    os.makedirs(out_dir, exist_ok=True)

    envelope = json.load(open(source))
    records = envelope.get('records', [])
    wechsler = [r for r in records if r.get('testType') == 'wechsler']
    if not wechsler:
        print('导出文件里没有韦氏记录，无法生成校准数据。')
        return 1

    params_a, version_a = load_model(os.path.join(ROOT, 'WechslerIQModel.json'))
    params_b, version_b = load_model(os.path.join(ROOT, 'WechslerIQModelB.json'))

    item_rows, response_rows, person_rows = [], [], []
    seen_items = set()
    missing_by_item = Counter()
    outcome_counts = Counter()
    question_sets = Counter()
    unmatched_parameters = Counter()

    for record in wechsler:
        responses = record.get('responses') or []
        if not responses:
            continue
        rid = record.get('id', '?')
        set_name = record.get('questionSet') or 'A'
        question_sets[set_name] += 1
        params = params_b if set_name.lower().startswith('b') else params_a

        answered = 0
        timed_out = 0
        interrupted = 0
        for response in responses:
            item_id = response.get('itemID', '')
            subtest = response.get('subtest', '')
            score = response.get('score', 0)
            max_score = response.get('maxScore', 0)
            outcome = response.get('outcome', 'answered')
            outcome_counts[outcome] += 1
            if outcome == 'answered':
                answered += 1
            elif outcome == 'timedOut':
                timed_out += 1
            else:
                interrupted += 1
            response_rows.append({
                'person_id': rid,
                'item_id': item_id,
                'subtest': subtest,
                'score': score,
                'max_score': max_score,
                'outcome': outcome,
                'elapsed_seconds': response.get('elapsedSeconds', ''),
                'question_set': set_name,
            })
            missing_by_item[item_id] += 0 if outcome == 'answered' else 1

            parameter = params.get(item_id) or params.get(item_id.replace('b-', ''))
            if parameter is None:
                unmatched_parameters[item_id] += 1
            if item_id not in seen_items:
                seen_items.add(item_id)
                thresholds = parameter['thresholds'] if parameter else []
                item_rows.append({
                    'item_id': item_id,
                    'subtest': subtest,
                    'domain': DOMAIN.get(subtest, ''),
                    'max_score': max_score,
                    'threshold_1': thresholds[0] if thresholds else '',
                    'threshold_2': thresholds[1] if len(thresholds) > 1 else '',
                    'discrimination': parameter['discrimination'] if parameter else '',
                    'question_set': set_name,
                })

        person_rows.append({
            'person_id': rid,
            'date': record.get('date', ''),
            'age': record.get('age', ''),
            'question_set': set_name,
            'raw_score': record.get('score', ''),
            'raw_max': record.get('total', ''),
            'completion': record.get('completion', ''),
            'items_answered': answered,
            'items_timed_out': timed_out,
            'items_interrupted': interrupted,
            'items_total': len(responses),
        })

    def write_csv(name, rows, fields):
        path = os.path.join(out_dir, name)
        with open(path, 'w', newline='', encoding='utf-8') as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        return path

    write_csv('items.csv', item_rows,
              ['item_id', 'subtest', 'domain', 'max_score', 'threshold_1', 'threshold_2',
               'discrimination', 'question_set'])
    write_csv('responses.csv', response_rows,
              ['person_id', 'item_id', 'subtest', 'score', 'max_score', 'outcome',
               'elapsed_seconds', 'question_set'])
    write_csv('persons.csv', person_rows,
              ['person_id', 'date', 'age', 'question_set', 'raw_score', 'raw_max',
               'completion', 'items_answered', 'items_timed_out', 'items_interrupted',
               'items_total'])

    # 各分测验在模型平均能力（θ=0）下的预期得分率，即难度基准。
    # 重新标定斜率时用它把原始分做难度归一，见 docs/calibrate_slopes.py。
    baseline_rows = []
    for subtest in core.SUBTESTS:
        items = [it for it in core.BANK if it['subtest'] == subtest]
        if not items:
            continue
        earned = 0.0
        max_total = 0
        for item in items:
            probabilities = core.prob(item, core.PARAMS[item['id']], 0.0)
            earned += sum(score * p for score, p in probabilities.items())
            max_total += max(item['optionScores'])
        baseline_rows.append({
            'subtest': subtest,
            'domain': DOMAIN.get(subtest, ''),
            'items': len(items),
            'max_score': max_total,
            'expected_rate_at_theta0': round(earned / max_total, 6) if max_total else 0,
        })
    write_csv('baselines.csv', baseline_rows,
              ['subtest', 'domain', 'items', 'max_score', 'expected_rate_at_theta0'])

    total_outcomes = sum(outcome_counts.values())
    report = [
        '参数拟合数据质量检查',
        f'来源：{source}',
        f'模型版本：A={version_a}  B={version_b}',
        '',
        f'被试数（韦氏记录）      {len(person_rows)}',
        f'题目数                  {len(item_rows)}',
        f'作答记录数              {len(response_rows)}',
        f'题组分布                {dict(question_sets)}',
        '',
        f'作答状态分布            {dict(outcome_counts)}',
    ]
    if total_outcomes:
        for outcome, count in outcome_counts.items():
            report.append(f'  {outcome:<12}{count:>8}  {count / total_outcomes * 100:5.1f}%')
    report.append('')

    incomplete = [p for p in person_rows if p['items_answered'] < p['items_total']]
    report.append(f'有超时或中断的记录      {len(incomplete)} / {len(person_rows)}')
    report.append('  拟合时这些项目应排除或单独建模，否则会把「没做完」当成「做错」。')

    if person_rows:
        ages = [p['age'] for p in person_rows if isinstance(p['age'], int)]
        if ages:
            report.append(f'年龄范围                {min(ages)}–{max(ages)} 岁（{len(ages)} 人有记录）')
        else:
            report.append('年龄                    全部缺失——无法做年龄分组或检查年龄效应')
    report.append('')

    if unmatched_parameters:
        report.append(f'未匹配到难度参数的题目      {len(unmatched_parameters)} 项')
        report.append('  这些题在 items.csv 中阈值列为空，拟合时缺少初值，需要单独处理：')
        for item in sorted(unmatched_parameters)[:10]:
            report.append(f'    {item}')
    else:
        report.append('全部题目都匹配到了难度参数。')

    report.append('')

    heavily_skipped = [(item, count) for item, count in missing_by_item.items() if count > 0]
    if heavily_skipped:
        report.append('有缺失（超时/中断）的题目：')
        for item, count in sorted(heavily_skipped, key=lambda row: -row[1])[:10]:
            report.append(f'  {item:<16}{count:>5} 次未计分')
    else:
        report.append('没有超时或中断的题目。')

    report.append('')
    report.append('下一步：')
    report.append('  1. 用 items.csv 的阈值作初值，responses.csv 的得分作观测，')
    report.append('     拟合每题的难度与区分度（项目分析与 IRT 标定）。')
    report.append('  2. 用 persons.csv 的作答完整度筛选样本，剔除未完成者或对其缺失单独建模。')
    report.append('  3. 用真实样本重新标定合成分斜率：')
    report.append('     python3 docs/calibrate_slopes.py <本目录>')
    report.append('  4. 标定完成后重跑 docs/ALGORITHM_SELF_CHECK.py 与')
    report.append('     docs/ITEM_DIFFICULTY_AUDIT.py，核对离散度与难度是否已符合预期。')

    report_path = os.path.join(out_dir, 'quality.txt')
    with open(report_path, 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(report) + '\n')

    print('\n'.join(report))
    print(f'\n已写入 {out_dir}/items.csv、responses.csv、persons.csv、quality.txt')
    return 0


if __name__ == '__main__':
    sys.exit(main())
