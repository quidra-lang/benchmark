import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from functools import cmp_to_key

RESERVED_WORDS = frozenset('''
    SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING
    ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE
    TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE
    COUNT SUM MIN MAX AVG EXIT
'''.split())
AGGREGATE_NAMES = ('COUNT', 'SUM', 'MIN', 'MAX', 'AVG')
COMPARISON_OPERATORS = ('=', '<>', '!=', '<', '<=', '>', '>=')

TOKEN_PATTERN = re.compile(r"""
    (?P<space>[ \n]+)
    | (?P<comment>--[^\n]*)
    | '(?P<string>[^']*)'
    | (?P<integer>[0-9]+)
    | (?P<word>[A-Za-z_][A-Za-z0-9_]*)
    | (?P<symbol><>|!=|<=|>=|\|\||[(),.;*/%+\-=<>])
""", re.VERBOSE)
STATEMENT_PATTERN = re.compile(r"'[^']*'|--[^\n]*|;")


class SqlError(Exception):
    pass


@dataclass
class Token:
    kind: str
    value: object
    text: str


@dataclass
class Literal:
    value: object


@dataclass
class ColumnRef:
    table: str | None
    column: str
    text: str
    index: int = -1


@dataclass
class Unary:
    operator: str
    operand: object


@dataclass
class Binary:
    operator: str
    left: object
    right: object


@dataclass
class IsNull:
    operand: object
    negated: bool


@dataclass
class InList:
    operand: object
    items: list
    negated: bool


@dataclass
class Between:
    operand: object
    low: object
    high: object
    negated: bool


@dataclass
class Like:
    operand: object
    pattern: object
    negated: bool


@dataclass
class Aggregate:
    name: str
    argument: object
    distinct: bool


@dataclass
class ColumnDef:
    name: str
    type: str
    primary_keys: int
    not_null: bool


@dataclass
class CreateTable:
    name: str
    columns: list


@dataclass
class DropTable:
    name: str


@dataclass
class Insert:
    table: str
    columns: list | None
    tuples: list


@dataclass
class Update:
    table: str
    assignments: list
    where: object


@dataclass
class Delete:
    table: str
    where: object


@dataclass
class TableRef:
    name: str
    alias: str | None

    @property
    def scope_name(self):
        return self.alias or self.name


@dataclass
class Join:
    table: TableRef
    left_outer: bool
    condition: object


@dataclass
class SelectItem:
    expr: object
    alias: str | None
    heading: str


@dataclass
class OrderItem:
    expr: object
    tokens: list
    descending: bool


@dataclass
class Select:
    distinct: bool
    items: list | None
    source: TableRef
    joins: list
    where: object
    group_by: list
    having: object
    order_by: list
    limit: int | None
    offset: int | None


class Exit:
    pass


def split_statements(source):
    statements = []
    start = 0
    for found in STATEMENT_PATTERN.finditer(source):
        if found.group() == ';':
            statements.append(source[start:found.end()])
            start = found.end()
    return statements


def tokenize(text):
    tokens = []
    position = 0
    while position < len(text):
        found = TOKEN_PATTERN.match(text, position)
        if found is None:
            raise SqlError(f"unexpected character '{text[position]}'")
        position = found.end()
        written = found.group()
        match found.lastgroup:
            case 'string':
                tokens.append(Token('string', found.group('string'), written))
            case 'integer':
                tokens.append(Token('integer', int(written), written))
            case 'word' if written.upper() in RESERVED_WORDS:
                tokens.append(Token('keyword', written.upper(), written))
            case 'word':
                tokens.append(Token('name', written, written))
            case 'symbol':
                tokens.append(Token('symbol', written, written))
    return tokens


