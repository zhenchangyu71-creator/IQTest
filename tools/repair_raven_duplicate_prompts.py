"""修掉瑞文题库中「去掉空白后完全相同」的重复题干。

起因：早期生成的一批图形规律题与后来生成的题是同一道题的两个副本——
序列相同、答案相同，只是问号前的空格数不同（一个空格 vs 两个空格）。
题库校验只去首尾空白，发现不了这种重复；于是同一轮抽题可能同时抽到
两道看起来一样的题，抽题轮换的意义被削弱。

修法：保留题号较新的那道，把较早的那道换成序列不同的新题
（沿用生成器「交替」规则的出题方式与选项构造），题干、选项、答案键、解析一并更新。

用法：
    python3 tools/repair_raven_duplicate_prompts.py            # 修复并写回
    python3 tools/repair_raven_duplicate_prompts.py --check    # 只报告，不写入
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_raven_items import PATTERN_SYMBOLS, ROOT  # noqa: E402


def normalized(prompt):
    return re.sub(r'\s+', '', prompt)


def rebuild(item, existing_prompts):
    """按「交替」规则给这道题出一道序列不同的新题；没有可行符号对则返回 None。"""
    for a in PATTERN_SYMBOLS:
        for b in PATTERN_SYMBOLS:
            if a == b:
                continue
            prompt = f'图形规律：{a} {b} {a} {b} {a}  ？'
            if normalized(prompt) in existing_prompts:
                continue
            options = [b] + [s for s in PATTERN_SYMBOLS if s != b][:3]
            return {
                'prompt': prompt,
                'options': options,
                'correctIndex': 0,
                'explanation': f'{a} 与 {b} 交替出现，{a} 之后应为 {b}。'
            }
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='只报告，不写入')
    args = parser.parse_args()

    path = os.path.join(ROOT, 'Questions.json')
    bank = json.load(open(path, encoding='utf-8'))

    seen = {}
    duplicates = []
    for item in bank:
        key = normalized(item['prompt'])
        if key in seen:
            duplicates.append((seen[key], item['id']))
        else:
            seen[key] = item['id']

    print(f'扫描 {len(bank)} 题，题干（去空白后）重复的有 {len(duplicates)} 组')
    for older, newer in duplicates:
        print(f'  id={older} 与 id={newer} 是同一道题')

    if args.check:
        return 1 if duplicates else 0

    index = {item['id']: item for item in bank}
    taken = {normalized(item['prompt']) for item in bank}
    for older, newer in duplicates:
        item = index[older]
        taken.discard(normalized(item['prompt']))
        rebuilt = rebuild(item, taken)
        if rebuilt is None:
            print(f'  id={older}：找不到可用的新序列，跳过')
            continue
        item['prompt'] = rebuilt['prompt']
        item['options'] = rebuilt['options']
        item['correctIndex'] = rebuilt['correctIndex']
        item['explanation'] = rebuilt['explanation']
        taken.add(normalized(item['prompt']))
        print(f"  id={older} 已换成 {item['prompt']!r}（答案 {item['options'][0]!r}）")

    if duplicates:
        with open(path, 'w', encoding='utf-8') as handle:
            json.dump(bank, handle, ensure_ascii=False, indent=2)
        print(f'\n已写回 {path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())