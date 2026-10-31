from lexer import SyntaxIssue


ASSIGNMENTS = frozenset(("=", "+=", "-=", "*=", "/=", "%=", "^="))
COMPARISONS = frozenset(("<", "<=", "==", "!=", ">=", ">"))
LVALUE_KINDS = frozenset(("name", "array", "field"))
STATEMENTS = frozenset(("if", "while", "do", "for", "for_in", "print", "printf", "delete",
                        "next", "break", "continue", "exit", "return", "expression_statement"))


class Node:
    def __init__(self, kind, position, children=(), **fields):
        self.kind, self.position = kind, position
        self.children = [child for child in children if child is not None]
        self.__dict__.update(fields)


class Parser:
    def __init__(self, tokens):
        self.tokens, self.position = tokens, 0
        self.function = False
        self.phase = None
        self.loop_depth = 0

    def peek(self):
        return self.tokens[self.position]

    def take(self):
        token = self.peek()
        self.position += 1
        return token

    def fail(self, position=None):
        raise SyntaxIssue(self.peek().position if position is None else position)

    def accept(self, spelling):
        return self.take() if self.peek().spelling == spelling else None

    def expect(self, spelling):
        if self.peek().spelling != spelling:
            self.fail()
        return self.take()

    def name(self):
        if self.peek().kind != "name":
            self.fail()
        token = self.take()
        return Node("name", token.position, name=token.spelling)

    def newlines(self):
        while self.accept("\n"):
            pass

    def parse(self):
        items = []
        while self.peek().kind != "end":
            if self.peek().spelling in ("\n", ";"):
                self.take()
                continue
            start = self.peek()
            if self.accept("function"):
                if self.peek().kind not in ("name", "function_name"):
                    self.fail()
                name = self.take()
                self.expect("(")
                parameters = []
                if self.peek().spelling != ")":
                    while True:
                        parameter = self.name()
                        parameter.kind = "parameter"
                        parameters.append(parameter)
                        if not self.accept(","):
                            break
                        self.newlines()
                self.expect(")")
                self.newlines()
                self.function = True
                body = self.block()
                self.function = False
                items.append(Node("function", start.position, [*parameters, body], name=name.spelling,
                                  name_position=name.position, parameters=parameters, body=body))
                continue
            patterns = []
            if start.spelling in ("BEGIN", "END"):
                flavor = self.take().spelling
            elif start.spelling == "{":
                flavor = "all"
            else:
                patterns.append(self.expression())
                if self.accept(","):
                    self.newlines()
                    patterns.append(self.expression())
                flavor = "range" if len(patterns) == 2 else "pattern"
            self.phase = flavor
            if flavor in ("BEGIN", "END", "all") or self.peek().spelling == "{":
                action = self.block()
            else:
                if self.peek().spelling not in ("\n", ";") and self.peek().kind != "end":
                    self.fail()
                action = None
            self.phase = None
            items.append(Node("rule", start.position, [*patterns, action], flavor=flavor,
                              patterns=patterns, action=action))
        return items

    def block(self):
        opening = self.expect("{")
        statements = []
        while self.peek().spelling != "}":
            if self.peek().spelling in ("\n", ";"):
                self.take()
            else:
                statements.append(self.statement())
        self.expect("}")
        return Node("block", opening.position, statements, statements=statements)

    def condition(self):
        self.expect("(")
        value = self.expression()
        self.expect(")")
        return value

    def loop_body(self):
        self.newlines()
        self.loop_depth += 1
        body = self.statement()
        self.loop_depth -= 1
        return body

    def terminator(self):
        if self.peek().spelling in (";", "\n"):
            self.take()
        elif self.peek().spelling != "}":
            self.fail()

    def statement(self):
        token = self.peek()
        spelling = token.spelling
        if spelling == "{":
            return self.block()
        if self.accept(";"):
            return Node("empty", token.position)
        if self.accept("if"):
            condition = self.condition()
            self.newlines()
            first = self.statement()
            self.newlines()
            second = None
            if self.accept("else"):
                self.newlines()
                second = self.statement()
            return Node("if", token.position, [condition, first, second], condition=condition, first=first, second=second)
        if self.accept("while"):
            condition = self.condition()
            body = self.loop_body()
            return Node("while", token.position, [condition, body], condition=condition, body=body)
        if self.accept("do"):
            body = self.loop_body()
            self.newlines()
            self.expect("while")
            condition = self.condition()
            self.terminator()
            return Node("do", token.position, [body, condition], body=body, condition=condition)
        if self.accept("for"):
            self.expect("(")
            ahead = self.tokens[self.position:self.position + 4]
            if len(ahead) == 4 and ahead[0].kind == "name" and ahead[1].spelling == "in" and ahead[2].kind == "name" and ahead[3].spelling == ")":
                variable = self.name()
                self.expect("in")
                array = self.name()
                self.expect(")")
                body = self.loop_body()
                return Node("for_in", token.position, [variable, array, body], variable=variable, array=array, body=body)
            initial = self.expression() if self.peek().spelling != ";" else None
            self.expect(";")
            self.newlines()
            condition = self.expression() if self.peek().spelling != ";" else None
            self.expect(";")
            self.newlines()
            update = self.expression() if self.peek().spelling != ")" else None
            self.expect(")")
            body = self.loop_body()
            return Node("for", token.position, [initial, condition, update, body], initial=initial,
                        condition=condition, update=update, body=body)
        if spelling in ("print", "printf"):
            self.take()
            result = self.output_statement(token)
        elif spelling == "delete":
            self.take()
            array = self.name()
            indexes = None
            if self.accept("["):
                indexes = self.expression_list()
                self.expect("]")
            result = Node("delete", token.position, [array, *(indexes or [])], array=array, indexes=indexes)
        elif spelling in ("next", "break", "continue", "exit", "return"):
            self.take()
            if spelling == "next" and not self.function and self.phase in ("BEGIN", "END"):
                self.fail(token.position)
            if spelling == "return" and not self.function:
                self.fail(token.position)
            if spelling in ("break", "continue") and self.loop_depth == 0:
                self.fail(token.position)
            value = None
            if spelling in ("exit", "return") and self.peek().spelling not in (";", "\n", "}"):
                value = self.expression()
            result = Node(spelling, token.position, [value], value=value)
        else:
            expression = self.expression()
            result = Node("expression_statement", token.position, [expression], expression=expression)
        self.terminator()
        return result

    def parenthesized_output(self):
        if self.peek().spelling != "(":
            return False
        depth = 0
        for index in range(self.position, len(self.tokens)):
            spelling = self.tokens[index].spelling
            if spelling == "(":
                depth += 1
            elif spelling == ")":
                depth -= 1
                if depth == 0:
                    next_token = self.tokens[index + 1]
                    return next_token.spelling in (";", "\n", "}", ">", ">>") or next_token.kind == "end"
        return False

    def output_statement(self, token):
        arguments = []
        if self.parenthesized_output():
            self.expect("(")
            arguments = self.expression_list()
            self.expect(")")
        elif self.peek().spelling not in (";", "\n", "}", ">", ">>"):
            arguments = self.expression_list(greater=False)
        if token.spelling == "printf" and not arguments:
            self.fail()
        redirect = self.take() if self.peek().spelling in (">", ">>") else None
        filename = self.concatenation() if redirect is not None else None
        return Node(token.spelling, token.position, [*arguments, filename], arguments=arguments,
                    redirect=redirect.spelling if redirect else None,
                    redirect_position=redirect.position if redirect else None, filename=filename)

    def expression_list(self, greater=True):
        result = [self.expression(greater)]
        while self.accept(","):
            self.newlines()
            result.append(self.expression(greater))
        return result

    def expression(self, greater=True):
        left = self.conditional(greater)
        if left.kind in LVALUE_KINDS and self.peek().spelling in ASSIGNMENTS:
            operator = self.take()
            right = self.expression(greater)
            return Node("assignment", operator.position, [left, right], operator=operator.spelling,
                        location=left, value=right)
        return left

    def conditional(self, greater):
        condition = self.logical(0, greater)
        operator = self.accept("?")
        if operator is None:
            return condition
        first = self.conditional(greater)
        self.expect(":")
        second = self.conditional(greater)
        return Node("conditional", operator.position, [condition, first, second],
                    condition=condition, first=first, second=second)

    def binary(self, operator, left, right):
        return Node("binary", operator.position, [left, right], operator=operator.spelling, left=left, right=right)

    def logical(self, level, greater):
        if level == 2:
            return self.membership(greater)
        operator_name = "||" if level == 0 else "&&"
        left = self.logical(level + 1, greater)
        while self.peek().spelling == operator_name:
            operator = self.take()
            self.newlines()
            left = self.binary(operator, left, self.logical(level + 1, greater))
        return left

    def membership(self, greater):
        left = self.comparison(greater)
        while self.peek().spelling == "in":
            operator = self.take()
            array = self.name()
            left = Node("membership", operator.position, [left, array], indexes=[left], array=array)
        return left

    def comparison(self, greater):
        left = self.concatenation()
        while self.peek().spelling in COMPARISONS and (greater or self.peek().spelling != ">"):
            operator = self.take()
            left = self.binary(operator, left, self.concatenation())
        return left

    def concatenation(self):
        left = self.additive()
        while self.peek().kind in ("number", "string", "name", "function_name", "builtin") or self.peek().spelling in ("$", "(", "++", "--"):
            position = self.peek().position
            right = self.additive()
            left = Node("binary", position, [left, right], operator="concat", left=left, right=right)
        return left

    def additive(self):
        left = self.multiplicative()
        while self.peek().spelling in ("+", "-"):
            operator = self.take()
            left = self.binary(operator, left, self.multiplicative())
        return left

    def multiplicative(self):
        left = self.unary()
        while self.peek().spelling in ("*", "/", "%"):
            operator = self.take()
            left = self.binary(operator, left, self.unary())
        return left

    def unary(self):
        if self.peek().spelling in ("!", "-", "+"):
            operator = self.take()
            operand = self.unary()
            return Node("unary", operator.position, [operand], operator=operator.spelling, operand=operand)
        left = self.postfix()
        if self.peek().spelling == "^":
            operator = self.take()
            left = self.binary(operator, left, self.unary())
        return left

    def prefix(self):
        operator = self.take()
        location = self.lvalue()
        return Node("increment", operator.position, [location], location=location,
                    delta=1 if operator.spelling == "++" else -1, prefix=True)

    def postfix(self):
        if self.peek().spelling in ("++", "--"):
            return self.prefix()
        left = self.atom()
        if left.kind in LVALUE_KINDS and self.peek().spelling in ("++", "--"):
            operator = self.take()
            return Node("increment", operator.position, [left], location=left,
                        delta=1 if operator.spelling == "++" else -1, prefix=False)
        return left

    def lvalue(self):
        if self.peek().kind == "name":
            node = self.name()
            if self.accept("["):
                indexes = self.expression_list()
                self.expect("]")
                return Node("array", node.position, indexes, name=node.name, indexes=indexes)
            return node
        dollar = self.accept("$")
        if dollar is not None:
            index = self.prefix() if self.peek().spelling in ("++", "--") else self.atom()
            return Node("field", dollar.position, [index], index=index)
        self.fail()

    def atom(self):
        token = self.peek()
        if token.kind in ("number", "string"):
            self.take()
            return Node(token.kind, token.position, value=token.value)
        if token.kind == "name" or token.spelling == "$":
            return self.lvalue()
        if self.accept("("):
            expressions = self.expression_list()
            self.expect(")")
            if len(expressions) == 1:
                return Node("paren", token.position, expressions, expression=expressions[0])
            self.expect("in")
            array = self.name()
            return Node("membership", token.position, [*expressions, array], indexes=expressions, array=array)
        if token.kind in ("function_name", "builtin"):
            self.take()
            arguments = []
            if self.accept("("):
                if self.peek().spelling != ")":
                    arguments = self.expression_list()
                self.expect(")")
            elif token.kind == "function_name" or token.spelling != "length":
                self.fail()
            kind = "call" if token.kind == "function_name" else "builtin"
            if kind == "builtin":
                self.check_builtin(token, arguments)
            return Node(kind, token.position, arguments, name=token.spelling, arguments=arguments)
        if self.accept("getline"):
            target = self.lvalue() if self.peek().kind == "name" or self.peek().spelling == "$" else None
            filename = self.atom() if self.accept("<") else None
            return Node("getline", token.position, [target, filename], target=target, filename=filename)
        self.fail()

    def check_builtin(self, token, arguments):
        count, name = len(arguments), token.spelling
        if name == "length":
            valid = count in (0, 1)
        elif name in ("substr", "split"):
            valid = count in (2, 3)
        elif name == "index":
            valid = count == 2
        elif name == "sprintf":
            valid = count >= 1
        else:
            valid = count == 1
        if not valid or name == "split" and arguments[1].kind != "name":
            self.fail(token.position)