def written_form(tokens):
    text = tokens[0].text
    for previous, token in zip(tokens, tokens[1:]):
        if previous.kind != 'symbol' and token.kind != 'symbol':
            text += ' '
        text += token.text
    return text


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0

    def peek(self):
        return self.tokens[self.position]

    def advance(self):
        token = self.tokens[self.position]
        self.position += 1
        return token

    def at(self, *values):
        token = self.peek()
        return token.kind in ('keyword', 'symbol') and token.value in values

    def accept(self, value):
        if self.at(value):
            self.position += 1
            return True
        return False

    def expect(self, value):
        if not self.accept(value):
            raise self.syntax_error()

    def expect_kind(self, kind):
        if self.peek().kind != kind:
            raise self.syntax_error()
        return self.advance().value

    def syntax_error(self):
        return SqlError(f"syntax error at '{self.peek().text}'")

    def comma_list(self, parse_item):
        items = [parse_item()]
        while self.accept(','):
            items.append(parse_item())
        return items

    def parenthesized_list(self, parse_item):
        self.expect('(')
        items = self.comma_list(parse_item)
        self.expect(')')
        return items

    def parse_statement(self):
        statement = None
        if self.accept('CREATE'):
            statement = self.parse_create_table()
        elif self.accept('DROP'):
            self.expect('TABLE')
            statement = DropTable(self.expect_kind('name'))
        elif self.accept('INSERT'):
            statement = self.parse_insert()
        elif self.accept('UPDATE'):
            statement = self.parse_update()
        elif self.accept('DELETE'):
            self.expect('FROM')
            table = self.expect_kind('name')
            statement = Delete(table, self.parse_clause('WHERE'))
        elif self.accept('SELECT'):
            statement = self.parse_select()
        elif self.accept('EXIT'):
            statement = Exit()
        self.expect(';')
        return statement

    def parse_create_table(self):
        self.expect('TABLE')
        name = self.expect_kind('name')
        return CreateTable(name, self.parenthesized_list(self.parse_column_def))

    def parse_column_def(self):
        name = self.expect_kind('name')
        if not self.at('INT', 'TEXT'):
            raise self.syntax_error()
        column_type = self.advance().value
        primary_keys = 0
        not_null = False
        while True:
            if self.accept('PRIMARY'):
                self.expect('KEY')
                primary_keys += 1
            elif self.accept('NOT'):
                self.expect('NULL')
                not_null = True
            else:
                return ColumnDef(name, column_type, primary_keys, not_null)

    def parse_insert(self):
        self.expect('INTO')
        table = self.expect_kind('name')
        columns = None
        if self.at('('):
            columns = self.parenthesized_list(lambda: self.expect_kind('name'))
        self.expect('VALUES')
        tuples = self.comma_list(lambda: self.parenthesized_list(self.parse_expr))
        return Insert(table, columns, tuples)

    def parse_update(self):
        table = self.expect_kind('name')
        self.expect('SET')
        assignments = self.comma_list(self.parse_assignment)
        return Update(table, assignments, self.parse_clause('WHERE'))

    def parse_assignment(self):
        column = self.expect_kind('name')
        self.expect('=')
        return column, self.parse_expr()

    def parse_clause(self, keyword):
        return self.parse_expr() if self.accept(keyword) else None

    def parse_select(self):
        distinct = self.accept('DISTINCT')
        items = None if self.accept('*') else self.comma_list(self.parse_select_item)
        self.expect('FROM')
        source = self.parse_table_ref()
        joins = []
        while self.at('JOIN', 'INNER', 'LEFT'):
            joins.append(self.parse_join())
        where = self.parse_clause('WHERE')
        group_by = []
        if self.accept('GROUP'):
            self.expect('BY')
            group_by = self.comma_list(self.parse_column_ref)
        having = self.parse_clause('HAVING')
        order_by = []
        if self.accept('ORDER'):
            self.expect('BY')
            order_by = self.comma_list(self.parse_order_item)
        limit = offset = None
        if self.accept('LIMIT'):
            limit = self.expect_kind('integer')
            if self.accept('OFFSET'):
                offset = self.expect_kind('integer')
        return Select(distinct, items, source, joins, where, group_by, having, order_by,
                      limit, offset)

    def parse_alias(self):
        if self.accept('AS'):
            return self.expect_kind('name')
        if self.peek().kind == 'name':
            return self.advance().value
        return None

    def parse_expr_tokens(self):
        start = self.position
        expr = self.parse_expr()
        return expr, self.tokens[start:self.position]

    def parse_select_item(self):
        expr, tokens = self.parse_expr_tokens()
        alias = self.parse_alias()
        if alias is not None:
            heading = alias
        elif isinstance(expr, ColumnRef) and tokens[0].kind == 'name':
            heading = expr.column
        else:
            heading = written_form(tokens)
        return SelectItem(expr, alias, heading)

    def parse_table_ref(self):
        name = self.expect_kind('name')
        return TableRef(name, self.parse_alias())

    def parse_join(self):
        left_outer = self.accept('LEFT')
        if left_outer:
            self.accept('OUTER')
        else:
            self.accept('INNER')
        self.expect('JOIN')
        table = self.parse_table_ref()
        self.expect('ON')
        return Join(table, left_outer, self.parse_expr())

    def parse_order_item(self):
        expr, tokens = self.parse_expr_tokens()
        descending = self.accept('DESC')
        if not descending:
            self.accept('ASC')
        return OrderItem(expr, tokens, descending)

    def parse_column_ref(self):
        name = self.expect_kind('name')
        if self.accept('.'):
            column = self.expect_kind('name')
            return ColumnRef(name, column, f'{name}.{column}')
        return ColumnRef(None, name, name)

    def parse_binary(self, operators, parse_operand):
        expr = parse_operand()
        while self.at(*operators):
            operator = self.advance().value
            expr = Binary(operator, expr, parse_operand())
        return expr

    def parse_expr(self):
        return self.parse_binary(('OR',), self.parse_and)

    def parse_and(self):
        return self.parse_binary(('AND',), self.parse_not)

    def parse_not(self):
        if self.accept('NOT'):
            return Unary('NOT', self.parse_not())
        return self.parse_comparison()

    def parse_comparison(self):
        left = self.parse_additive()
        if self.at(*COMPARISON_OPERATORS):
            operator = self.advance().value
            return Binary(operator, left, self.parse_additive())
        if self.accept('IS'):
            negated = self.accept('NOT')
            self.expect('NULL')
            return IsNull(left, negated)
        negated = self.accept('NOT')
        if self.accept('IN'):
            return InList(left, self.parenthesized_list(self.parse_expr), negated)
        if self.accept('BETWEEN'):
            low = self.parse_additive()
            self.expect('AND')
            return Between(left, low, self.parse_additive(), negated)
        if self.accept('LIKE'):
            return Like(left, self.parse_additive(), negated)
        if negated:
            raise self.syntax_error()
        return left

    def parse_additive(self):
        return self.parse_binary(('+', '-', '||'), self.parse_multiplicative)

    def parse_multiplicative(self):
        return self.parse_binary(('*', '/', '%'), self.parse_unary)

    def parse_unary(self):
        if self.accept('-'):
            return Unary('-', self.parse_unary())
        return self.parse_primary()

    def parse_primary(self):
        token = self.peek()
        if token.kind in ('integer', 'string'):
            self.advance()
            return Literal(token.value)
        if self.accept('NULL'):
            return Literal(None)
        if token.kind == 'name':
            return self.parse_column_ref()
        if self.at(*AGGREGATE_NAMES):
            return self.parse_aggregate()
        if self.accept('('):
            expr = self.parse_expr()
            self.expect(')')
            return expr
        raise self.syntax_error()

    def parse_aggregate(self):
        name = self.advance().value
        self.expect('(')
        if name == 'COUNT' and self.accept('*'):
            argument = None
            distinct = False
        else:
            distinct = self.accept('DISTINCT')
            argument = self.parse_expr()
        self.expect(')')
        return Aggregate(name, argument, distinct)


