import sys
from collections import namedtuple
from dataclasses import dataclass

SIDES = ('top', 'right', 'bottom', 'left')
BOX_SHORTHANDS = ('margin', 'padding', 'border')
SHORTHAND_PICKS = {1: (0, 0, 0, 0), 2: (0, 1, 0, 1), 3: (0, 1, 2, 1), 4: (0, 1, 2, 3)}
JUSTIFY_WEIGHTS = {'space-between': (0, 1), 'space-around': (1, 2), 'space-evenly': (1, 1)}

Edges = namedtuple('Edges', SIDES)
Area = namedtuple('Area', 'row column row_span column_span')


def is_non_negative(token):
    return 1 <= len(token) <= 3 and token.isdigit()


def is_positive(token):
    return is_non_negative(token) and int(token) > 0


def is_signed(token):
    return is_non_negative(token.removeprefix('-'))


def is_percentage(token):
    return token.endswith('%') and is_non_negative(token[:-1])


def is_fr(token):
    return token.endswith('fr') and is_positive(token[:-2])


def one_of(*options):
    def check(tokens):
        return len(tokens) == 1 and any(
            option(tokens[0]) if callable(option) else option == tokens[0] for option in options
        )

    return check


def is_track_list(tokens):
    return tokens == ['none'] or all(
        token == 'auto' or is_non_negative(token) or is_fr(token) for token in tokens
    )


def is_grid_line(tokens):
    match tokens:
        case ['auto']:
            return True
        case ['span', count]:
            return is_positive(count)
        case [start]:
            return is_positive(start)
        case [start, '/', 'span', count]:
            return is_positive(start) and is_positive(count)
        case [start, '/', end]:
            return is_positive(start) and is_positive(end) and int(start) < int(end)
    return False


SIZE = one_of('auto', is_non_negative, is_percentage)
MIN_SIZE = one_of(is_non_negative, is_percentage)
MAX_SIZE = one_of('none', is_non_negative, is_percentage)
INTEGER = one_of(is_non_negative)

LONGHANDS = {
    'display': ('block', one_of('block', 'flex', 'grid', 'none')),
    'position': ('static', one_of('static', 'relative', 'absolute')),
    'box-sizing': ('content-box', one_of('content-box', 'border-box')),
    'width': ('auto', SIZE),
    'height': ('auto', SIZE),
    'min-width': ('0', MIN_SIZE),
    'min-height': ('0', MIN_SIZE),
    'max-width': ('none', MAX_SIZE),
    'max-height': ('none', MAX_SIZE),
    **{f'margin-{side}': ('0', INTEGER) for side in SIDES},
    **{f'padding-{side}': ('0', INTEGER) for side in SIDES},
    **{f'border-{side}': ('0', one_of('0', '1')) for side in SIDES},
    **{side: ('auto', one_of('auto', is_signed)) for side in SIDES},
    'flex-direction': ('row', one_of('row', 'row-reverse', 'column', 'column-reverse')),
    'flex-wrap': ('nowrap', one_of('nowrap', 'wrap')),
    'justify-content': (
        'start',
        one_of('start', 'end', 'center', 'space-between', 'space-around', 'space-evenly'),
    ),
    'align-items': ('stretch', one_of('stretch', 'start', 'end', 'center')),
    'align-self': ('auto', one_of('auto', 'stretch', 'start', 'end', 'center')),
    'row-gap': ('0', INTEGER),
    'column-gap': ('0', INTEGER),
    'order': ('0', one_of(is_signed)),
    'flex-grow': ('0', INTEGER),
    'flex-shrink': ('1', INTEGER),
    'flex-basis': ('auto', SIZE),
    'grid-template-columns': ('none', is_track_list),
    'grid-template-rows': ('none', is_track_list),
    'grid-column': ('auto', is_grid_line),
    'grid-row': ('auto', is_grid_line),
}
KNOWN_PROPERTIES = {*LONGHANDS, *BOX_SHORTHANDS, 'gap'}


