OPERATORS = {
    "||": (1, True), "&&": (2, True),
    "=": (3, False), "<>": (3, False), "<": (3, False),
    ">": (3, False), "<=": (3, False), ">=": (3, False),
    "::": (4, True), "^": (4, True), "+": (5, False),
    "-": (5, False), "*": (6, False), "/": (6, False), "mod": (6, False),
}


class Node:
    def __init__(self, kind, position, children=(), value=None):
        self.kind = kind
        self.position = position
        self.children = tuple(children)
        self.value = value
        self.inferred = None


class Binding:
    def __init__(self, name, expression):
        self.name = name.spelling
        self.position = name.position
        self.expression = expression
        self.scheme = None
        self.classification = ""


class Group:
    def __init__(self, bindings, rec_position):
        self.bindings = bindings
        self.rec_position = rec_position


class Item:
    def __init__(self, kind, value):
        self.kind = kind
        self.value = value


class SyntaxFailure(Exception):
    def __init__(self, token):
        self.token = token


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.index = 0

    def peek(self):
        return self.tokens[self.index]

    def accept(self, kind):
        if self.peek().kind != kind:
            return None
        token = self.peek()
        self.index += 1
        return token

    def expect(self, kind):
        token = self.accept(kind)
        if token is None:
            raise SyntaxFailure(self.peek())
        return token

    def name(self):
        if not self.peek().is_name():
            raise SyntaxFailure(self.peek())
        return self.expect("identifier")

    def recover(self):
        while self.peek().kind not in (";;", "EOF"):
            self.index += 1
        self.accept(";;")

    def item(self):
        if self.accept("val"):
            name = self.name()
            self.expect(":")
            declared_type = self.type_expression()
            self.expect(";;")
            return Item("signature", (name, declared_type))
        opening = self.accept("let")
        if opening:
            group = self.group()
            if self.accept("in"):
                expression = Node("let", opening.position, (self.expression(),), group)
                result = Item("expression", expression)
            else:
                result = Item("declaration", group)
        else:
            result = Item("expression", self.expression())
        self.expect(";;")
        return result

    def group(self):
        rec = self.accept("rec")
        bindings = [self.binding()]
        while self.accept("and"):
            bindings.append(self.binding())
        return Group(bindings, rec.position if rec else None)

    def binding(self):
        name = self.name()
        parameters = []
        while self.peek().kind == "identifier":
            parameters.append(self.expect("identifier"))
        self.expect("=")
        expression = self.expression()
        for parameter in reversed(parameters):
            expression = Node("fun", parameter.position, (expression,), parameter)
        return Binding(name, expression)

    def expression(self):
        opening = self.accept("let")
        if opening:
            group = self.group()
            self.expect("in")
            return Node("let", opening.position, (self.expression(),), group)
        opening = self.accept("fun")
        if opening:
            parameters = [self.expect("identifier")]
            while self.peek().kind == "identifier":
                parameters.append(self.expect("identifier"))
            self.expect("->")
            expression = self.expression()
            for parameter in reversed(parameters):
                expression = Node("fun", parameter.position, (expression,), parameter)
            expression.position = opening.position
            return expression
        opening = self.accept("if")
        if opening:
            condition = self.expression()
            self.expect("then")
            first = self.expression()
            self.expect("else")
            second = self.expression()
            return Node("if", opening.position, (condition, first, second))
        opening = self.accept("match")
        if opening:
            expression = self.expression()
            self.expect("with")
            self.accept("|")
            arms = [self.arm()]
            while self.accept("|"):
                arms.append(self.arm())
            return Node("match", opening.position, (expression,), arms)
        return self.binary(1)

    def arm(self):
        pattern = self.pattern()
        self.expect("->")
        return pattern, self.expression()

    def binary(self, minimum):
        expression = self.unary()
        while self.peek().kind in OPERATORS:
            precedence, right_associative = OPERATORS[self.peek().kind]
            if precedence < minimum:
                break
            operator = self.peek()
            self.index += 1
            right = self.binary(precedence if right_associative else precedence + 1)
            expression = Node("binary", expression.position, (expression, right), operator)
        return expression

    def starts_atom(self):
        token = self.peek()
        return token.kind in ("integer", "string", "true", "false", "(", "[") or token.is_name()

    def unary(self):
        operator = self.accept("-")
        if operator:
            return Node("negate", operator.position, (self.unary(),), operator)
        expression = self.atom()
        while self.starts_atom():
            expression = Node("apply", expression.position, (expression, self.atom()))
        return expression

    def atom(self):
        token = self.peek()
        if token.kind in ("integer", "string"):
            self.index += 1
            return Node(token.kind, token.position, value=token.value)
        if token.kind in ("true", "false"):
            self.index += 1
            return Node("boolean", token.position, value=token.kind == "true")
        if token.is_name():
            self.index += 1
            return Node("name", token.position, value=token.spelling)
        if self.accept("("):
            first = self.expression()
            if self.accept(","):
                second = self.expression()
                self.expect(")")
                return Node("pair", token.position, (first, second))
            self.expect(")")
            return first
        if self.accept("["):
            elements = []
            if not self.accept("]"):
                elements.append(self.expression())
                while self.accept(";"):
                    elements.append(self.expression())
                self.expect("]")
            return Node("list", token.position, elements)
        raise SyntaxFailure(token)

    def pattern(self):
        first = self.pattern_atom()
        if self.accept("::"):
            return Node("cons", first.position, (first, self.pattern()))
        return first

    def pattern_atom(self):
        token = self.peek()
        if token.kind == "identifier":
            self.index += 1
            kind = "wildcard" if token.spelling == "_" else "name"
            return Node(kind, token.position, value=token.spelling)
        if self.accept("-"):
            integer = self.expect("integer")
            return Node("integer", token.position, value=-integer.value)
        if token.kind in ("integer", "string", "true", "false"):
            return self.atom()
        if self.accept("("):
            first = self.pattern()
            if self.accept(","):
                second = self.pattern()
                self.expect(")")
                return Node("pair", token.position, (first, second))
            self.expect(")")
            return first
        if self.accept("["):
            elements = []
            if not self.accept("]"):
                elements.append(self.pattern())
                while self.accept(";"):
                    elements.append(self.pattern())
                self.expect("]")
            return Node("list", token.position, elements)
        raise SyntaxFailure(token)

    def type_expression(self):
        first = self.list_type()
        if self.accept("*"):
            first = Node("pair", first.position, (first, self.list_type()))
        if self.accept("->"):
            first = Node("function", first.position, (first, self.type_expression()))
        return first

    def list_type(self):
        expression = self.type_atom()
        while self.peek().kind == "identifier" and self.peek().spelling == "list":
            self.index += 1
            expression = Node("list", expression.position, (expression,))
        return expression

    def type_atom(self):
        token = self.peek()
        if token.kind == "identifier" and token.spelling in ("int", "bool", "string"):
            self.index += 1
            return Node(token.spelling, token.position)
        if self.accept("type_variable"):
            return Node("type_variable", token.position, value=token.spelling)
        if self.accept("("):
            expression = self.type_expression()
            self.expect(")")
            return expression
        raise SyntaxFailure(token)