@dataclass
class Column:
    name: str
    type: str
    not_null: bool


@dataclass
class Table:
    name: str
    columns: list
    primary_key: int | None
    rows: list = field(default_factory=list)

    def column_index(self, name):
        for index, column in enumerate(self.columns):
            if column.name == name:
                return index
        return None


@dataclass
class ScopeEntry:
    name: str
    table: Table
    offset: int


class Scope:
    def __init__(self):
        self.entries = []
        self.width = 0

    def add(self, name, table):
        if any(entry.name == name for entry in self.entries):
            raise SqlError(f'duplicate table name {name}')
        self.entries.append(ScopeEntry(name, table, self.width))
        self.width += len(table.columns)

    def resolve(self, ref):
        entries = self.entries
        if ref.table is not None:
            entries = [entry for entry in entries if entry.name == ref.table]
            if not entries:
                raise SqlError(f'unknown table {ref.table}')
        candidates = []
        for entry in entries:
            index = entry.table.column_index(ref.column)
            if index is not None:
                candidates.append((entry, index))
        if not candidates:
            raise SqlError(f'unknown column {ref.text}')
        if len(candidates) > 1:
            raise SqlError(f'ambiguous column {ref.column}')
        entry, index = candidates[0]
        ref.index = entry.offset + index
        return entry.table.columns[index].type


