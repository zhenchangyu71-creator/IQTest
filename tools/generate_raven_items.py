"""生成瑞文推理题库的扩充题目。

扩充题库的直接原因：题池有限时，多次测试会反复遇到同样的题目——
既让复测分数混入练习效应（看过解析再遇到，分数必然虚高），也让多次测量失去意义。
配套的抽题轮换机制优先选没做过的题，题库越大，能维持不重复的轮次越多。

四种题型都按规则生成，答案由规则本身保证正确：
  number   数列：等差、递增差、交替、平方、倍数
  pattern  符号模式：交替、循环、成组、数量递增
  verbal   类比：种属、对象与用途、反义、部分与整体
  logic    逻辑：排序链、全称命题、逆否推理、排除

用法：
    python3 tools/generate_raven_items.py            # 生成并追加到题库
    python3 tools/generate_raven_items.py --check    # 只校验，不写入

固定随机种子，重复运行得到同样的题库。
"""
import argparse
import json
import os
import random
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'IQTest', 'Resources')
SEED = 20261022
PER_COMBINATION = 12

PATTERN_SYMBOLS = ['●', '○', '◆', '◇', '▲', '△', '★', '☆', '■', '□']

# 每种 pattern 出题规则的「解析里哪个符号才是答案」。
# 格式：(正则, 答案所在的捕获组, 从该捕获组到实际选项的变换)。
PATTERN_ANSWER_RULES = [
    (re.compile(r'(.)\s*与\s*(.)\s*交替出现，\1\s*之后应为\s*(.)'), 3, lambda s: s),
    (re.compile(r'以\s*(.)\s*(.)\s*(.)\s*为一组循环，第三组第三位应为\s*(.)'), 4, lambda s: s),
    (re.compile(r'以\s*(.)\s*(.)\s*(.)\s*(.)\s*为一组循环，第二组第二位应为\s*(.)'), 5, lambda s: s),
    (re.compile(r'以\s*(.)\s*(.)\s*(.)\s*为一组循环，第三组第二位应为\s*(.)'), 4, lambda s: s),
    (re.compile(r'(.)\s*(.)\s*(.)\s*(.)\s*之后回到\s*(.)'), 5, lambda s: s),
    (re.compile(r'符号数量依次递增，第四组应有 4 个\s*(.)'), 1, lambda s: s * 4),
]


def expected_answer(item):
    """从解析里取出这道题真正的答案；不是 pattern 类题目则返回 None。"""
    for pattern, group, transform in PATTERN_ANSWER_RULES:
        match = pattern.search(item.get('explanation', ''))
        if match:
            return transform(match.group(group))
    return None


def check_answer_key(item):
    """答案键必须与解析给出的答案一致。

    这一条曾真的错过：「交替」分支把答案写成了序列的第一项，
    而解析说的是交替之后的另一项，于是正确答案被排除在选项之外——
    用户无论怎么选都答不对，而题库校验（结构校验）完全看不出来。
    """
    expected = expected_answer(item)
    if expected is None:
        return
    actual = item['options'][item['correctIndex']]
    assert actual == expected, (
        f"答案键与解析不一致：{item['prompt']} 解析说应为 {expected}，"
        f"但 correctIndex 指向 {actual}")


def make_item(category, difficulty, prompt, options, correct_index, explanation, next_id):
    assert 0 <= correct_index < len(options)
    assert len(set(options)) == len(options), f'选项重复：{prompt}'
    return {'id': next_id, 'category': category, 'difficulty': difficulty,
            'prompt': prompt, 'options': list(options), 'correctIndex': correct_index,
            'explanation': explanation}


def numeric_distractors(rng, answer, count=3):
    """给数值答案生成邻近且互不相同的干扰项。

    干扰项必须分布在答案两侧：若全在同侧，「答案总是最小（或最大）」就成了
    可被模式猜中的破绽，题目便不再测推理。
    """
    wrong = []
    lower = [answer - d for d in range(1, 20) if answer - d >= 0]
    upper = [answer + d for d in range(1, 20)]
    if lower:
        wrong.append(rng.choice(lower[:8]))
    if upper:
        wrong.append(rng.choice(upper[:8]))
    pool = lower[8:] + upper[8:] + [answer + d for d in range(20, 40)]
    rng.shuffle(pool)
    for candidate in pool:
        if len(wrong) >= count:
            break
        if candidate != answer and candidate not in wrong:
            wrong.append(candidate)
    while len(wrong) < count:
        wrong.append(answer + len(wrong) + 1)
    return wrong[:count]


