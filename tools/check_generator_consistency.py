"""核对题库与生成器是否还对得上。

题库里的题是生成器产出的（题号连续、参数同源），所以两边应该能对上。
一旦对不上，通常意味着其中一方被单独改过：改了生成器没重生成题库，
或反过来改��题库没改生成器。前者会让下次跑生成器把修正覆盖回去，
后者会让生成器永远无法重现题库。

差异分两类：
  - 实质差异：题干、选项内容或解析不同——题目变了，必须同步。
  - 顺序差异：只有选项排列不同。作答时选项会被打乱（WechslerViewModel
    对 presentedOptions 做过 shuffle），所以顺序差异不影响任何行为，可以放过。

用法：
    python3 tools/check_generator_consistency.py          # 报告差异
    python3 tools/check_generator_consistency.py --strict # 顺序差异也算失败

退出码：0 无实质差异；1 有实质差异（--strict 下顺序差异也算）。
"""
import importlib.util
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, 'IQTest', 'Resources')
TOOLS = os.path.join(ROOT, 'tools')


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def substantive_difference(current, generated):
    """返回差异说明；没有实质差异返回 None。"""
    if current['prompt'] != generated['prompt']:
        return '题干不同'
    if current['explanation'] != generated['explanation']:
        return '解析不同'
    if sorted(current['options']) != sorted(generated['options']):
        return '选项内容不同'
    if current['optionScores'] != generated['optionScores']:
        return '选项分值不同'
    return None


def main():
    strict = '--strict' in sys.argv
    generator = load_module('gen_wechsler', os.path.join(TOOLS, 'generate_wechsler_items.py'))

    groups = (
        ('A', 'Wechsler.json', generator.SEED, ''),
        ('B', 'WechslerB.json', generator.SEED + 1, 'b-'),
    )
    # 扩充前的题库每分测验 24 题，生成器产出的接着往后排。
    baseline_per_subtest = 24

    substantive = []
    order_only = []
    checked = 0
    for group, bankfile, seed, prefix in groups:
        bank = {item['id']: item for item in json.load(open(os.path.join(RESOURCES, bankfile),
                                                             encoding='utf-8'))}
        generated = generator.build_for_group(group, seed)
        for subtest, items in generated.items():
            for index, item in enumerate(items, start=1):
                item_id = f'{prefix}{subtest}-{baseline_per_subtest + index:02d}'
                current = bank.get(item_id)
                if current is None:
                    substantive.append((item_id, '题库里没有这一题'))
                    continue
                checked += 1
                reason = substantive_difference(current, item)
                if reason:
                    substantive.append((item_id, reason))
                elif current['options'] != item['options']:
                    order_only.append(item_id)

    print(f'可比对 {checked} 题（题库中由生成器产出的部分）')
    print(f'  实质差异 {len(substantive)} 题')
    print(f'  仅选项顺序不同 {len(order_only)} 题（作答时会打乱，不影响行为）')
    if substantive:
        print('\n实质差异明细：')
        for item_id, reason in substantive:
            print(f'  {item_id}: {reason}')
    if order_only and strict:
        print('\n--strict：选项顺序差异也视为失败。')
        print('  ' + ' '.join(order_only[:20]))

    failed = bool(substantive) or (strict and bool(order_only))
    if failed:
        print('\n题库与生成器已经对不上。改了其中一方就要同步另一方，'
              '否则下次跑生成器会把修正覆盖回去。')
    else:
        print('\n题库与生成器一致。')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())