@dataclass
class CheckContext:
    scope: Scope
    allow_aggregates: bool = False
    grouping: list | None = None


def table_scope(table):
    scope = Scope()
    scope.add(table.name, table)
    return scope


def compatible(first, second):
    return first == second or 'NULL' in (first, second)


def require(actual, expected, operator):
    if not compatible(actual, expected):
        raise SqlError(f'type mismatch for {operator}')


def check(expr, context, in_aggregate=False):
    match expr:
        case Literal(value=None):
            return 'NULL'
        case Literal(value=int()):
            return 'INT'
        case Literal():
            return 'TEXT'
        case ColumnRef():
            column_type = context.scope.resolve(expr)
            grouping = context.grouping
            if grouping is not None and not in_aggregate and expr.index not in grouping:
                raise SqlError(f'column {expr.text} is not grouped')
            return column_type
        case Unary():
            require(check(expr.operand, context, in_aggregate), 'INT', expr.operator)
            return 'INT'
        case Binary():
            left = check(expr.left, context, in_aggregate)
            right = check(expr.right, context, in_aggregate)
            if expr.operator in COMPARISON_OPERATORS:
                require(left, right, expr.operator)
                return 'INT'
            operand_type = 'TEXT' if expr.operator == '||' else 'INT'
            require(left, operand_type, expr.operator)
            require(right, operand_type, expr.operator)
            return operand_type
        case IsNull():
            check(expr.operand, context, in_aggregate)
            return 'INT'
        case InList():
            operand_type = check(expr.operand, context, in_aggregate)
            item_types = [check(item, context, in_aggregate) for item in expr.items]
            for item_type in item_types:
                require(item_type, operand_type, 'IN')
            return 'INT'
        case Between():
            operand_type = check(expr.operand, context, in_aggregate)
            low_type = check(expr.low, context, in_aggregate)
            high_type = check(expr.high, context, in_aggregate)
            require(low_type, operand_type, 'BETWEEN')
            require(high_type, operand_type, 'BETWEEN')
            return 'INT'
        case Like():
            operand_type = check(expr.operand, context, in_aggregate)
            pattern_type = check(expr.pattern, context, in_aggregate)
            require(operand_type, 'TEXT', 'LIKE')
            require(pattern_type, 'TEXT', 'LIKE')
            return 'INT'
        case Aggregate():
            if not context.allow_aggregates or in_aggregate:
                raise SqlError(f'misuse of aggregate {expr.name}')
            if expr.argument is None:
                return 'INT'
            argument_type = check(expr.argument, context, True)
            if expr.name in ('SUM', 'AVG'):
                require(argument_type, 'INT', expr.name)
            return argument_type if expr.name in ('MIN', 'MAX') else 'INT'


def check_condition(condition, context, clause):
    if condition is not None:
        require(check(condition, context), 'INT', clause)


def subexpressions(expr):
    match expr:
        case Unary() | IsNull():
            return [expr.operand]
        case Binary():
            return [expr.left, expr.right]
        case InList():
            return [expr.operand, *expr.items]
        case Between():
            return [expr.operand, expr.low, expr.high]
        case Like():
            return [expr.operand, expr.pattern]
    return []


def contains_aggregate(expr):
    return isinstance(expr, Aggregate) or any(map(contains_aggregate, subexpressions(expr)))