def expand_declaration(prop, value):
    tokens = value.split(' ')
    if prop in LONGHANDS:
        return [(prop, value)] if LONGHANDS[prop][1](tokens) else None
    if prop == 'gap' and len(tokens) <= 2 and all(map(is_non_negative, tokens)):
        return [('row-gap', tokens[0]), ('column-gap', tokens[-1])]
    if prop in BOX_SHORTHANDS and len(tokens) <= 4:
        is_valid = LONGHANDS[f'{prop}-top'][1]
        if all(is_valid([token]) for token in tokens):
            picks = SHORTHAND_PICKS[len(tokens)]
            return [(f'{prop}-{side}', tokens[pick]) for side, pick in zip(SIDES, picks)]
    return None


class Element:
    def __init__(self, type_name, element_id, classes, text, parent):
        self.type_name = type_name
        self.id = element_id
        self.classes = classes
        self.text = text
        self.parent = parent
        self.depth = 0 if parent is None else parent.depth + 1
        self.children = []
        self.style = {prop: initial for prop, (initial, _) in LONGHANDS.items()}
        self.update_style([])
        self.displayed = False
        self.cw = 0
        self.ch = 0
        self.lines = []
        self.rel_x = 0
        self.rel_y = 0
        self.x = 0
        self.y = 0
        if parent is not None:
            parent.children.append(self)

    def update_style(self, declarations):
        self.style.update(declarations)
        self.margin = self.edges('margin')
        self.padding = self.edges('padding')
        self.border = self.edges('border')

    def edges(self, kind):
        return Edges(*(int(self.style[f'{kind}-{side}']) for side in SIDES))

    def number(self, prop):
        return int(self.style[prop])

    def frame(self, horizontal):
        padding, border = self.padding, self.border
        if horizontal:
            return padding.left + padding.right + border.left + border.right
        return padding.top + padding.bottom + border.top + border.bottom

    def outer(self, horizontal):
        if horizontal:
            return self.frame(True) + self.margin.left + self.margin.right
        return self.frame(False) + self.margin.top + self.margin.bottom

    @property
    def border_width(self):
        return self.cw + self.frame(True)

    @property
    def border_height(self):
        return self.ch + self.frame(False)

    def in_flow_children(self):
        return [
            child
            for child in self.children
            if child.displayed and child.style['position'] != 'absolute'
        ]

    def items(self):
        return sorted(self.in_flow_children(), key=lambda child: child.number('order'))

    def place_child(self, child, x, y):
        child.rel_x = self.border.left + self.padding.left + x
        child.rel_y = self.border.top + self.padding.top + y

    def margin_box(self):
        return (
            self.x - self.margin.left,
            self.y - self.margin.top,
            self.cw + self.outer(True),
            self.ch + self.outer(False),
        )

    def border_box(self):
        return self.x, self.y, self.border_width, self.border_height

    def padding_box(self):
        return (
            self.x + self.border.left,
            self.y + self.border.top,
            self.cw + self.padding.left + self.padding.right,
            self.ch + self.padding.top + self.padding.bottom,
        )

    def content_box(self):
        return (
            self.x + self.border.left + self.padding.left,
            self.y + self.border.top + self.padding.top,
            self.cw,
            self.ch,
        )


@dataclass
class FlexItem:
    element: Element
    align: str
    outer: int
    cross: int = 0
    base: int = 0
    hypothetical: int = 0
    size: int = 0


def parse_rule(line):
    selectors, body = line.split(' { ', 1)
    declarations = []
    for declaration in body.removesuffix(' }').split('; '):
        prop, value = declaration.split(': ', 1)
        declarations.extend(expand_declaration(prop, value) or [])
    return selectors.split(', '), declarations


def parse_element(line, stack):
    head = line.lstrip(' ')
    depth = (len(line) - len(head)) // 2
    head, _, text = head.partition(' ')
    type_name, _, names = head.partition('#')
    element_id, *classes = names.split('.')
    del stack[depth:]
    parent = stack[-1] if stack else None
    element = Element(type_name, element_id, classes, text[1:-1] if text else None, parent)
    stack.append(element)
    return element


