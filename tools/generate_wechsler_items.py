"""生成韦氏题库的扩充题目。

扩充题库的直接原因：每组原本只有 120 题，而完整练习一轮就把全部 120 题做完，
第二次测试必然 100% 遇到原题——复测分数会混入练习效应，多次测量也失去意义。

生成方式按构念分两类：
  程序化生成  编码、符号搜索、数字广度、矩阵推理、算术、积木、视觉拼图。
              这些分测验本身就是「按规则转换符号」「按序列回忆」「按形状拼合」，
              用模板加随机参数生成最忠实于韦氏的构念，且答案由生成逻辑保证正确、可自动校验。
  手工撰写    类同、词汇、常识。
              这三项测的是语义与事实，程序生成无法保证正确，由本文件内的语料逐题给出。

用法：
    python3 tools/generate_wechsler_items.py            # 生成并追加到题库
    python3 tools/generate_wechsler_items.py --check    # 只校验，不写入

固定随机种子，重复运行得到同样的题库。
"""
import argparse
import json
import os
import random

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'IQTest', 'Resources')
SEED = 20261022
NEW_PER_SUBTEST = 12

SYMBOLS = ['■', '●', '▲', '◆', '★', '☆', '○', '◇', '□', '△', '▽', '◎']
# 视觉上容易混淆的符号对：目标符号的「孪生」不出现在干扰项中，
# 否则符号搜索会变成辨字形而不是找目标。
SIMILAR_GROUPS = [['★', '☆'], ['○', '◇'], ['■', '□'], ['▲', '△'],
                   ['●', '◎'], ['▼', '▽'], ['◆', '◇']]


def similar_to(symbol):
    for group in SIMILAR_GROUPS:
        if symbol in group:
            return {s for s in group if s != symbol}
    return set()


SHAPES = ['正方形', '长方形', '三角形', '圆形', '椭圆', '球', '圆锥', '圆柱', '梯形', '五边形']

# 新题的难度参数（θ 尺度，负值越负越难）。
# 数字广度与算术按题目结构直接推算；其余按分测验的基准值加小扰动，
# 使新题参数落在该分测验既有参数的区间内，不引入系统性的边际偏差。
# 注意：这些是按结构估计的初值，与旧题同样属于启发式设定，未经真实数据标定。
DIFFICULTY_PROFILE = {
    'arithmetic': (-1.8, 1.0),
    'block': (-2.0, 0.8),
    'coding': (-0.6, 0.25),
    'information': (-1.3, 0.9),
    'matrix': (-2.1, 0.6),
    'similarities': (-2.4, 0.9),
    'symbolsearch': (-1.2, 0.2),
    'visualpuzzle': (-1.6, 0.9),
    'vocabulary': (-1.8, 1.3),
}


def sequence_distractors(rng, sequence, replace_pool, count=3):
    """为序列生成 count 个互不相同、且与原序列不同的干扰项。

    不靠「排列去重」来凑数：序列含重复元素时不同排列可能不足 count 个，
    那样的循环取不满就会挂住。这里用交换位置、替换元素、重新排列三种方式，
    每一项都能保证与原序列不同。
    """
    wrong = []
    original = list(sequence)

    def add(candidate):
        if candidate != original and candidate not in wrong:
            wrong.append(candidate)

    for _ in range(30):
        if len(wrong) >= count:
            break
        if len(original) < 2:
            break
        i, j = rng.sample(range(len(original)), 2)
        candidate = list(original)
        candidate[i], candidate[j] = candidate[j], candidate[i]
        add(candidate)

    for _ in range(30):
        if len(wrong) >= count:
            break
        index = rng.randrange(len(original))
        candidate = list(original)
        alternatives = [x for x in replace_pool if x != original[index]]
        if not alternatives:
            break
        candidate[index] = rng.choice(alternatives)
        add(candidate)

    for _ in range(30):
        if len(wrong) >= count:
            break
        candidate = list(original)
        rng.shuffle(candidate)
        add(candidate)

    return wrong


def make_item(subtest, prompt, options, correct_index, explanation, **extra):
    scores = [0] * len(options)
    scores[correct_index] = extra.pop('max_score', 1)
    item = {'subtest': subtest, 'prompt': prompt, 'options': options,
            'optionScores': scores, 'explanation': explanation}
    item.update(extra)
    return item


def distractors(rng, correct, pool, count=3):
    """从候选中取不与正确答案重复的干扰项。"""
    options = [correct]
    candidates = [x for x in pool if x != correct]
    rng.shuffle(candidates)
    for candidate in candidates:
        if len(options) >= count + 1:
            break
        if candidate not in options:
            options.append(candidate)
    while len(options) < count + 1:
        filler = f'以上都不对'
        if filler not in options:
            options.append(filler)
    return options


# ---------------------------------------------------------------- 程序化生成

def gen_coding(rng, count):
    """密码替换：按题干给出的符号—数字映射，逐个替换并保持顺序。"""
    items = []
    for index in range(count):
        symbols = rng.sample(SYMBOLS, 4)
        values = rng.sample(range(1, 10), 4)
        mapping = dict(zip(symbols, values))
        sequence = [rng.choice(symbols) for _ in range(3)]
        answer = ' '.join(str(mapping[s]) for s in sequence)
        # 干扰项是替换后的数字序列，取值范围与题干给出的数字一致。
        wrong_sequences = sequence_distractors(rng, [mapping[s] for s in sequence], range(1, 10))
        prompt = (f'密码：{"、".join(f"{s}={v}" for s, v in mapping.items())}。'
                  f'那么 {" ".join(sequence)} 代表：')
        explanation = (f'逐个按题干映射替换并保持顺序，'
                       f'{"、".join(f"{s}={mapping[s]}" for s in sequence)} → {answer}。')
        options = [answer] + [' '.join(str(x) for x in w) for w in wrong_sequences]
        rng.shuffle(options)
        items.append(make_item('coding', prompt, options, options.index(answer), explanation))
    return items