def resolve_order_key(order_item, items, context):
    tokens = order_item.tokens
    if len(tokens) == 1 and tokens[0].kind == 'integer':
        position = tokens[0].value
        if not 1 <= position <= len(items):
            raise SqlError(f'ORDER BY position {position} is out of range')
        return items[position - 1].expr
    if len(tokens) == 1 and tokens[0].kind == 'name':
        for item in items:
            if item.alias == tokens[0].value:
                return item.expr
    check(order_item.expr, context)
    return order_item.expr


def is_true(value):
    return value is not None and value != 0


def logical_not(value):
    return None if value is None else int(value == 0)


def logical_and(left, right):
    if left == 0 or right == 0:
        return 0
    if left is None or right is None:
        return None
    return 1


def logical_or(left, right):
    if is_true(left) or is_true(right):
        return 1
    if left is None or right is None:
        return None
    return 0


def negate_if(negated, value):
    return logical_not(value) if negated else value


def divide(left, right):
    quotient = abs(left) // abs(right)
    return quotient if (left < 0) == (right < 0) else -quotient


def apply_operator(operator, left, right):
    if operator == 'AND':
        return logical_and(left, right)
    if operator == 'OR':
        return logical_or(left, right)
    if left is None or right is None:
        return None
    match operator:
        case '+' | '||':
            return left + right
        case '-':
            return left - right
        case '*':
            return left * right
        case '/':
            return None if right == 0 else divide(left, right)
        case '%':
            return None if right == 0 else left - right * divide(left, right)
        case '=':
            return int(left == right)
        case '<>' | '!=':
            return int(left != right)
        case '<':
            return int(left < right)
        case '<=':
            return int(left <= right)
        case '>':
            return int(left > right)
        case '>=':
            return int(left >= right)


def like_match(text, pattern):
    matched = [True] + [False] * len(text)
    for symbol in pattern:
        if symbol == '%':
            for index in range(1, len(text) + 1):
                matched[index] = matched[index] or matched[index - 1]
        else:
            for index in range(len(text), 0, -1):
                matched[index] = matched[index - 1] and symbol in ('_', text[index - 1])
            matched[0] = False
    return matched[-1]


def evaluate(expr, row, group=None):
    match expr:
        case Literal():
            return expr.value
        case ColumnRef():
            return row[expr.index]
        case Unary(operator='-'):
            value = evaluate(expr.operand, row, group)
            return None if value is None else -value
        case Unary():
            return logical_not(evaluate(expr.operand, row, group))
        case Binary():
            left = evaluate(expr.left, row, group)
            right = evaluate(expr.right, row, group)
            return apply_operator(expr.operator, left, right)
        case IsNull():
            is_null = evaluate(expr.operand, row, group) is None
            return int(is_null != expr.negated)
        case InList():
            value = evaluate(expr.operand, row, group)
            items = [evaluate(item, row, group) for item in expr.items]
            if value is None:
                result = None
            elif value in items:
                result = 1
            else:
                result = None if None in items else 0
            return negate_if(expr.negated, result)
        case Between():
            value = evaluate(expr.operand, row, group)
            low = apply_operator('>=', value, evaluate(expr.low, row, group))
            high = apply_operator('<=', value, evaluate(expr.high, row, group))
            return negate_if(expr.negated, logical_and(low, high))
        case Like():
            text = evaluate(expr.operand, row, group)
            pattern = evaluate(expr.pattern, row, group)
            if text is None or pattern is None:
                return None
            return negate_if(expr.negated, int(like_match(text, pattern)))
        case Aggregate():
            return evaluate_aggregate(expr, group)


def evaluate_aggregate(aggregate, group):
    if aggregate.argument is None:
        return len(group)
    values = [evaluate(aggregate.argument, row) for row in group]
    values = [value for value in values if value is not None]
    if aggregate.distinct:
        values = list(dict.fromkeys(values))
    if aggregate.name == 'COUNT':
        return len(values)
    if not values:
        return None
    match aggregate.name:
        case 'SUM':
            return sum(values)
        case 'MIN':
            return min(values)
        case 'MAX':
            return max(values)
        case 'AVG':
            return divide(sum(values), len(values))


def satisfies(condition, row, group=None):
    return condition is None or is_true(evaluate(condition, row, group))