def selector_specificity(selector, element):
    if selector.startswith('#'):
        return 2 if selector[1:] == element.id else -1
    if selector.startswith('.'):
        return 1 if selector[1:] in element.classes else -1
    return 0 if selector == element.type_name else -1


def cascaded_style(element, rules):
    winners = {}
    for selectors, declarations in rules:
        specificity = max(selector_specificity(selector, element) for selector in selectors)
        if specificity < 0:
            continue
        for prop, value in declarations:
            if prop not in winners or specificity >= winners[prop][0]:
                winners[prop] = (specificity, value)
    return [(prop, value) for prop, (_, value) in winners.items()]


def resolve(element, prop, reference, horizontal):
    value = element.style[prop]
    if value in ('auto', 'none'):
        return None
    if value.endswith('%'):
        if reference is None:
            return None
        result = reference * int(value[:-1]) // 100
    else:
        result = int(value)
    if element.style['box-sizing'] == 'border-box':
        result = max(0, result - element.frame(horizontal))
    return result


def clamp(element, value, horizontal, reference):
    axis = 'width' if horizontal else 'height'
    lower = resolve(element, f'min-{axis}', reference, horizontal) or 0
    upper = resolve(element, f'max-{axis}', reference, horizontal)
    if upper is not None and value > upper:
        value = upper
    return max(value, lower)


def inset(element, side):
    value = element.style[side]
    return None if value == 'auto' else int(value)


def wrap(text, width):
    lines = []
    for word in text.split(' '):
        if lines and len(lines[-1]) + 1 + len(word) <= width:
            lines[-1] += ' ' + word
        else:
            lines.append(word)
    return lines