# ---------------------------------------------------------------- number

def gen_number(rng, difficulty, count, start_id):
    items = []
    styles = {
        'easy': ['等差', '倍数'],
        'medium': ['等差', '递增差', '倍数'],
        'hard': ['交替', '平方', '递增差'],
    }[difficulty]
    for index in range(count):
        style = styles[index % len(styles)]
        if style == '等差':
            start = rng.randint(1, 20)
            step = rng.randint(2, 6)
            length = 5
            series = [start + step * i for i in range(length)]
            answer = series[-1] + step
            explanation = f'公差为 {step} 的等差数列，{series[-1]} + {step} = {answer}。'
        elif style == '倍数':
            start = rng.randint(1, 6)
            factor = rng.choice([2, 3])
            series = [start * factor ** i for i in range(5)]
            answer = series[-1] * factor
            explanation = f'每一项是前一项的 {factor} 倍，{series[-1]} × {factor} = {answer}。'
        elif style == '递增差':
            start = rng.randint(1, 12)
            step = rng.randint(2, 4)
            series = [start]
            for i in range(4):
                series.append(series[-1] + step + i)
            answer = series[-1] + step + 4
            explanation = (f'相邻差依次为 {step}、{step + 1}、{step + 2}、{step + 3}，'
                           f'下一差为 {step + 4}，{series[-1]} + {step + 4} = {answer}。')
        elif style == '交替':
            a = rng.randint(1, 9)
            b = rng.randint(10, 25)
            series = []
            for i in range(6):
                series.append(a if i % 2 == 0 else b)
            answer = a
            explanation = f'奇数位都是 {a}、偶数位都是 {b}，下一项（第七项）应为 {a}。'
        else:  # 平方
            base = rng.randint(2, 5)
            series = [base ** i for i in range(1, 5)]
            answer = base ** 5
            explanation = f'依次是 {base} 的 1、2、3、4 次方，下一项是 {base} 的 5 次方 = {answer}。'
        options = [str(answer)] + [str(x) for x in numeric_distractors(rng, answer)]
        rng.shuffle(options)
        prompt = f'数列：{"，".join(str(x) for x in series)}，？'
        items.append(make_item('number', difficulty, prompt, options,
                               options.index(str(answer)), explanation, start_id + index))
    return items


# ---------------------------------------------------------------- pattern

def gen_pattern(rng, difficulty, count, start_id):
    items = []
    styles = {
        'easy': ['交替', '数量递增'],
        'medium': ['交替', '三循环', '成组', '数量递增'],
        'hard': ['四循环', '三循环', '成组', '位移'],
    }[difficulty]
    for index in range(count):
        style = styles[index % len(styles)]
        if style == '交替':
            a, b = rng.sample(PATTERN_SYMBOLS, 2)
            series = [a if i % 2 == 0 else b for i in range(6)]
            # 序列是 a b a b a b，问号是第六项，交替后应为 b 而不是 a。
            answer = b
            explanation = f'{a} 与 {b} 交替出现，{a} 之后应为 {b}。'
            series = series[:5]
        elif style == '三循环':
            a, b, c = rng.sample(PATTERN_SYMBOLS, 3)
            series = [a, b, c, a, b]
            answer = c
            explanation = f'以 {a} {b} {c} 为一组循环，第三组第三位应为 {c}。'
        elif style == '四循环':
            a, b, c, d = rng.sample(PATTERN_SYMBOLS, 4)
            series = [a, b, c, d, a]
            answer = b
            explanation = f'以 {a} {b} {c} {d} 为一组循环，第二组第二位应为 {b}。'
        elif style == '成组':
            a, b = rng.sample(PATTERN_SYMBOLS, 2)
            series = [a, a, b, a, a]
            answer = b
            explanation = f'以 {a} {a} {b} 为一组循环，第三组第二位应为 {b}。'
        elif style == '位移':
            a, b, c = rng.sample(PATTERN_SYMBOLS, 3)
            series = [a, b, c, b]
            answer = a
            explanation = f'{a} {b} {c} {b} 之后回到 {a}，呈对称排列。'
        else:  # 数量递增
            a = rng.choice(PATTERN_SYMBOLS)
            series = [a, a * 2, a * 3]
            answer = a * 4
            explanation = f'符号数量依次递增，第四组应有 4 个 {a}。'
        options = [answer] + [s for s in PATTERN_SYMBOLS if s != answer][:3]
        rng.shuffle(options)
        prompt = f'图形规律：{" ".join(series)}  ？'
        items.append(make_item('pattern', difficulty, prompt, options,
                               options.index(answer), explanation, start_id + index))
    return items