def join_rows(rows, table, join):
    joined = []
    padding = [None] * len(table.columns)
    for left in rows:
        matched = False
        for right in table.rows:
            combined = left + right
            if is_true(evaluate(join.condition, combined)):
                joined.append(combined)
                matched = True
        if join.left_outer and not matched:
            joined.append(left + padding)
    return joined


def group_rows(rows, grouping):
    groups = {}
    for row in rows:
        groups.setdefault(tuple(row[index] for index in grouping), []).append(row)
    return list(groups.values())


def compare_values(first, second):
    if first is None or second is None:
        return (first is not None) - (second is not None)
    return (first > second) - (first < second)


def compare_keys(first, second, descending):
    for first_key, second_key, reverse in zip(first, second, descending):
        result = compare_values(first_key, second_key)
        if result != 0:
            return -result if reverse else result
    return 0


@dataclass
class ResultRow:
    values: list
    keys: list


def format_value(value):
    return 'NULL' if value is None else str(value)


def count_rows(count):
    return '1 row' if count == 1 else f'{count} rows'


def print_table(headings, types, rows):
    cells = [[format_value(value) for value in row] for row in rows]
    widths = [max([len(heading)] + [len(line[index]) for line in cells])
              for index, heading in enumerate(headings)]
    separator = '+' + ''.join('-' * (width + 2) + '+' for width in widths)
    print(separator)
    print('|' + ''.join(f' {heading.ljust(width)} |' for heading, width in zip(headings, widths)))
    print(separator)
    for line in cells:
        padded = [cell.rjust(width) if column_type == 'INT' else cell.ljust(width)
                  for cell, width, column_type in zip(line, widths, types)]
        print('|' + ''.join(f' {cell} |' for cell in padded))
    print(separator)
    print(f'({count_rows(len(rows))})')


def column_indices(table, names):
    indices = []
    for name in names:
        index = table.column_index(name)
        if index is None:
            raise SqlError(f'unknown column {name}')
        if index in indices:
            raise SqlError(f'duplicate column {name}')
        indices.append(index)
    return indices


def check_constraints(table, rows, checked):
    key = table.primary_key
    key_counts = Counter(row[key] for row in rows) if key is not None else Counter()
    for position in checked:
        row = rows[position]
        for column, value in zip(table.columns, row):
            if column.not_null and value is None:
                raise SqlError(f'NULL value in column {column.name}')
        if key is not None and key_counts[row[key]] > 1:
            raise SqlError(f'duplicate primary key {format_value(row[key])}')


