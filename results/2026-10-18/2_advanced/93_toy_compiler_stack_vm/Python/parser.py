from lexer import CompileError


TYPES = frozenset(("int", "bool", "void"))
OPERATORS = ({"||"}, {"&&"}, {"==", "!="}, {"<", "<=", ">", ">="}, {"+", "-"}, {"*", "/", "%"})


class Node:
    def __init__(self, kind, position, **fields):
        self.kind = kind
        self.position = position
        self.__dict__.update(fields)


def expression_children(node):
    if node.kind == "binary":
        return [node.left, node.right]
    if node.kind == "unary":
        return [node.operand]
    if node.kind == "array":
        return [node.index]
    if node.kind == "call":
        return node.arguments
    return []


def statement_children(node):
    if node.kind == "block":
        return node.statements
    if node.kind == "if":
        return [node.then] + ([node.otherwise] if node.otherwise is not None else [])
    if node.kind == "while":
        return [node.body]
    if node.kind == "for":
        return [child for child in (node.initial, node.update, node.body) if child is not None]
    return []


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0

    def peek(self):
        return self.tokens[self.position]

    def fail(self):
        token = self.peek()
        message = "unexpected end of program" if token.kind == "end" else f"unexpected '{token.spelling}'"
        raise CompileError("syntax", token.position, message)

    def take(self):
        token = self.peek()
        self.position += 1
        return token

    def accept(self, spelling):
        if self.peek().spelling == spelling:
            return self.take()
        return None

    def expect(self, spelling):
        if self.peek().spelling != spelling:
            self.fail()
        return self.take()

    def identifier(self):
        if self.peek().kind != "identifier":
            self.fail()
        return self.take()

    def declaration_head(self):
        if self.peek().spelling not in TYPES:
            self.fail()
        type_token = self.take()
        name = self.identifier()
        return type_token.position, {"type": type_token.spelling, "name": name.spelling,
                                     "name_position": name.position}

    def parse(self):
        declarations = []
        while self.peek().kind != "end":
            position, fields = self.declaration_head()
            if self.accept("("):
                parameters = []
                if self.peek().spelling != ")":
                    while True:
                        parameter_position, parameter_fields = self.declaration_head()
                        parameters.append(Node("parameter", parameter_position, **parameter_fields))
                        if not self.accept(","):
                            break
                self.expect(")")
                declarations.append(Node("function", position, parameters=parameters, body=self.block(), **fields))
            else:
                size = size_position = initializer = None
                if self.accept("["):
                    if self.peek().kind != "integer":
                        self.fail()
                    token = self.take()
                    size, size_position = int(token.spelling), token.position
                    self.expect("]")
                elif self.accept("="):
                    initializer = self.expression()
                self.expect(";")
                declarations.append(Node("global", position, size=size, size_position=size_position,
                                         initializer=initializer, **fields))
        return declarations

    def declaration(self, for_initial=False):
        position, fields = self.declaration_head()
        initializer = None
        if for_initial:
            self.expect("=")
            initializer = self.expression()
        else:
            if self.accept("="):
                initializer = self.expression()
            self.expect(";")
        return Node("declaration", position, initializer=initializer, **fields)

    def block(self):
        opening = self.expect("{")
        statements = []
        while self.peek().spelling != "}":
            statements.append(self.declaration() if self.peek().spelling in TYPES else self.statement())
        closing = self.expect("}")
        return Node("block", opening.position, statements=statements, end_position=closing.position)

    def statement(self):
        token = self.peek()
        spelling = token.spelling
        if spelling == "{":
            return self.block()
        if spelling in ("if", "while"):
            self.take()
            self.expect("(")
            condition = self.expression()
            self.expect(")")
            body = self.statement()
            if spelling == "while":
                return Node("while", token.position, condition=condition, body=body)
            otherwise = self.statement() if self.accept("else") else None
            return Node("if", token.position, condition=condition, then=body, otherwise=otherwise)
        if spelling == "for":
            self.take()
            self.expect("(")
            initial = None
            if self.peek().spelling in TYPES:
                initial = self.declaration(for_initial=True)
            elif self.peek().spelling != ";":
                initial = self.simple()
            self.expect(";")
            condition = self.expression() if self.peek().spelling != ";" else None
            self.expect(";")
            update = self.simple() if self.peek().spelling != ")" else None
            self.expect(")")
            return Node("for", token.position, initial=initial, condition=condition,
                        update=update, body=self.statement())
        if spelling in ("break", "continue"):
            self.take()
            self.expect(";")
            return Node(spelling, token.position)
        if spelling == "return":
            self.take()
            value = self.expression() if self.peek().spelling != ";" else None
            self.expect(";")
            return Node("return", token.position, value=value)
        if spelling == "print":
            self.take()
            self.expect("(")
            arguments = [self.expression()]
            while self.accept(","):
                arguments.append(self.expression())
            self.expect(")")
            self.expect(";")
            return Node("print", token.position, arguments=arguments)
        if token.kind == "identifier" or spelling == "read":
            result = self.simple()
            self.expect(";")
            return result
        self.fail()

    def simple(self):
        token = self.peek()
        if token.kind != "identifier" and token.spelling != "read":
            self.fail()
        value = self.primary()
        if value.kind in ("call", "read"):
            return Node("call_statement", value.position, expression=value)
        self.expect("=")
        index = value.index if value.kind == "array" else None
        return Node("assignment", value.position, name=value.name, index=index, value=self.expression())

    def expression(self, level=0):
        if level == len(OPERATORS):
            if self.peek().spelling in ("-", "!"):
                operator = self.take()
                return Node("unary", operator.position, operator=operator.spelling, operand=self.expression(level))
            return self.primary()
        result = self.expression(level + 1)
        while self.peek().spelling in OPERATORS[level]:
            operator = self.take()
            result = Node("binary", operator.position, operator=operator.spelling,
                          left=result, right=self.expression(level + 1))
        return result

    def primary(self):
        token = self.peek()
        if token.kind == "integer":
            self.take()
            return Node("integer", token.position, value=int(token.spelling))
        if token.spelling in ("true", "false"):
            self.take()
            return Node("boolean", token.position, value=token.spelling == "true")
        if token.spelling == "read":
            self.take()
            self.expect("(")
            self.expect(")")
            return Node("read", token.position)
        if self.accept("("):
            result = self.expression()
            self.expect(")")
            return result
        if token.kind == "identifier":
            self.take()
            if self.accept("("):
                arguments = []
                if self.peek().spelling != ")":
                    arguments.append(self.expression())
                    while self.accept(","):
                        arguments.append(self.expression())
                self.expect(")")
                return Node("call", token.position, name=token.spelling, arguments=arguments)
            if self.accept("["):
                index = self.expression()
                self.expect("]")
                return Node("array", token.position, name=token.spelling, index=index)
            return Node("variable", token.position, name=token.spelling)
        self.fail()