def distribute(total, weights):
    weight_sum = sum(weights)
    shares = [total * weight // weight_sum for weight in weights]
    remainder = total - sum(shares)
    for index, weight in enumerate(weights):
        if remainder > 0 and weight > 0:
            shares[index] += 1
            remainder -= 1
    return shares


def gap_total(gap, count):
    return gap * max(0, count - 1)


def layout(element, width_ref, height_ref, fixed_width=None, fixed_height=None):
    if fixed_width is None:
        width = resolve(element, 'width', width_ref, True)
        if width is None:
            width = max(0, width_ref - element.outer(True))
        fixed_width = clamp(element, width, True, width_ref)
    if fixed_height is None:
        height = resolve(element, 'height', height_ref, False)
        if height is not None:
            fixed_height = clamp(element, height, False, height_ref)
    element.cw = fixed_width
    display = element.style['display']
    if element.text is not None:
        element.lines = wrap(element.text, fixed_width)
        content_height = len(element.lines)
    elif display == 'flex':
        content_height = flex_layout(element, fixed_width, fixed_height, height_ref)
    elif display == 'grid':
        content_height = grid_layout(element, fixed_width, fixed_height)
    else:
        content_height = block_layout(element, fixed_width, fixed_height)
    if fixed_height is None:
        fixed_height = clamp(element, content_height, False, height_ref)
    element.ch = fixed_height
    return content_height


def block_layout(element, content_width, content_height):
    bottom = 0
    previous_margin = 0
    for child in element.in_flow_children():
        layout(child, content_width, content_height)
        top = bottom + max(previous_margin, child.margin.top)
        element.place_child(child, child.margin.left, top)
        bottom = top + child.border_height
        previous_margin = child.margin.bottom
    return bottom + previous_margin


def item_align(container, item):
    align = item.style['align-self']
    return container.style['align-items'] if align == 'auto' else align


def align_offset(align, free):
    if free > 0 and align == 'end':
        return free
    if free > 0 and align == 'center':
        return free // 2
    return 0


def flex_item(container, element, horizontal, content_width, content_height):
    main_ref = content_width if horizontal else content_height
    item = FlexItem(element, item_align(container, element), element.outer(horizontal))
    if not horizontal:
        room = max(0, content_width - element.outer(True))
        cross = resolve(element, 'width', content_width, True)
        if cross is None:
            cross = room if item.align == 'stretch' else min(max_content_width(element), room)
        item.cross = clamp(element, cross, True, content_width)
    base = resolve(element, 'flex-basis', main_ref, horizontal)
    if base is None:
        base = resolve(element, 'width' if horizontal else 'height', main_ref, horizontal)
    if base is None and horizontal:
        base = max_content_width(element)
    elif base is None:
        base = layout(element, content_width, content_height, item.cross)
    item.base = base
    item.hypothetical = clamp(element, base, horizontal, main_ref)
    return item


def resolve_main_sizes(line, main_length, gap, horizontal, main_ref):
    gaps = gap_total(gap, len(line))
    growing = sum(item.hypothetical + item.outer for item in line) + gaps < main_length
    weights = []
    unfrozen = []
    for index, item in enumerate(line):
        if growing:
            weight = item.element.number('flex-grow')
        else:
            weight = item.element.number('flex-shrink') * item.base
        weights.append(weight)
        item.size = item.hypothetical
        flexible = item.base <= item.hypothetical if growing else item.base >= item.hypothetical
        if weight > 0 and flexible:
            unfrozen.append(index)
    while unfrozen:
        free = main_length - gaps - sum(
            (item.base if index in unfrozen else item.size) + item.outer
            for index, item in enumerate(line)
        )
        amount = max(0, free) if growing else max(0, -free)
        shares = distribute(amount, [weights[index] for index in unfrozen])
        violations = {}
        for index, share in zip(unfrozen, shares):
            item = line[index]
            tentative = item.base + share if growing else item.base - share
            item.size = clamp(item.element, tentative, horizontal, main_ref)
            violations[index] = item.size - tentative
        total = sum(violations.values())
        if total > 0:
            unfrozen = [index for index in unfrozen if violations[index] <= 0]
        elif total < 0:
            unfrozen = [index for index in unfrozen if violations[index] >= 0]
        else:
            unfrozen = []


def justify_spaces(justify, remaining, count):
    spaces = [0] * count
    if remaining <= 0 or justify == 'start':
        return spaces
    if justify == 'end':
        spaces[0] = remaining
    elif justify == 'center':
        spaces[0] = remaining // 2
    else:
        edge, inner = JUSTIFY_WEIGHTS[justify]
        weights = [edge] + [inner] * (count - 1) + [edge]
        if sum(weights) > 0:
            spaces = distribute(remaining, weights)[:count]
    return spaces


def main_positions(line, main_length, gap, justify, reverse, horizontal):
    used = sum(item.size + item.outer for item in line) + gap_total(gap, len(line))
    cursor = main_length if reverse else 0
    positions = []
    for item, space in zip(line, justify_spaces(justify, main_length - used, len(line))):
        length = item.size + item.outer
        if reverse:
            cursor -= space + length
            margin_start = cursor
            cursor -= gap
        else:
            cursor += space
            margin_start = cursor
            cursor += length + gap
        margin = item.element.margin
        positions.append(margin_start + (margin.left if horizontal else margin.top))
    return positions


def flex_layout(container, content_width, content_height, height_ref):
    direction = container.style['flex-direction']
    horizontal = direction in ('row', 'row-reverse')
    row_gap = container.number('row-gap')
    gap = container.number('column-gap') if horizontal else row_gap
    main_ref = content_width if horizontal else content_height
    items = [
        flex_item(container, element, horizontal, content_width, content_height)
        for element in container.items()
    ]

    if horizontal:
        main_length = content_width
    elif content_height is not None:
        main_length = content_height
    else:
        total = sum(item.hypothetical + item.outer for item in items) + gap_total(gap, len(items))
        main_length = clamp(container, total, False, height_ref)

    lines = []
    if horizontal and container.style['flex-wrap'] == 'wrap':
        for item in items:
            if lines:
                used = sum(other.hypothetical + other.outer for other in lines[-1])
                if used + gap * len(lines[-1]) + item.hypothetical + item.outer <= main_length:
                    lines[-1].append(item)
                    continue
            lines.append([item])
    elif items:
        lines.append(items)

    reverse = direction.endswith('-reverse')
    justify = container.style['justify-content']
    cross_start = 0
    line_crosses = []
    for line in lines:
        resolve_main_sizes(line, main_length, gap, horizontal, main_ref)
        if horizontal:
            for item in line:
                layout(item.element, content_width, content_height, item.size)
                item.cross = item.element.ch
            largest = max(item.cross + item.element.outer(False) for item in line)
            if len(lines) > 1:
                line_cross = largest
            elif content_height is not None:
                line_cross = content_height
            else:
                line_cross = clamp(container, largest, False, height_ref)
        else:
            line_cross = content_width

        positions = main_positions(line, main_length, gap, justify, reverse, horizontal)
        for item, main_position in zip(line, positions):
            element = item.element
            if not horizontal:
                layout(element, content_width, content_height, item.cross, item.size)
            elif item.align == 'stretch' and element.style['height'] == 'auto':
                stretched = max(0, line_cross - element.outer(False))
                item.cross = clamp(element, stretched, False, content_height)
                layout(element, content_width, content_height, item.size, item.cross)
            else:
                layout(element, content_width, content_height, item.size)
            free = line_cross - item.cross - element.outer(not horizontal)
            offset = align_offset(item.align, free)
            if horizontal:
                container.place_child(
                    element, main_position, cross_start + offset + element.margin.top
                )
            else:
                container.place_child(
                    element, cross_start + offset + element.margin.left, main_position
                )
        line_crosses.append(line_cross)
        cross_start += line_cross + row_gap

    if horizontal:
        return sum(line_crosses) + gap_total(row_gap, len(line_crosses))
    return main_length


def parse_grid_line(value):
    match value.split(' '):
        case ['auto']:
            return None, 1
        case ['span', count]:
            return None, int(count)
        case [start]:
            return int(start), 1
        case [start, '/', 'span', count]:
            return int(start), int(count)
        case [start, '/', end]:
            return int(start), int(end) - int(start)


def track_specs(container, prop):
    value = container.style[prop]
    return [] if value == 'none' else value.split(' ')


def column_specs(container):
    return track_specs(container, 'grid-template-columns') or ['auto']


def area_cells(row, column, row_span, column_span):
    return {
        (r, c)
        for r in range(row, row + row_span)
        for c in range(column, column + column_span)
    }


def place_grid_items(container, items):
    requests = [
        (*parse_grid_line(item.style['grid-row']), *parse_grid_line(item.style['grid-column']))
        for item in items
    ]
    column_count = max(
        [len(column_specs(container))]
        + [span if start is None else start + span - 1 for _, _, start, span in requests]
    )
    occupied = set()
    areas = [None] * len(items)

    def fits(row, column, row_span, column_span):
        return occupied.isdisjoint(area_cells(row, column, row_span, column_span))

    def occupy(index, row, column):
        _, row_span, _, column_span = requests[index]
        areas[index] = Area(row, column, row_span, column_span)
        occupied.update(area_cells(row, column, row_span, column_span))

    for index, (row, _, column, _) in enumerate(requests):
        if row is not None and column is not None:
            occupy(index, row, column)

    cursor_row, cursor_column = 1, 1
    for index, (row, row_span, column, column_span) in enumerate(requests):
        if row is not None and column is not None:
            continue
        if row is not None:
            candidates = range(1, column_count - column_span + 2)
            column = next(
                (c for c in candidates if fits(row, c, row_span, column_span)),
                1,
            )
        elif column is not None:
            if column < cursor_column:
                cursor_row += 1
            row = cursor_row
            while not fits(row, column, row_span, column_span):
                row += 1
            cursor_row, cursor_column = row, column + column_span
        else:
            row, column = cursor_row, cursor_column
            while column + column_span - 1 > column_count or not fits(
                row, column, row_span, column_span
            ):
                if column + column_span - 1 > column_count:
                    row += 1
                    column = 1
                else:
                    column += 1
            cursor_row, cursor_column = row, column + column_span
        occupy(index, row, column)
    return areas, column_count


def track_sizes(specs, count, available, gap, contributions):
    tracks = specs + ['auto'] * (count - len(specs))
    sizes = []
    for index, spec in enumerate(tracks, 1):
        if spec == 'auto' or (spec.endswith('fr') and available is None):
            sizes.append(
                max(
                    (size for start, span, size in contributions if start == index and span == 1),
                    default=0,
                )
            )
        elif spec.endswith('fr'):
            sizes.append(0)
        else:
            sizes.append(int(spec))
    if available is not None:
        leftover = available - sum(sizes) - gap * (len(tracks) - 1)
        weights = [int(spec[:-2]) if spec.endswith('fr') else 0 for spec in tracks]
        if not any(weights):
            weights = [1 if spec == 'auto' else 0 for spec in tracks]
        if leftover > 0 and any(weights):
            for index, share in enumerate(distribute(leftover, weights)):
                sizes[index] += share
    return sizes


def span_start(sizes, index, gap):
    return sum(sizes[: index - 1]) + gap * (index - 1)


def span_size(sizes, index, span, gap):
    return sum(sizes[index - 1 : index - 1 + span]) + gap * (span - 1)


def grid_layout(container, content_width, content_height):
    items = container.items()
    areas, column_count = place_grid_items(container, items)
    column_gap = container.number('column-gap')
    row_gap = container.number('row-gap')
    column_contributions = [
        (area.column, area.column_span, width_contribution(item))
        for item, area in zip(items, areas)
    ]
    columns = track_sizes(
        column_specs(container), column_count, content_width, column_gap, column_contributions
    )

    widths = []
    row_contributions = []
    for item, area in zip(items, areas):
        area_width = span_size(columns, area.column, area.column_span, column_gap)
        width = resolve(item, 'width', area_width, True)
        if width is None:
            width = max(0, area_width - item.outer(True))
        width = clamp(item, width, True, area_width)
        layout(item, area_width, None, width)
        widths.append((area_width, width))
        row_contributions.append((area.row, area.row_span, item.ch + item.outer(False)))

    row_specs = track_specs(container, 'grid-template-rows')
    row_count = max([len(row_specs)] + [area.row + area.row_span - 1 for area in areas])
    rows = track_sizes(row_specs, row_count, content_height, row_gap, row_contributions)
    for item, area, (area_width, width) in zip(items, areas, widths):
        area_height = span_size(rows, area.row, area.row_span, row_gap)
        align = item_align(container, item)
        if align == 'stretch' and item.style['height'] == 'auto':
            stretched = max(0, area_height - item.outer(False))
            height = clamp(item, stretched, False, area_height)
            layout(item, area_width, area_height, width, height)
        else:
            layout(item, area_width, area_height, width)
        offset = align_offset(align, area_height - item.ch - item.outer(False))
        container.place_child(
            item,
            span_start(columns, area.column, column_gap) + item.margin.left,
            span_start(rows, area.row, row_gap) + offset + item.margin.top,
        )
    return sum(rows) + gap_total(row_gap, row_count)


def max_content_width(element):
    if element.text is not None:
        return len(element.text)
    children = element.in_flow_children()
    display = element.style['display']
    gap = element.number('column-gap')
    if display == 'flex' and element.style['flex-direction'] in ('row', 'row-reverse'):
        return sum(map(width_contribution, children)) + gap_total(gap, len(children))
    if display == 'grid':
        items = element.items()
        areas, column_count = place_grid_items(element, items)
        contributions = [
            (area.column, area.column_span, width_contribution(item))
            for item, area in zip(items, areas)
        ]
        sizes = track_sizes(column_specs(element), column_count, None, gap, contributions)
        return sum(sizes) + gap_total(gap, column_count)
    return max(map(width_contribution, children), default=0)


def width_contribution(element):
    width = resolve(element, 'width', None, True)
    if width is None:
        width = max_content_width(element)
    return clamp(element, width, True, None) + element.outer(True)


def positioned_ancestor(element):
    ancestor = element.parent
    while ancestor is not None and ancestor.style['position'] == 'static':
        ancestor = ancestor.parent
    return ancestor


def absolute_offset(start, end, margin_start, margin_end, free):
    if start is not None:
        return start + margin_start
    if end is not None:
        return free - end - margin_end
    return margin_start


def relative_shift(start, end):
    if start is not None:
        return start
    if end is not None:
        return -end
    return 0


def layout_absolute(element, viewport_width, viewport_height):
    block = positioned_ancestor(element)
    if block is None:
        block_width, block_height = viewport_width, viewport_height
    else:
        _, _, block_width, block_height = block.padding_box()
    top, right, bottom, left = (inset(element, side) for side in SIDES)

    width = resolve(element, 'width', block_width, True)
    if width is None:
        room = max(0, block_width - (left or 0) - (right or 0) - element.outer(True))
        if left is not None and right is not None:
            width = room
        else:
            width = min(max_content_width(element), room)
    width = clamp(element, width, True, block_width)
    height = None
    if element.style['height'] == 'auto' and top is not None and bottom is not None:
        room = max(0, block_height - top - bottom - element.outer(False))
        height = clamp(element, room, False, block_height)
    layout(element, block_width, block_height, width, height)

    margin = element.margin
    element.rel_x = absolute_offset(
        left, right, margin.left, margin.right, block_width - element.border_width
    )
    element.rel_y = absolute_offset(
        top, bottom, margin.top, margin.bottom, block_height - element.border_height
    )


def finalize_position(element):
    position = element.style['position']
    if position == 'absolute':
        block = positioned_ancestor(element)
        origin_x, origin_y = (0, 0) if block is None else block.padding_box()[:2]
    elif element.parent is None:
        origin_x, origin_y = 0, 0
    else:
        origin_x, origin_y = element.parent.x, element.parent.y
    element.x = origin_x + element.rel_x
    element.y = origin_y + element.rel_y
    if position == 'relative':
        top, right, bottom, left = (inset(element, side) for side in SIDES)
        element.x += relative_shift(left, right)
        element.y += relative_shift(top, bottom)


def contains(box, x, y):
    left, top, width, height = box
    return left <= x < left + width and top <= y < top + height


def overflows(element):
    if element.text is not None:
        longest = max(map(len, element.lines))
        return longest > element.cw or len(element.lines) > element.ch
    left, top, width, height = element.content_box()
    for child in element.in_flow_children():
        x, y, w, h = child.margin_box()
        if x < left or y < top or x + w > left + width or y + h > top + height:
            return True
    return False


def format_box(box):
    return ' '.join(map(str, box))


class Document:
    def __init__(self, width, height, elements):
        self.width = width
        self.height = height
        self.elements = elements
        self.by_id = {element.id: element for element in elements}
        self.perform_layout()

    def perform_layout(self):
        for element in self.elements:
            parent_displayed = element.parent is None or element.parent.displayed
            element.displayed = parent_displayed and element.style['display'] != 'none'
        root = self.elements[0]
        if root.displayed and root.style['position'] != 'absolute':
            layout(root, self.width, self.height)
            root.rel_x, root.rel_y = root.margin.left, root.margin.top
        for element in self.elements:
            if element.displayed and element.style['position'] == 'absolute':
                layout_absolute(element, self.width, self.height)
        for element in self.elements:
            if element.displayed:
                finalize_position(element)

    def snapshot(self):
        return [element.border_box() if element.displayed else None for element in self.elements]

    def changes(self, before):
        after = self.snapshot()
        changed = [
            element.id for element, old, new in zip(self.elements, before, after) if old != new
        ]
        return ' '.join(changed) or 'no change'

    def execute(self, line):
        name, *args = line.split(' ', 3)
        match name:
            case 'LAYOUT':
                return self.report_layout()
            case 'BOX':
                return self.report_box(args[0])
            case 'RENDER':
                return self.render()
            case 'HIT':
                return self.hit(int(args[0]), int(args[1]))
            case 'SET':
                return self.set_property(*args)
            case 'VIEWPORT':
                return self.resize(int(args[0]), int(args[1]))
            case 'OVERFLOW':
                return self.report_overflow()
        return [f'error: unknown command {name}']

    def report_layout(self):
        lines = [f'layout {self.width}x{self.height}']
        for element in self.elements:
            indent = '  ' * element.depth
            box = format_box(element.border_box()) if element.displayed else 'none'
            lines.append(f'{indent}{element.id} {box}')
        return lines

    def report_box(self, element_id):
        element = self.by_id.get(element_id)
        if element is None:
            return [f'error: unknown element {element_id}']
        if not element.displayed:
            return [f'box {element_id}: none']
        return [
            f'box {element_id}',
            f'margin {format_box(element.margin_box())}',
            f'border {format_box(element.border_box())}',
            f'padding {format_box(element.padding_box())}',
            f'content {format_box(element.content_box())}',
        ]

    def render(self):
        screen = [['.'] * self.width for _ in range(self.height)]
        for element in self.elements:
            if element.displayed:
                self.draw(screen, element)
        edge = '#' * (self.width + 2)
        rows = ['#' + ''.join(row) + '#' for row in screen]
        return [f'render {self.width}x{self.height}', edge, *rows, edge]

    def draw(self, screen, element):
        left, top, width, height = element.border_box()
        right, bottom = left + width - 1, top + height - 1
        border = element.border
        for y in range(max(top, 0), min(bottom + 1, self.height)):
            for x in range(max(left, 0), min(right + 1, self.width)):
                on_row = (border.top and y == top) or (border.bottom and y == bottom)
                on_column = (border.left and x == left) or (border.right and x == right)
                if on_row and on_column:
                    screen[y][x] = '+'
                elif on_row:
                    screen[y][x] = '-'
                elif on_column:
                    screen[y][x] = '|'
                else:
                    screen[y][x] = ' '
        if element.text is not None:
            text_left, text_top, _, _ = element.content_box()
            for row, text_line in enumerate(element.lines):
                for column, char in enumerate(text_line):
                    x, y = text_left + column, text_top + row
                    if 0 <= x < self.width and 0 <= y < self.height:
                        screen[y][x] = char

    def hit(self, x, y):
        if x >= self.width or y >= self.height:
            return [f'error: point {x} {y} outside viewport']
        target = None
        for element in self.elements:
            if element.displayed and contains(element.border_box(), x, y):
                target = element
        if target is None:
            return [f'hit {x} {y}: none']
        path = []
        while target is not None:
            path.append(target.id)
            target = target.parent
        return [f'hit {x} {y}: ' + ' > '.join(reversed(path))]

    def set_property(self, element_id, prop, value):
        element = self.by_id.get(element_id)
        if element is None:
            return [f'error: unknown element {element_id}']
        if prop not in KNOWN_PROPERTIES:
            return [f'error: unknown property {prop}']
        declarations = expand_declaration(prop, value)
        if declarations is None:
            return [f'error: invalid value for {prop}: {value}']
        before = self.snapshot()
        element.update_style(declarations)
        self.perform_layout()
        return [f'set {element_id} {prop} {value}: {self.changes(before)}']

    def resize(self, width, height):
        if not (1 <= width <= 80 and 1 <= height <= 40):
            return [f'error: invalid viewport {width} {height}']
        before = self.snapshot()
        self.width = width
        self.height = height
        self.perform_layout()
        return [f'viewport {width} {height}: {self.changes(before)}']

    def report_overflow(self):
        overflowing = [
            element.id for element in self.elements if element.displayed and overflows(element)
        ]
        return ['overflow: ' + (' '.join(overflowing) or 'none')]


def main():
    lines = iter(sys.stdin.read().splitlines())
    width, height = map(int, next(lines).split())
    rules = [parse_rule(line) for line in iter(lines.__next__, '---')]
    stack = []
    elements = [parse_element(line, stack) for line in iter(lines.__next__, '===')]
    for element in elements:
        element.update_style(cascaded_style(element, rules))
    document = Document(width, height, elements)
    for line in iter(lines.__next__, 'END'):
        print('\n'.join(document.execute(line)))


if __name__ == '__main__':
    main()