# ---------------------------------------------------------------- verbal

VERBAL_BANK = {
    'easy': [
        ('种属', [('猫', '动物'), ('玫瑰', '植物'), ('鲸鱼', '哺乳动物'),
                   ('青蛙', '两栖动物'), ('橡树', '树木'), ('蜜蜂', '昆虫'),
                   ('医生', '职业'), ('钢琴', '乐器'), ('三角形', '图形')]),
        ('反义', [('白天', '夜晚'), ('高', '矮'), ('热', '冷'),
                   ('宽', '窄'), ('快', '慢'), ('厚', '薄'),
                   ('前进', '后退'), ('开始', '结束')]),
    ],
    'medium': [
        ('对象与用途', [('书', '阅读'), ('钥匙', '开锁'), ('雨伞', '遮雨'),
                        ('温度计', '测温'), ('剪刀', '剪纸'), ('地图', '导航')]),
        ('部分与整体', [('车轮', '汽车'), ('手指', '手'), ('树叶', '树'),
                        ('琴弦', '吉他'), ('门', '房子'), ('翅膀', '鸟')]),
    ],
    'hard': [
        ('属性与主体', [('长寿', '乌龟'), ('凶猛', '老虎'), ('勤劳', '蜜蜂'),
                        ('灵活', '猫'), ('坚硬', '钻石'), ('甘甜', '蜂蜜')]),
        ('功能与对象', [('保温', '棉衣'), ('导航', '指南针'), ('录音', '录音笔'),
                        ('照明', '手电筒'), ('计时', '沙漏'), ('消毒', '酒精')]),
    ],
}

VERBAL_NOISE = {
    '种属': ['花朵', '果实', '叶子', '树干'],
    '反义': ['明亮', '沉重', '陡峭', '粗糙'],
    '对象与用途': ['演奏', '书写', '调味', '搬运'],
    '部分与整体': ['轮胎', '脚趾', '枝干', '窗框'],
    '属性与主体': ['懒惰', '温顺', '缓慢', '柔软'],
    '功能与对象': ['保温', '装饰', '计算', '清洁'],
}


def gen_verbal(rng, difficulty, count, start_id):
    items = []
    relations = VERBAL_BANK[difficulty]
    for index in range(count):
        relation, pairs = relations[index % len(relations)]
        (a, b), (c, _) = rng.sample(pairs, 2)
        answer = b
        noise = [x for x in VERBAL_NOISE[relation] if x not in (b,)]
        distractors = rng.sample(noise, min(3, len(noise)))
        while len(distractors) < 3:
            filler = f'以上都不对'
            if filler not in distractors:
                distractors.append(filler)
        options = [b] + distractors
        rng.shuffle(options)
        prompt = f'{a} : {b} ＝ {c} : ？'
        explanation = f'{a} 与 {b} 构成{relation}关系，同理 {c} 应对应「{b}」。'
        items.append(make_item('verbal', difficulty, prompt, options,
                               options.index(b), explanation, start_id + index))
    return items


# ---------------------------------------------------------------- logic

NAMES = ['小明', '小红', '小华', '小刚', '小美', '小强', '小丽', '小军']


