"""Recursive-descent concrete syntax parser for the benchmark language."""

from lexer import ASSIGNMENT, SourceError, TYPES


PRECEDENCE = {
    "||": 1, "&&": 2,
    "==": 3, "!=": 3,
    "<": 4, "<=": 4, ">": 4, ">=": 4,
    "+": 5, "-": 5,
    "*": 6, "/": 6, "%": 6,
}


def node(tag, first, **props):
    return {"tag": tag, "first": first, **props}


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.cursor = 0

    def peek(self):
        return self.tokens[self.cursor]

    def at(self, symbol):
        return self.peek()["text"] == symbol

    def fail(self, expected):
        actual = self.peek()
        found = "end of file" if actual["kind"] == "end" else f"'{actual['text']}'"
        raise SourceError(
            actual["line"], actual["column"],
            f"expected {expected}, found {found}",
        )

    def take(self, symbol):
        if not self.at(symbol):
            self.fail(f"'{symbol}'")
        token = self.peek()
        self.cursor += 1
        return token

    def take_identifier(self):
        if self.peek()["kind"] != "identifier":
            self.fail("identifier")
        token = self.peek()
        self.cursor += 1
        return token

    def take_type(self):
        if self.peek()["text"] not in TYPES:
            self.fail("type")
        token = self.peek()
        self.cursor += 1
        return token

    def is_type(self):
        return self.peek()["text"] in TYPES

    def allow(self, tok):
        tok["allowed"] = True

    def parse(self):
        result = []
        while self.peek()["kind"] != "end":
            result.append(self.item())
        return result

    def item(self):
        typ = self.take_type()
        self.allow(typ)
        name = self.take_identifier()
        if self.at("("):
            parameters = self.list_of("(", ")", self.parameter, False)
            body = self.block()
            return node("function", typ, typ=typ, name=name,
                        parameters=parameters, body=body)
        return self.var_remainder(typ, name, semicolon=True)

    def parameter(self):
        typ = self.take_type()
        name = self.take_identifier()
        brackets = []
        while self.at("["):
            opening = self.take("[")
            closing = self.take("]")
            brackets.append((opening, closing))
        return node("parameter", typ, typ=typ, name=name, brackets=brackets)

    def var_remainder(self, typ, name, semicolon):
        dimensions = []
        while self.at("["):
            opening = self.take("[")
            expression = None if self.at("]") else self.expression()
            closing = self.take("]")
            dimensions.append((opening, expression, closing))
        equals = self.take("=") if self.at("=") else None
        initializer = self.initializer() if equals is not None else None
        semi = self.take(";") if semicolon else None
        return node("variable", typ, typ=typ, name=name, dimensions=dimensions,
                    equals=equals, initializer=initializer, semi=semi)

    def initializer(self):
        return (self.list_of("{", "}", self.initializer, True)
                if self.at("{") else self.expression())

    def list_of(self, opening, closing, element, trailing):
        left = self.take(opening)
        contents, commas = [], []
        final_comma = None
        if not self.at(closing):
            first = element()
            self.allow(first["first"])
            contents.append(first)
            while self.at(","):
                comma = self.take(",")
                if trailing and self.at(closing):
                    comma["trailing_comma"] = True
                    final_comma = comma
                    break
                commas.append(comma)
                item = element()
                self.allow(item["first"])
                contents.append(item)
        right = self.take(closing)
        return node("list", left, left=left, right=right, elements=contents,
                    commas=commas, trailing=final_comma, role=opening)

    def block(self):
        left = self.take("{")
        statements = []
        while not self.at("}") and self.peek()["kind"] != "end":
            statement = self.statement()
            self.allow(statement["first"])
            statements.append(statement)
        right = self.take("}")
        self.allow(right)
        return node("block", left, left=left, right=right,
                    statements=statements)

    def statement(self):
        tok = self.peek()
        if self.at("{"):
            return self.block()
        if self.is_type():
            typ = self.take_type()
            name = self.take_identifier()
            return self.var_remainder(typ, name, True)
        if self.at("if"):
            return self.if_statement()
        if self.at("while"):
            return self.while_statement()
        if self.at("for"):
            return self.for_statement()
        if self.at("switch"):
            return self.switch_statement()
        if self.at("return"):
            keyword = self.take("return")
            expr = None if self.at(";") else self.expression()
            semi = self.take(";")
            return node("return", keyword, keyword=keyword, expr=expr, semi=semi)
        if self.at("break") or self.at("continue"):
            keyword = self.peek()
            self.cursor += 1
            semi = self.take(";")
            return node("flow", keyword, keyword=keyword, semi=semi)
        expression = self.simple()
        semi = self.take(";")
        return node("simple_stmt", expression["first"], value=expression, semi=semi)

    def body(self):
        result = self.statement()
        if result["tag"] != "block" and result["tag"] != "if_else_if":
            self.allow(result["first"])
        return result

    def if_statement(self):
        keyword = self.take("if")
        left = self.take("(")
        condition = self.expression()
        right = self.take(")")
        body = self.body()
        else_token = self.take("else") if self.at("else") else None
        alternative = None
        if else_token is not None:
            if self.at("if"):
                alternative = self.if_statement()
                # An "else if" is one continuation, not an independent body.
                alternative["first"]["allowed"] = False
            else:
                alternative = self.body()
        return node("if", keyword, keyword=keyword, left=left, test=condition,
                    right=right, body=body, else_token=else_token,
                    alternative=alternative)

    def while_statement(self):
        keyword = self.take("while")
        left = self.take("(")
        condition = self.expression()
        right = self.take(")")
        body = self.body()
        return node("while", keyword, keyword=keyword, left=left,
                    test=condition, right=right, body=body)

    def for_statement(self):
        keyword = self.take("for")
        left = self.take("(")
        if self.at(";"):
            initial = None
        elif self.is_type():
            typ = self.take_type()
            name = self.take_identifier()
            initial = self.var_remainder(typ, name, False)
        else:
            initial = self.simple()
        first_semi = self.take(";")
        condition = None if self.at(";") else self.expression()
        second_semi = self.take(";")
        update = None if self.at(")") else self.simple()
        right = self.take(")")
        body = self.body()
        return node("for", keyword, keyword=keyword, left=left, initial=initial,
                    first_semi=first_semi, condition=condition,
                    second_semi=second_semi, update=update, right=right, body=body)

    def switch_statement(self):
        keyword = self.take("switch")
        left = self.take("(")
        test = self.expression()
        right = self.take(")")
        opening = self.take("{")
        clauses = []
        while self.at("case") or self.at("default"):
            label = self.peek()
            self.cursor += 1
            self.allow(label)
            value = self.expression() if label["text"] == "case" else None
            colon = self.take(":")
            statements = []
            while (not self.at("case") and not self.at("default")
                   and not self.at("}") and self.peek()["kind"] != "end"):
                stmt = self.statement()
                self.allow(stmt["first"])
                statements.append(stmt)
            clauses.append(node("clause", label, label=label,
                                value=value, colon=colon, statements=statements))
        closing = self.take("}")
        self.allow(closing)
        return node("switch", keyword, keyword=keyword, left=left, test=test,
                    right=right, opening=opening, closing=closing, clauses=clauses)

    def simple(self):
        left = self.expression()
        if self.peek()["text"] in ASSIGNMENT:
            operator = self.peek()
            self.cursor += 1
            right = self.expression()
            return node("assign", left["first"], left=left, op=operator, right=right)
        return node("expr_stmt", left["first"], expr=left)

    def expression(self):
        condition = self.binary(1)
        if self.at("?"):
            question = self.take("?")
            yes = self.expression()
            colon = self.take(":")
            no = self.expression()
            return node("conditional", condition["first"], test=condition,
                        question=question, yes=yes, colon=colon, no=no, level=0)
        return condition

    def binary(self, precedence):
        if precedence > 6:
            return self.unary()
        left = self.binary(precedence + 1)
        while PRECEDENCE.get(self.peek()["text"]) == precedence:
            operator = self.peek()
            self.cursor += 1
            right = self.binary(precedence + 1)
            left = node("binary", left["first"], left=left, op=operator,
                        right=right, level=precedence)
        return left

    def unary(self):
        if self.at("-") or self.at("!"):
            operator = self.peek()
            self.cursor += 1
            operand = self.unary()
            return node("unary", operator, op=operator, operand=operand, level=7)
        target = self.primary()
        while True:
            if self.at("("):
                args = self.list_of("(", ")", self.expression, False)
                target = node("call", target["first"], target=target,
                              arguments=args, level=8)
            elif self.at("["):
                left = self.take("[")
                index = self.expression()
                right = self.take("]")
                target = node("index", target["first"], target=target,
                              left=left, index=index, right=right, level=8)
            elif self.at("."):
                dot = self.take(".")
                member = self.take_identifier()
                target = node("member", target["first"], target=target,
                              dot=dot, member=member, level=8)
            else:
                break
        return target

    def primary(self):
        tok = self.peek()
        if tok["kind"] in ("identifier", "number", "string") or tok["text"] in (
                "true", "false"):
            self.cursor += 1
            return node("primary", tok, value=tok, level=8)
        if self.at("("):
            left = self.take("(")
            inner = self.expression()
            right = self.take(")")
            return node("paren", left, left=left, inner=inner,
                        right=right, level=8)
        self.fail("expression")