def gen_symbolsearch(rng, count):
    """目标符号：四个三符号组合中只有一个含有目标符号。"""
    items = []
    for index in range(count):
        target = rng.choice(SYMBOLS)
        twins = similar_to(target)
        others = [s for s in SYMBOLS if s != target and s not in twins]
        # 三个不含目标的组合，彼此不能重复。
        rows = []
        seen = set()
        for _ in range(60):
            if len(rows) >= 3:
                break
            pair = tuple(rng.sample(others, 2))
            if pair not in seen:
                seen.add(pair)
                rows.append(list(pair))
        # 含目标的那一组，位置随机以免总是固定在第一个。
        with_target = [target, rng.choice(others)]
        if rng.random() < 0.5:
            with_target.reverse()
        rows.append(with_target)
        target_text = ' '.join(with_target)
        rng.shuffle(rows)
        options = [' '.join(row) for row in rows]
        prompt = f'目标符号 {target}。下面哪一组含有 {target}？'
        explanation = f'逐一核对目标 {target}，只有得分选项含有完全相同的符号。'
        items.append(make_item('symbolsearch', prompt, options, options.index(target_text), explanation))
    return items


def gen_digitspan(rng, count):
    """数字广度：记住数字序列，随后按指定规则回忆。"""
    items = []
    rules = [('forward', '相同顺序', 3, 7), ('backward', '相反顺序', 3, 5), ('ascending', '从小到大', 3, 5)]
    for index in range(count):
        rule, rule_text, min_len, max_len = rules[index % len(rules)]
        length = rng.randint(min_len, max_len)
        digits = [rng.randint(0, 9) for _ in range(length)]
        stimulus = ' '.join(str(d) for d in digits)
        if rule == 'forward':
            answer_digits = digits
        elif rule == 'backward':
            answer_digits = list(reversed(digits))
        else:
            answer_digits = sorted(digits)
        answer = ' '.join(str(d) for d in answer_digits)
        wrong_sequences = sequence_distractors(rng, answer_digits, range(10))
        wrong = [' '.join(str(d) for d in w) for w in wrong_sequences]
        options = [answer] + wrong
        rng.shuffle(options)
        prompt = f'请记住下面的数字，随后请按【{rule_text}】回忆。'
        explanation = f'按{rule_text}回忆，应输入：{answer.replace(" ", "")}。'
        # 位数越多越难；逆序与升序比正序稍难。
        by_length = {3: 0.6, 4: 0.2, 5: -0.5, 6: -1.2, 7: -1.8}
        difficulty = by_length.get(length, -1.0)
        if rule != 'forward':
            difficulty -= 0.3
        item = make_item('digitspan', prompt, options, options.index(answer), explanation,
                         presentation='digits', stimulus=stimulus,
                         displaySeconds=rng.choice([4, 5, 6]), recallRule=rule)
        item['_difficulty'] = round(difficulty, 2)
        items.append(item)
    return items


def gen_matrix(rng, count):
    """矩阵推理：三种规则——主对角线相同、沿行移动、整行左移。"""
    items = []
    for index in range(count):
        style = index % 3
        if style == 0:
            # 主对角线上的符号相同
            a, b, c, d, e = rng.sample(SYMBOLS[:8], 5)
            rows = [[a, b, c], [d, a, b], [e, d, None]]
            answer = a
            explanation = f'主对角线上的符号都是 {a}，第三行第三位应为 {a}。'
        elif style == 1:
            mover, other = rng.sample(SYMBOLS[:8], 2)
            rows = [[mover, other, other], [other, mover, other], [other, other, None]]
            answer = mover
            explanation = f'{mover} 在每行从左到右依次移动一格，第三行应落在第三格。'
        else:
            a, b, c = rng.sample(SYMBOLS[:8], 3)
            rows = [[a, b, c], [b, c, a], [c, a, None]]
            answer = b
            explanation = f'每行整体左移一位，第一行为 {a} {b} {c}，第三行第三位应为 {b}。'
        options = [answer] + [s for s in SYMBOLS[:8] if s != answer][:3]
        rng.shuffle(options)
        prompt = f'矩阵：第一行 {" ".join(str(x) for x in rows[0])}，' \
                 f'第二行 {" ".join(str(x) for x in rows[1])}，' \
                 f'第三行 {" ".join(str(x) if x is not None else "？" for x in rows[2])}'
        items.append(make_item('matrix', prompt, options, options.index(answer), explanation))
    return items