def gen_logic(rng, difficulty, count, start_id):
    items = []
    styles = {
        'easy': ['排序', '全称'],
        'medium': ['全称', '逆否', '排序'],
        'hard': ['逆否', '排序', '排除'],
    }[difficulty]
    for index in range(count):
        style = styles[index % len(styles)]
        if style == '排序':
            first, second, third = rng.sample(NAMES, 3)
            dimension = rng.choice(['高', '重', '大'])
            prompt = f'{first}比{second}{dimension}，{second}比{third}{dimension}。那么三人中最小的{dimension[0]}的是：'
            answer = third
            options = [first, second, third, '无法确定']
            rng.shuffle(options)
            explanation = f'由 {first} > {second} > {third}，可知最小的是{third}。'
        elif style == '全称':
            animal = rng.choice(['狗', '猫', '鸟', '马'])
            ability = rng.choice(['会叫', '会飞', '会跑', '会游泳'])
            name = rng.choice(['旺财', '小白', '阿黄', '闪电'])
            prompt = f'已知：所有的{animal}都{ability}。{name}是一只{animal}。那么：'
            answer = f'{name}{ability}'
            options = [f'{name}{ability}', f'{name}不会{ability}', f'{name}是别的动物', '无法判断']
            rng.shuffle(options)
            explanation = f'由全称命题「所有{animal}都{ability}」和「{name}是{animal}」，可推出{name}{ability}。'
        elif style == '逆否':
            condition = rng.choice(['下雨', '迟到', '停电', '堵车'])
            action = rng.choice(['带伞', '打车', '点蜡烛', '换线路'])
            prompt = f'如果{condition}，我就{action}。今天我没有{action}。那么：'
            answer = f'今天没{condition}'
            options = [f'今天没{condition}', f'今天{condition}了', f'{action}丢了', '无法判断']
            rng.shuffle(options)
            explanation = f'原命题的逆否命题成立：没{action} ⇒ 今天没{condition}。'
        else:  # 排除
            a, b, c = rng.sample(NAMES, 3)
            prompt = (f'甲、乙、丙三人中只有一人是第一名。甲不是第一名，乙也不是第一名。那么第一名是：')
            answer = c
            options = [a, b, c, '无法确定']
            rng.shuffle(options)
            explanation = f'甲、乙都不是第一名，只有可能是{c}。'
        items.append(make_item('logic', difficulty, prompt, options,
                               options.index(answer), explanation, start_id + index))
    return items


# ---------------------------------------------------------------- 组装与写入

def main():
    parser = argparse.ArgumentParser(description='生成瑞文题库扩充题目')
    parser.add_argument('--check', action='store_true', help='只校验，不写入')
    args = parser.parse_args()

    path = os.path.join(ROOT, 'Questions.json')
    bank = json.load(open(path, encoding='utf-8'))
    existing_ids = {item['id'] for item in bank}
    next_id = max(int(i) for i in existing_ids) + 1
    used_prompts = {item['prompt'] for item in bank}

    generated = []
    rng = random.Random(SEED)
    for category, generator in (('number', gen_number), ('pattern', gen_pattern),
                                ('verbal', gen_verbal), ('logic', gen_logic)):
        for difficulty in ('easy', 'medium', 'hard'):
            # 多生成一些并丢弃重复题干：既有题库零重复，新增题也应保持。
            items = []
            attempts = 0
            while len(items) < PER_COMBINATION and attempts < 12:
                attempts += 1
                for item in generator(rng, difficulty, PER_COMBINATION, 0):
                    if item['prompt'] in used_prompts:
                        continue
                    used_prompts.add(item['prompt'])
                    item['id'] = next_id
                    next_id += 1
                    items.append(item)
                    if len(items) == PER_COMBINATION:
                        break
            assert len(items) == PER_COMBINATION, f'{category}/{difficulty} 生成不足'
            generated.extend(items)

    for item in generated:
        assert item['id'] not in existing_ids, item['id']
        existing_ids.add(item['id'])
        assert len(item['options']) >= 2
        assert item['explanation'].strip()
        for option in item['options']:
            assert option.strip(), item['prompt']
        check_answer_key(item)

    print(f'校验通过：新增 {len(generated)} 题，'
          f'题库 {len(bank)} → {len(bank) + len(generated)} 题')

    if args.check:
        for item in generated[:6]:
            print(f"[{item['category']}/{item['difficulty']}] {item['prompt']}")
            print(f"   {item['options']} → {item['explanation']}")
        return

    bank.extend(generated)
    with open(path, 'w', encoding='utf-8') as handle:
        json.dump(bank, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
    print(f'已写入 Questions.json：{len(bank)} 题')
    from collections import Counter
    counts = Counter((item['category'], item['difficulty']) for item in bank)
    for category in ('number', 'verbal', 'logic', 'pattern'):
        row = '  '.join(f'{d} {counts[(category, d)]}' for d in ('easy', 'medium', 'hard'))
        print(f'   {category:<9}{row}')


if __name__ == '__main__':
    main()
