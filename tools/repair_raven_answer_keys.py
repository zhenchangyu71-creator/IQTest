"""修复瑞文题库中「答案键与解析不一致」的题目。

起因：生成器的「交替」规则把答案写成了序列的第一项，而解析说的是交替之后的
另一项。结果是正确答案被排除在选项之外——用户无论怎么选都答不对，
而题库的结构校验（重复题干、选项重复、答案索引越界）完全看不出来。

这个脚本从每道题的解析里读出真正的答案，然后修正选项与 correctIndex；
答案不在选项里时，把「序列里的另一个符号」换成正确答案——这正是修好的生成器
本该产出的样子。题干、解析与题号都不动，改动只落在选项与答案键上。

用法：
    python3 tools/repair_raven_answer_keys.py            # 修复并写回
    python3 tools/repair_raven_answer_keys.py --check    # 只报告，不写入
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_raven_items import ROOT, expected_answer  # noqa: E402

# 「交替」规则的解析里还有另一个符号——它才是被误当成答案的那个干扰项。
ALTERNATING = 'alternating'


def alternating_distractor(explanation):
    """交替规则里被误用的那个符号（序列的第一项），用它换取正确答案。"""
    import re
    match = re.search(r'(.)\s*与\s*(.)\s*交替出现', explanation)
    return match.group(1) if match else None


def repair(item):
    """返回 (说明, 是否需要改动)。"""
    expected = expected_answer(item)
    if expected is None:
        return None, False
    options = item['options']
    actual = options[item['correctIndex']]
    if actual == expected:
        return None, False
    if expected in options:
        item['correctIndex'] = options.index(expected)
        return f"答案键指向 {actual}，改为 {expected}", True
    # 正确答案不在选项里：把序列里的另一个符号换成正确答案。
    distractor = alternating_distractor(item['explanation'])
    if distractor is None or distractor not in options:
        return f"解析说应为 {expected}，但选项里没有，且无法安全替换", True
    item['options'] = [expected if o == distractor else o for o in options]
    item['correctIndex'] = item['options'].index(expected)
    return (f"正确答案 {expected} 不在选项里，已把干扰项 {distractor} 换成它，"
            f"correctIndex 改为 {item['correctIndex']}"), True


def main():
    args = sys.argv[1:]
    check_only = '--check' in args
    path = os.path.join(ROOT, 'Questions.json')
    bank = json.load(open(path, encoding='utf-8'))

    changes = []
    for item in bank:
        message, changed = repair(item)
        if changed:
            changes.append((item['id'], item['prompt'], message))

    print(f"扫描 {len(bank)} 题，发现 {len(changes)} 道题的答案键与解析不一致")
    for item_id, prompt, message in changes:
        print(f"  id={item_id} {prompt}\n      {message}")

    if check_only:
        return 1 if changes else 0

    if changes:
        with open(path, 'w', encoding='utf-8') as handle:
            json.dump(bank, handle, ensure_ascii=False, indent=2)
        print(f"\n已写回 {path}")
    return 0


if __name__ == '__main__':
    sys.exit(main())