ARITHMETIC_TEMPLATES = [
    ('心算：{a} + {b} = ？', lambda a, b: a + b, '{a}+{b}={res}'),
    ('心算：{a} − {b} = ？', lambda a, b: a - b, '{a}−{b}={res}'),
    ('每 {b} 个一组，共有 {a} 组，一共有多少个？',
     lambda a, b: a * b, '{b}×{a}={res}'),
    ('每本笔记本 {b} 元，买 {a} 本一共要付多少元？',
     lambda a, b: a * b, '{b}×{a}={res} 元'),
    ('把 {a} 个苹果平均分给 {b} 个小朋友，每人分到几个？',
     lambda a, b: a // b if b and a % b == 0 else None, '{a}÷{b}={res}'),
    ('原有 {a} 元，用掉 {b} 元，还剩多少元？',
     lambda a, b: a - b, '{a}−{b}={res} 元'),
    ('一盒有 {b} 支笔，{a} 盒一共有多少支？',
     lambda a, b: a * b, '{b}×{a}={res} 支'),
    ('每排坐 {b} 人，坐了 {a} 排，一共坐了多少人？',
     lambda a, b: a * b, '{b}×{a}={res} 人'),
]


def gen_arithmetic(rng, count):
    """算术：心算与应用情境混合，答案由生成时的运算保证。"""
    items = []
    for index in range(count):
        template, compute, explain = ARITHMETIC_TEMPLATES[index % len(ARITHMETIC_TEMPLATES)]
        for _ in range(40):
            a = rng.randint(3, 60)
            b = rng.randint(2, 19)
            result = compute(a, b)
            # 结果过大时心算不现实，丢弃重取。
            if result is not None and 0 < result <= 200:
                break
        if result is None:
            continue
        unit = ' 元' if '元' in template else (' 人' if '人' in template else (' 支' if '支' in template else ''))
        answer = f'{result}{unit}'
        wrong = set()
        while len(wrong) < 3:
            offset = rng.choice([-3, -2, -1, 1, 2, 3, 10, -10])
            candidate = f'{result + offset}{unit}'
            if candidate != answer and result + offset > 0:
                wrong.add(candidate)
        options = [answer] + list(wrong)
        rng.shuffle(options)
        prompt = template.format(a=a, b=b)
        explanation = explain.format(a=a, b=b, res=result) + '。'
        # 结果越大越难，结果区间 4–200 对应难度 -0.6 到 -2.5。
        difficulty = -0.5 - (result / 200.0) * 2.0
        item = make_item('arithmetic', prompt, options, options.index(answer), explanation)
        item['_difficulty'] = round(difficulty, 2)
        items.append(item)
    return items


BLOCK_TEMPLATES = [
    # 题干模板；每个模板配合不同的长方形组合，构成互不重复的题目。
    '用 {n} 个相同的小正方体，可以拼成：',
    '一层 {a}×{b} 的长方形由 {n} 个小正方体拼成，从上面看是：',
    '用 {n} 个相同的小正方体，最少能拼成几个边长为 2 的大正方体？',
    '一层 {a}×{b} 的长方形由 {n} 个小正方体拼成，那么一层 {a2}×{b} 的长方形需要多少个小正方体？',
]


def gen_block(rng, count, template_offset=0):
    """积木：小正方体拼合成什么形状。

    template_offset 让 A、B 两组用不同的题干模板，两组的新题因此不会重复。
    """
    items = []
    shapes = [(2, 2), (2, 3), (2, 4), (3, 3), (3, 4), (4, 4)]
    for index in range(count):
        template_id = (index + template_offset) % len(BLOCK_TEMPLATES)
        a, b = shapes[index % len(shapes)]
        n = a * b
        if template_id == 0:
            answer = f'一层 {a}×{b} 的长方形'
            prompt = f'用 {n} 个相同的小正方体，可以拼成：'
            explanation = f'{n} 个小正方体可排成 {a}×{b} 的长方形；其他选项需要的块数或形状都对不上。'
        elif template_id == 1:
            answer = f'一个 {a}×{b} 的长方形'
            prompt = f'一层 {a}×{b} 的长方形由 {n} 个小正方体拼成，从上面看是：'
            explanation = f'这 {n} 个小正方体排成的是 {a}×{b} 的长方形。'
        elif template_id == 2:
            big = n // 4
            answer = f'{big} 个边长为 2 的大正方体'
            prompt = f'用 {n} 个相同的小正方体，最少能拼成几个边长为 2 的大正方体？'
            explanation = f'每个边长为 2 的大正方体需要 4 个小正方体，{n} ÷ 4 = {big}。'
        else:
            a2 = a + 1
            n2 = a2 * b
            answer = f'{n2} 个小正方体'
            prompt = (f'一层 {a}×{b} 的长方形由 {n} 个小正方体拼成，'
                      f'那么一层 {a2}×{b} 的长方形需要多少个小正方体？')
            explanation = f'一层 {a2}×{b} 的长方形需要 {a2}×{b} = {n2} 个小方块。'
        # 干扰项取自固定的形状池并保证互不相同，也避免出现语义重复的选项。
        wrong = rng.sample(['一个大圆球', '一个大圆锥', '一个圆柱体',
                            '一个五边形', '一个六边形', '一个八边形'], 3)
        options = [answer] + wrong
        rng.shuffle(options)
        items.append(make_item('block', prompt, options, options.index(answer), explanation))
    return items


PUZZLE_TEMPLATES = [
    # 24 个模板，A、B 两组各取 12 个不重叠的，两组因此不会遇到同一道拼合题。
    ('两个完全相同的半圆，可以拼成：', '一个圆', ['一个正方形', '一个三角形', '一个椭圆']),
    ('一个正方形沿对角线剪开，得到两个：', '等腰直角三角形', ['长方形', '梯形', '圆形']),
    ('两个完全一样的等腰直角三角形，可以拼成一个：', '正方形', ['五边形', '椭圆', '球']),
    ('三个相同的直角三角形，可以拼成一个：', '长方形', ['球', '圆锥', '五边形']),
    ('一个长方形沿中线对折，得到两个：', '完全相同的小长方形', ['三角形', '圆形', '梯形']),
    ('一个平行四边形沿对角线剪开，得到两个：', '完全相同的三角形', ['正方形', '圆形', '梯形']),
    ('四个完全相同的正方形，可以拼成一个：', '大正方形', ['球', '圆柱', '五边形']),
    ('一个圆形沿直径对折，得到两个：', '完全相同的半圆', ['三角形', '正方形', '梯形']),
    ('两个完全相同的直角三角形，可以拼成一个：', '长方形', ['正方形', '圆', '梯形']),
    ('一个圆形沿半径剪开，得到两个：', '扇形', ['三角形', '长方形', '正方形']),
    ('三个完全相同的正方形，可以拼成一个：', '长方形', ['梯形', '三角形', '圆形']),
    ('一个圆沿两条半径剪开，得到四个：', '扇形', ['三角形', '长方形', '正方形']),
    ('两个完全相同的梯形，可以拼成一个：', '平行四边形', ['长方形', '三角形', '圆']),
    ('两个完全相同的等边三角形，可以拼成一个：', '菱形', ['正方形', '梯形', '圆']),
    ('一个正方形沿水平中线剪开，得到两个：', '完全相同的小长方形', ['三角形', '圆', '梯形']),
    ('两个完全相同的月牙形，可以拼成一个：', '圆', ['椭圆', '菱形', '梯形']),
    ('一个梯形的两腰向外翻折，可以拼成一个：', '长方形', ['三角形', '圆形', '梯形']),
    ('四个完全相同的等腰直角三角形，可以拼成一个：', '正方形', ['长方形', '菱形', '圆']),
    ('两个完全相同的直角梯形，可以拼成一个：', '长方形', ['三角形', '梯形', '圆']),
    ('一个六边形沿对角线分成两个：', '完全相同的梯形', ['三角形', '长方形', '正方形']),
    ('两个完全相同的正五边形，可以拼成一个：', '十边形', ['长方形', '三角形', '圆形']),
    ('一个正方形对角线剪开后，把两个三角形重新拼回去，得到：', '正方形', ['长方形', '菱形', '三角形']),
    ('三个完全相同的扇形（圆心角 120 度），可以拼成一个：', '圆', ['半圆', '扇形', '长方形']),
]


def gen_visualpuzzle(rng, count, template_offset=0):
    """视觉拼图：两个或几个相同形状如何拼合。

    template_offset 让 A、B 两组用不同的模板，两组的新题因此不会重复。
    """
    items = []
    for index in range(count):
        prompt, answer, wrong_pool = PUZZLE_TEMPLATES[(index + template_offset) % len(PUZZLE_TEMPLATES)]
        wrong = rng.sample(wrong_pool, min(3, len(wrong_pool)))
        options = [answer] + wrong
        rng.shuffle(options)
        explanation = f'按几何关系，{prompt.rstrip("：")}的结果是{answer}。'
        items.append(make_item('visualpuzzle', prompt, options, options.index(answer), explanation))
    return items


# ---------------------------------------------------------------- 手工撰写
# 语义类题目（类同、词汇、常识）无法由程序保证正确，逐题给出。
# 每条为 (题干, 选项, 满分选项下标, 解析)。部分得分题按韦氏惯例给最概括的类别满分。

SIMILARITIES_A = [
    ('医生和护士在哪些方面相似？',
     ['都是照顾病人健康的医疗从业者', '都穿白大褂', '都需要轮班工作', '都必须会打针'], 0,
     '最概括的共同类别是医疗从业者；白大褂、轮班、打针都只是部分职业特征。'),
    ('钢琴和吉他在哪些方面相似？',
     ['都是乐器', '都需要用手弹奏', '都有六根弦', '都有黑色琴身'], 0,
     '最概括的共同类别是乐器；手弹、六根弦、黑色琴身都只适用于其中一部分。'),
    ('火车和轮船在哪些方面相似？',
     ['都是运送人或货物的交通工具', '都会发出轰鸣声', '都需要燃料', '都能装载大量货物'], 0,
     '最概括的共同类别是交通工具；轰鸣、燃料、载货量都不是两者都具备的。'),
    ('蜜蜂和蚂蚁在哪些方面相似？',
     ['都是昆虫', '都有六条腿', '都采食花蜜', '都筑巢而居'], 0,
     '最概括的共同类别是昆虫；六条腿是共同特征但不如「昆虫」这一类别概括。'),
    ('地球和月球在哪些方面相似？',
     ['都是天体', '都有自转', '都有表面', '都围绕恒星运行'], 0,
     '最概括的共同类别是天体；自转、表面、绕恒星运行都只适用于其中之一。'),
    ('汉字和英语在哪些方面相似？',
     ['都是记录语言的符号系统', '都有表音成分', '都由字母组成', '都从左往右书写'], 0,
     '最概括的共同类别是记录语言的符号系统；表音、字母组成、书写方向都只适用于其中之一。'),
    ('篮球和排球在哪些方面相似？',
     ['都是球类运动', '都需要用球', '都分两队对抗', '都在室内进行'], 0,
     '最概括的共同类别是球类运动；用球、两队对抗、室内进行都不完全成立。'),
    ('雨伞和帐篷在哪些方面相似？',
     ['都是可以挡雨的用品', '都能折叠携带', '都靠支架撑开', '都必须在户外使用'], 0,
     '最概括的共同类别是挡雨用品；折叠、支架、户外使用只适用于其中一部分。'),
    ('三角形和正方形在哪些方面相似？',
     ['都是几何图形', '都有三条边', '都有直角', '面积都相等'], 0,
     '最概括的共同类别是几何图形；三条边属于三角形，直角两者都有但不如类别概括。'),
    ('鲸鱼和海豚在哪些方面相似？',
     ['都是哺乳动物', '都生活在海洋', '都用鳃呼吸', '都有流线型身体'], 0,
     '最概括的共同类别是哺乳动物；鲸与海豚都用肺呼吸，所以「用鳃呼吸」是错的。'),
    ('铅笔和钢笔在哪些方面相似？',
     ['都是书写工具', '都有笔身', '都需要削或拔笔帽', '写出的字都可擦除'], 0,
     '最概括的共同类别是书写工具；削或拔笔帽是部分特征，铅笔的字不可擦除。'),
    ('太阳和月亮在哪些方面相似？',
     ['都是天体', '都会发光', '都有盈亏', '都围绕地球运行'], 0,
     '最概括的共同类别是天体；月亮不发光，盈亏与绕地运行都只适用于其中之一。'),
]

SIMILARITIES_B = [
    ('医生和律师在哪些方面相似？',
     ['都是需要专业资格与长期训练的职业', '都在法庭或诊室工作', '都有顾问性质', '都需要理解他人诉求'], 0,
     '最概括的共同类别是需要专业资格的职业；工作场所、是否顾问、是否理解诉求都只适用于其中一部分。'),
    ('小提琴和钢琴在哪些方面相似？',
     ['都是乐器', '都需要演奏技巧', '都能演奏旋律', '都有踏板'], 0,
     '最概括的共同类别是乐器；演奏技巧与旋律两者都有，踏板只属于钢琴。'),
    ('火车和飞机在哪些方面相似？',
     ['都是运送人货的交通工具', '都靠动力驱动', '都能跨区域移动', '都有时刻表'], 0,
     '最概括的共同类别是交通工具；动力、跨区域、时刻表不是两者都具备的。'),
    ('蜜蜂和蝴蝶在哪些方面相似？',
     ['都是昆虫', '都有翅膀', '都要经过完全变态', '都吸食花蜜'], 0,
     '最概括的共同类别是昆虫；翅膀是共同特征但不如「昆虫」概括，吸食花蜜不适用于蜜蜂以外的全部。'),
    ('太阳和地球在哪些方面相似？',
     ['都是天体', '都在引力作用下运动', '都有自转', '都属于同一恒星系统'], 0,
     '最概括的共同类别是天体；自转与恒星系统是共同特征但不如类别概括。'),
    ('汉字和希腊字母在哪些方面相似？',
     ['都是记录语言的符号', '都有一定书写顺序', '都由多个单元组成', '都可以表音'], 0,
     '最概括的共同类别是记录语言的符号；书写顺序、单元组成、表音都只适用于其中一部分。'),
    ('足球和乒乓球在哪些方面相似？',
     ['都是球类运动', '都需要用球', '都是两队对抗', '都需要球网或球门'], 0,
     '最概括的共同类别是球类运动；球网与球门分别只属于其中一种。'),
    ('雨衣和帐篷在哪些方面相似？',
     ['都是防雨用品', '都能穿在身上或架起来', '都由防水材料制成', '都能随身携带'], 0,
     '最概括的共同类别是防雨用品；穿戴或架设、防水材料、携带方式都只适用于一部分。'),
    ('圆形和三角形在哪些方面相似？',
     ['都是几何图形', '都有直边或弧线', '面积都可以计算', '都能用尺规作图'], 0,
     '最概括的共同类别是几何图形；直边只属于三角形，面积计算与尺规作图两者都成立。'),
    ('老虎和狮子在哪些方面相似？',
     ['都是猫科动物', '都是肉食动物', '都有条纹或鬃毛', '都能发出吼声'], 0,
     '最概括的共同类别是猫科动物；条纹只属于老虎，鬃毛主要属于雄狮。'),
    ('铅笔和圆珠笔在哪些方面相似？',
     ['都是书写工具', '都有笔身', '都靠石墨或油墨留下痕迹', '写出的字都可擦除'], 0,
     '最概括的共同类别是书写工具；圆珠笔写出的字不可擦除，所以最后一项是错的。'),
    ('星星和月亮在哪些方面相似？',
     ['都是天体', '都能反射光', '位置都随时间变化', '都属于太阳系'], 0,
     '最概括的共同类别是天体；反射光两者都有但不如类别概括，太阳系只适用于月亮与部分恒星。'),
]

VOCABULARY_A = [
    ('「慷慨」最接近的意思是：',
     ['乐于给予、大方', '计较得失、小气', '犹豫不决', '爱讲道理'], 0,
     '慷慨指待人宽厚、愿意给予。'),
    ('「沉思」最接近的意思是：',
     ['深入地思考', '大声说话', '来回走动', '迅速做完'], 0,
     '沉思指深入、反复地思考。'),
    ('「坚固」最接近的意思是：',
     ['结实而牢固', '颜色很鲜艳', '位置很偏远', '价格很昂贵'], 0,
     '坚固指结构牢靠、不易损坏。'),
    ('「陌生」最接近的意思是：',
     ['不熟悉、不认识', '十分遥远', '非常安静', '格外珍贵'], 0,
     '陌生指不熟悉、没见过或不了解。'),
    ('「敏捷」最接近的意思是：',
     ['动作快而灵活', '身材很高大', '性情很温和', '思路很迟缓'], 0,
     '敏捷形容动作轻快、反应灵敏。'),
    ('「宁静」最接近的意思是：',
     ['安静而平和', '喧闹而拥挤', '紧张而急促', '整洁而有序'], 0,
     '宁静指安静、不喧闹。'),
    ('「陡峭」最接近的意思是：',
     ['坡度很大', '路面很平坦', '树木很茂密', '道路很长'], 0,
     '陡峭形容坡度大、落差急。'),
    ('「准确」最接近的意思是：',
     ['精确而没有偏差', '速度很快', '数量很多', '声音很响亮'], 0,
     '准确指与实际完全相符，没有误差。'),
    ('「疲倦」最接近的意思是：',
     ['因劳累而感到疲乏', '因兴奋而睡不着', '因困惑而说不出话', '因寒冷而发抖'], 0,
     '疲倦指因过度劳累而疲乏无力。'),
    ('「清晰」最接近的意思是：',
     ['清楚而明白', '颜色很暗淡', '声音很嘈杂', '价格很昂贵'], 0,
     '清晰指清楚、不含糊。'),
    ('「谨慎」最接近的意思是：',
     ['做事小心、考虑周全', '行动迅速果断', '态度冷漠疏远', '喜欢高谈阔论'], 0,
     '谨慎指小心谨慎、避免冒进。'),
    ('「微弱」最接近的意思是：',
     ['轻微而弱', '强烈而持久', '尖锐刺耳', '沉重缓慢'], 0,
     '微弱指强度小、不明显。'),
]

VOCABULARY_B = [
    ('「干燥」最接近的意思是：',
     ['不含水分', '非常潮湿', '空气不流通', '天气很寒冷'], 0,
     '干燥指缺少水分。'),
    ('「拥挤」最接近的意思是：',
     ['人多而不宽敞', '空旷而安静', '整齐而有秩序', '缓慢而平稳'], 0,
     '拥挤指空间狭小而人很多。'),
    ('「沉重」最接近的意思是：',
     ['分量大、压手', '声音很尖细', '动作很灵巧', '颜色很浅淡'], 0,
     '沉重指重量大，也常形容声音或心情。'),
    ('「模糊」最接近的意思是：',
     ['不清楚、不分明', '非常清楚明确', '非常沉重缓慢', '非常明亮刺眼'], 0,
     '模糊指轮廓或界限不清楚。'),
    ('「灵巧」最接近的意思是：',
     ['动作灵活而聪明', '身材高大结实', '性情安静温和', '做事缓慢迟钝'], 0,
     '灵巧指灵活敏捷、聪明机敏。'),
    ('「荒凉」最接近的意思是：',
     ['人迹稀少而荒芜', '繁华而热闹', '整齐而清洁', '浓密而茂盛'], 0,
     '荒凉指荒无人烟、荒废空旷。'),
    ('「冷淡」最接近的意思是：',
     ['不热情、不亲切', '非常热心体贴', '非常严肃正式', '非常缓慢迟钝'], 0,
     '冷淡指态度不热情、不亲热。'),
    ('「迟缓」最接近的意思是：',
     ['缓慢、动作慢', '迅速、动作快', '沉重、压力大', '清晰、很明白'], 0,
     '迟缓指缓慢、不够敏捷。'),
    ('「鲜明」最接近的意思是：',
     ['颜色清楚、对比强烈', '颜色很灰暗', '声音很轻微', '形状很规则'], 0,
     '鲜明形容色彩或对比强烈醒目。'),
    ('「琐碎」最接近的意思是：',
     ['细小而纷杂、无关紧要', '重要而关键', '整齐而有条理', '强烈而激动'], 0,
     '琐碎指细小零碎、不值一提。'),
    ('「端正」最接近的意思是：',
     ['整齐而正', '歪斜而不正', '沉重而不稳', '模糊而不清'], 0,
     '端正指整齐、正。'),
    ('「稀少」最接近的意思是：',
     ['数量很少', '数量很多', '分布很平均', '增长很快'], 0,
     '稀少指数量少、难得见到。'),
]

INFORMATION_A = [
    ('通常按春、夏、秋、冬划分，一年有几个季节？',
     ['两个', '三个', '四个', '六个'], 2,
     '通常按春、夏、秋、冬划分四季。'),
    ('水的化学式是：',
     ['CO2', 'H2O', 'O2', 'NaCl'], 1,
     '水由两个氢原子与一个氧原子组成，化学式为 H2O。'),
    ('一个星期有几天？',
     ['五天', '六天', '七天', '十天'], 2,
     '一个星期七天。'),
    ('一天有多少个小时？',
     ['十二个', '二十四个', '三十六个', '六十个'], 1,
     '一天二十四小时。'),
    ('一年有几个月？',
     ['十个月', '十一个月', '十二个月', '六个月'], 2,
     '一年十二个月。'),
    ('三角形有几个角？',
     ['两个', '三个', '四个', '五个'], 1,
     '三角形有三个角与三条边。'),
    ('人的心脏有几个？',
     ['一个', '两个', '三个', '四个'], 0,
     '人只有一个心脏。'),
    ('血液中负责运输氧气的是哪一种细胞？',
     ['白细胞', '红细胞', '血小板', '淋巴细胞'], 1,
     '红细胞含血红蛋白，负责运输氧气。'),
    ('世界最高峰是：',
     ['珠穆朗玛峰', '乞力马扎罗山', '阿尔卑斯山', '安第斯山'], 0,
     '珠穆朗玛峰海拔约 8848 米，是世界最高峰。'),
    ('光在真空中的传播速度大约是每秒：',
     ['三十万公里', '三百公里', '三万公里', '三百万公里'], 0,
     '光速约为每秒 30 万公里，这是宇宙中最快的速度。'),
    ('地球有几颗天然卫星？',
     ['一颗', '两颗', '三颗', '无数颗'], 0,
     '地球只有一颗天然卫星，即月球。'),
    ('一年通常分为几个季度？',
     ['两个', '三个', '四个', '十二个'], 2,
     '一年通常分四个季度，每季三个月。'),
]

INFORMATION_B = [
    ('正方形有几条边？',
     ['三条', '四条', '五条', '六条'], 1,
     '正方形有四条相等的边与四个直角。'),
    ('中国的首都是：',
     ['上海', '北京', '广州', '西安'], 1,
     '北京是中国的首都。'),
    ('在标准大气压下，水的沸点是多少摄氏度？',
     ['50 度', '80 度', '100 度', '120 度'], 2,
     '标准大气压下水的沸点是 100 摄氏度。'),
    ('哺乳动物用什么呼吸？',
     ['鳃', '肺', '皮肤', '触角'], 1,
     '哺乳动物是胎生并用肺呼吸的恒温动物。'),
    ('一个世纪有多少年？',
     ['十年', '五十年', '一百年', '一千年'], 2,
     '一个世纪是一百年。'),
    ('太阳是哪个星系的恒星？',
     ['银河系', '仙女座星系', '室女座星系', '麦哲伦星系'], 0,
     '太阳位于银河系。'),
    ('人的正常体温大约是多少摄氏度？',
     ['约 25 度', '约 30 度', '约 37 度', '约 42 度'], 2,
     '人的正常腋温约 36.5–37.3 摄氏度。'),
    ('世界上面积最大的大洋是：',
     ['大西洋', '印度洋', '北冰洋', '太平洋'], 3,
     '太平洋是面积最大的大洋。'),
    ('标准足球比赛每队上场多少名球员？',
     ['九名', '十名', '十一名', '十二名'], 2,
     '每队上场 11 名球员，另有守门员 1 名。'),
    ('汉字「日」通常表示什么？',
     ['月亮', '太阳', '山', '水'], 1,
     '「日」是太阳的象形字，也用来表示一天。'),
    ('北半球一年中白昼最长的节气是：',
     ['春分', '夏至', '秋分', '冬至'], 1,
     '夏至时北半球白昼最长、黑夜最短。'),
    ('成年人的骨骼通常有多少块？',
     ['约 106 块', '约 206 块', '约 306 块', '约 406 块'], 1,
     '成年人通常有 206 块骨。'),
]

HANDWRITTEN = {
    'A': {'similarities': SIMILARITIES_A, 'vocabulary': VOCABULARY_A, 'information': INFORMATION_A},
    'B': {'similarities': SIMILARITIES_B, 'vocabulary': VOCABULARY_B, 'information': INFORMATION_B},
}


# ---------------------------------------------------------------- 组装与校验

# 部分得分选项：类同与词汇的「较具体但不够概括」的表述，选中得 1 分。
# 韦氏这两个分测验是部分得分的——只给 0/2 分就丢掉了这个层次，
# 也与既有题库（[2,1,0,0]）不一致。常识题保持 0/2 分制。
PARTIAL_OPTIONS = {
    # 类同 A 组
    '医生和护士在哪些方面相似？': '都参与病人的照护工作',
    '钢琴和吉他在哪些方面相似？': '都需要用手演奏',
    '火车和轮船在哪些方面相似？': '都需要动力来驱动',
    '蜜蜂和蚂蚁在哪些方面相似？': '都是社会性昆虫',
    '地球和月球在哪些方面相似？': '都被人类观测和记录',
    '汉字和英语在哪些方面相似？': '都用来记录语言',
    '篮球和排球在哪些方面相似？': '都要靠手控制小球',
    '雨伞和帐篷在哪些方面相似？': '都能挡雨',
    '三角形和正方形在哪些方面相似？': '都有直边和顶点',
    '鲸鱼和海豚在哪些方面相似？': '都要用肺呼吸',
    '铅笔和钢笔在哪些方面相似？': '都能书写文字',
    '太阳和月亮在哪些方面相似？': '都出现在天空中',
    # 类同 B 组
    '医生和律师在哪些方面相似？': '都以口头说明来工作',
    '小提琴和钢琴在哪些方面相似？': '都要靠人演奏',
    '火车和飞机在哪些方面相似？': '都在固定线路上运行',
    '蜜蜂和蝴蝶在哪些方面相似？': '都要经历卵、幼虫、蛹、成虫四个阶段',
    '太阳和地球在哪些方面相似？': '都在绕着中心运转',
    '汉字和希腊字母在哪些方面相似？': '都靠约定而非自然物',
    '足球和乒乓球在哪些方面相似？': '都要用手或脚击球',
    '雨衣和帐篷在哪些方面相似？': '都靠防水布料',
    '圆形和三角形在哪些方面相似？': '都没有角',
    '老虎和狮子在哪些方面相似？': '都是大型哺乳动物',
    '铅笔和圆珠笔在哪些方面相似？': '都要靠手推动书写',
    '星星和月亮在哪些方面相似？': '都能在夜里被看见',
    # 词汇 A 组
    '「慷慨」最接近的意思是：': '愿意付出',
    '「沉思」最接近的意思是：': '想事情',
    '「坚固」最接近的意思是：': '结实',
    '「陌生」最接近的意思是：': '没见过',
    '「敏捷」最接近的意思是：': '动作快',
    '「宁静」最接近的意思是：': '安静',
    '「陡峭」最接近的意思是：': '坡很斜',
    '「准确」最接近的意思是：': '没有偏差',
    '「疲倦」最接近的意思是：': '感到累',
    '「清晰」最接近的意思是：': '清楚',
    '「谨慎」最接近的意思是：': '做事小心',
    '「微弱」最接近的意思是：': '很轻',
    # 词汇 B 组
    '「干燥」最接近的意思是：': '缺少水分',
    '「拥挤」最接近的意思是：': '人很多',
    '「沉重」最接近的意思是：': '很重',
    '「模糊」最接近的意思是：': '看不清楚',
    '「灵巧」最接近的意思是：': '动作灵活',
    '「荒凉」最接近的意思是：': '没有人烟',
    '「冷淡」最接近的意思是：': '不热情',
    '「迟缓」最接近的意思是：': '很慢',
    '「鲜明」最接近的意思是：': '颜色清楚',
    '「琐碎」最接近的意思是：': '细小零碎',
    '「端正」最接近的意思是：': '整齐正',
    '「稀少」最接近的意思是：': '数量少',
}


def hand_written_to_items(entries, subtest):
    """把手写语料转成题目格式。部分得分题按韦氏惯例：最概括的选项满分，
    较具体但说得通的选项得 1 分。"""
    items = []
    for prompt, options, correct_index, explanation in entries:
        scores = [0] * len(options)
        scores[correct_index] = 2
        option_list = list(options)
        partial = PARTIAL_OPTIONS.get(prompt)
        if partial:
            option_list.append(partial)
            scores.append(1)
        items.append({'subtest': subtest, 'prompt': prompt, 'options': option_list,
                      'optionScores': scores, 'explanation': explanation})
    return items


def validate(items, subtest):
    """校验题目是否符合题库要求：唯一满分、选项不重复、解析非空。"""
    for item in items:
        scores = item['optionScores']
        assert item['subtest'] == subtest, item
        assert len(options := item['options']) == len(scores), item['prompt']
        assert len(set(options)) == len(options), f'选项重复：{item["prompt"]}'
        assert max(scores) in (1, 2), item['prompt']
        assert scores.count(max(scores)) == 1, f'满分答案不唯一：{item["prompt"]}'
        assert all(0 <= s <= 2 for s in scores), item['prompt']
        assert item['explanation'].strip(), f'缺少解析：{item["prompt"]}'
        assert item['prompt'].strip(), '题干为空'
        for option in options:
            assert option.strip(), f'存在空选项：{item["prompt"]}'


def build_for_group(group, seed):
    """为一个题组生成全部扩充题目。"""
    rng = random.Random(seed)
    generated = {}
    # 积木与视觉拼图的题干模板由两个题组各取一半，两组因此不会遇到同一道题。
    offset = 0 if group == 'A' else 1
    for subtest, generator in (('coding', gen_coding), ('symbolsearch', gen_symbolsearch),
                               ('digitspan', gen_digitspan), ('matrix', gen_matrix),
                               ('arithmetic', gen_arithmetic),
                               ('block', lambda r, n: gen_block(r, n, offset)),
                               ('visualpuzzle', lambda r, n: gen_visualpuzzle(r, n, offset * 12))):
        generated[subtest] = generator(rng, NEW_PER_SUBTEST)
    for subtest, entries in HANDWRITTEN[group].items():
        generated[subtest] = hand_written_to_items(entries, subtest)
    # 没有按结构推算难度的题目，用分测验基准值加小扰动。
    difficulty_rng = random.Random(seed + 1000)
    for subtest, items in generated.items():
        if subtest not in DIFFICULTY_PROFILE:
            # 数字广度与算术按结构推算，每题都应已有难度。
            assert all('_difficulty' in item for item in items), subtest
            continue
        base, spread = DIFFICULTY_PROFILE[subtest]
        for item in items:
            if '_difficulty' not in item:
                item['_difficulty'] = round(base + difficulty_rng.uniform(-spread, spread), 2)
    return generated


def main():
    parser = argparse.ArgumentParser(description='生成韦氏题库扩充题目')
    parser.add_argument('--check', action='store_true', help='只校验，不写入题库')
    args = parser.parse_args()

    groups = {
        'A': ('Wechsler.json', 'WechslerIQModel.json', SEED, 'irt-heuristic-v2'),
        'B': ('WechslerB.json', 'WechslerIQModelB.json', SEED + 1, 'irt-heuristic-form-b-v2'),
    }
    bank_version = 'practice-2026-10-22-v4'
    plan = {}
    for group, (filename, model_filename, seed, model_version) in groups.items():
        path = os.path.join(ROOT, filename)
        model_path = os.path.join(ROOT, model_filename)
        bank = json.load(open(path, encoding='utf-8'))
        model = json.load(open(model_path, encoding='utf-8'))
        existing = {item['id'] for item in bank}
        generated = build_for_group(group, seed)
        for subtest, items in generated.items():
            validate(items, subtest)
            prefix = 'b-' if group == 'B' else ''
            used = {item['id'] for item in bank if item['subtest'] == subtest}
            number = len(used)
            for item in items:
                number += 1
                item['id'] = f'{prefix}{subtest}-{number:02d}'
                assert item['id'] not in existing, item['id']
                existing.add(item['id'])
        plan[group] = (path, model_path, bank, model, generated, model_version)

    total = sum(len(items) for _, _, _, _, generated, _ in plan.values() for items in generated.values())
    print(f'校验通过：A 组 {sum(len(i) for i in plan["A"][4].values())} 题，'
          f'B 组 {sum(len(i) for i in plan["B"][4].values())} 题，共 {total} 题')

    if args.check:
        return

    for group, (path, model_path, bank, model, generated, model_version) in plan.items():
        known = {entry['itemID'] for entry in model['items']}
        for subtest, items in generated.items():
            for item in items:
                difficulty = item.pop('_difficulty')
                bank.append(item)
                if item['id'] not in known:
                    # 阈值个数必须与题目的分值结构一致：有 1 分选项的部分得分题用
                    # 两个递增阈值（得满分需要更高能力），其余用单个阈值。
                    if max(item['optionScores']) == 2 and 1 in item['optionScores']:
                        thresholds = [round(difficulty, 2), round(difficulty + 1.0, 2)]
                    else:
                        thresholds = [round(difficulty, 2)]
                    model['items'].append({'itemID': item['id'], 'discrimination': 1.0,
                                           'thresholds': thresholds})
                    known.add(item['id'])
        with open(path, 'w', encoding='utf-8') as handle:
            json.dump(bank, handle, ensure_ascii=False, indent=2)
            handle.write('\n')
        model['bankVersion'] = bank_version
        model['version'] = model_version
        with open(model_path, 'w', encoding='utf-8') as handle:
            json.dump(model, handle, ensure_ascii=False, indent=2)
            handle.write('\n')
        print(f'已写入 {os.path.basename(path)}：{len(bank)} 题；'
              f'{os.path.basename(model_path)}：{len(model["items"])} 项参数（版本 {model_version}）')
        for subtest in sorted(generated):
            count = sum(1 for item in bank if item['subtest'] == subtest)
            print(f'   {subtest:<14}{count} 题')


if __name__ == '__main__':
    main()