class Database:
    def __init__(self):
        self.tables = {}

    def table(self, name):
        if name not in self.tables:
            raise SqlError(f'unknown table {name}')
        return self.tables[name]

    def execute(self, statement):
        match statement:
            case CreateTable():
                self.create_table(statement)
            case DropTable():
                self.table(statement.name)
                del self.tables[statement.name]
                print(f'Table {statement.name} dropped.')
            case Insert():
                self.insert(statement)
            case Update():
                self.update(statement)
            case Delete():
                self.delete(statement)
            case Select():
                self.select(statement)

    def create_table(self, statement):
        if statement.name in self.tables:
            raise SqlError(f'table {statement.name} already exists')
        columns = []
        primary_key = None
        primary_key_count = 0
        for definition in statement.columns:
            if any(column.name == definition.name for column in columns):
                raise SqlError(f'duplicate column {definition.name}')
            primary_key_count += definition.primary_keys
            if primary_key_count >= 2:
                raise SqlError('multiple primary keys')
            if definition.primary_keys:
                primary_key = len(columns)
            not_null = definition.not_null or definition.primary_keys > 0
            columns.append(Column(definition.name, definition.type, not_null))
        self.tables[statement.name] = Table(statement.name, columns, primary_key)
        print(f'Table {statement.name} created.')

    def insert(self, statement):
        table = self.table(statement.table)
        if statement.columns is None:
            targets = list(range(len(table.columns)))
        else:
            targets = column_indices(table, statement.columns)
        context = CheckContext(Scope())
        for values in statement.tuples:
            if len(values) != len(targets):
                raise SqlError(f'expected {len(targets)} values, got {len(values)}')
            for expr, index in zip(values, targets):
                column = table.columns[index]
                require(check(expr, context), column.type, f'column {column.name}')
        new_rows = []
        for values in statement.tuples:
            row = [None] * len(table.columns)
            for expr, index in zip(values, targets):
                row[index] = evaluate(expr, [])
            new_rows.append(row)
        rows = table.rows + new_rows
        check_constraints(table, rows, range(len(table.rows), len(rows)))
        table.rows = rows
        print(f'{count_rows(len(new_rows))} inserted.')

    def update(self, statement):
        table = self.table(statement.table)
        targets = column_indices(table, [column for column, _ in statement.assignments])
        context = CheckContext(table_scope(table))
        for (_, expr), index in zip(statement.assignments, targets):
            column = table.columns[index]
            require(check(expr, context), column.type, f'column {column.name}')
        check_condition(statement.where, context, 'WHERE')
        rows = list(table.rows)
        updated = []
        for position, row in enumerate(table.rows):
            if satisfies(statement.where, row):
                new_row = list(row)
                for (_, expr), index in zip(statement.assignments, targets):
                    new_row[index] = evaluate(expr, row)
                rows[position] = new_row
                updated.append(position)
        check_constraints(table, rows, updated)
        table.rows = rows
        print(f'{count_rows(len(updated))} updated.')

    def delete(self, statement):
        table = self.table(statement.table)
        check_condition(statement.where, CheckContext(table_scope(table)), 'WHERE')
        kept = [row for row in table.rows if not satisfies(statement.where, row)]
        deleted = len(table.rows) - len(kept)
        table.rows = kept
        print(f'{count_rows(deleted)} deleted.')

    def select(self, query):
        scope = Scope()
        scope.add(query.source.scope_name, self.table(query.source.name))
        for join in query.joins:
            scope.add(join.table.scope_name, self.table(join.table.name))
            check_condition(join.condition, CheckContext(scope), 'ON')
        check_condition(query.where, CheckContext(scope), 'WHERE')
        for ref in query.group_by:
            scope.resolve(ref)
        items = query.items
        if items is None:
            items = [SelectItem(ColumnRef(entry.name, column.name, column.name), None, column.name)
                     for entry in scope.entries for column in entry.table.columns]
        aggregated = (bool(query.group_by) or query.having is not None
                      or any(contains_aggregate(item.expr) for item in items + query.order_by))
        grouping = [ref.index for ref in query.group_by]
        context = CheckContext(scope, True, grouping if aggregated else None)
        types = [check(item.expr, context) for item in items]
        check_condition(query.having, context, 'HAVING')
        sort_keys = [resolve_order_key(item, items, context) for item in query.order_by]

        rows = scope.entries[0].table.rows
        for join, entry in zip(query.joins, scope.entries[1:]):
            rows = join_rows(rows, entry.table, join)
        rows = [row for row in rows if satisfies(query.where, row)]
        if aggregated:
            groups = group_rows(rows, grouping) if query.group_by else [rows]
            sources = [(group[0] if group else None, group) for group in groups]
            sources = [(row, group) for row, group in sources
                       if satisfies(query.having, row, group)]
        else:
            sources = [(row, None) for row in rows]
        results = [ResultRow([evaluate(item.expr, row, group) for item in items],
                             [evaluate(key, row, group) for key in sort_keys])
                   for row, group in sources]
        if query.order_by:
            descending = [item.descending for item in query.order_by]
            results.sort(key=cmp_to_key(
                lambda first, second: compare_keys(first.keys, second.keys, descending)))
        if query.distinct:
            unique = {}
            for result in results:
                unique.setdefault(tuple(result.values), result)
            results = list(unique.values())
        if query.offset is not None:
            results = results[query.offset:]
        if query.limit is not None:
            results = results[:query.limit]
        headings = [item.heading for item in items]
        print_table(headings, types, [result.values for result in results])


def main():
    database = Database()
    for text in split_statements(sys.stdin.read()):
        try:
            statement = Parser(tokenize(text)).parse_statement()
            if isinstance(statement, Exit):
                break
            if statement is not None:
                database.execute(statement)
        except SqlError as error:
            print(f'ERROR: {error}')


if __name__ == '__main__':
    main()
