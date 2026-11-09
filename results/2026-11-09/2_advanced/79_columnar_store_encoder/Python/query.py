from sys import getrecursionlimit, setrecursionlimit


def tokenize(text):
    tokens = []
    position = 0
    while position < len(text):
        character = text[position]
        if character == " ":
            position += 1
            continue
        start = position
        if character == "'":
            position = text.index("'", position + 1) + 1
        elif character.isalpha() or character == "_":
            position += 1
            while position < len(text) and (text[position].isalnum() or text[position] == "_"):
                position += 1
        elif character.isdigit() or character == "-":
            position += 1
            while position < len(text) and text[position].isdigit():
                position += 1
        elif text[position:position + 2] in ("<=", ">=", "<>"):
            position += 2
        else:
            position += 1
        tokens.append(text[start:position])
    return tokens


class Parser:
    def __init__(self, text):
        self.tokens = tokenize(text)
        self.position = 0
        setrecursionlimit(max(getrecursionlimit(), 4 * len(self.tokens) + 1000))

    def peek(self):
        return self.tokens[self.position] if self.position < len(self.tokens) else None

    def take(self, expected=None):
        token = self.tokens[self.position]
        self.position += 1
        if expected is not None and token != expected:
            raise ValueError(f"Expected {expected}, found {token}")
        return token

    def accept(self, token):
        if self.peek() == token:
            self.position += 1
            return True
        return False

    def parse(self):
        self.take("SELECT")
        items = None
        if not self.accept("*"):
            items = [self.item()]
            while self.accept(","):
                items.append(self.item())
        condition = self.condition() if self.accept("WHERE") else None
        group = None
        if self.accept("GROUP"):
            self.take("BY")
            group = self.take()
        order, descending = None, False
        if self.accept("ORDER"):
            self.take("BY")
            order = self.take()
            if self.accept("DESC"):
                descending = True
            else:
                self.accept("ASC")
        limit = int(self.take()) if self.accept("LIMIT") else None
        return {"items": items, "condition": condition, "group": group, "order": order,
                "descending": descending, "limit": limit}

    def item(self):
        name = self.take()
        if name[0].islower():
            return "COLUMN", name
        self.take("(")
        operation = "COUNT_DISTINCT" if self.accept("DISTINCT") else name
        column = None if self.accept("*") else self.take()
        self.take(")")
        return operation, column

    def literal(self):
        token = self.take()
        if token.startswith("'"):
            return "STRING", token[1:-1]
        if token in ("TRUE", "FALSE"):
            return "BOOL", token == "TRUE"
        return "INT", int(token)

    def condition(self):
        tree = self.conjunction()
        while self.accept("OR"):
            tree = "OR", tree, self.conjunction()
        return tree

    def conjunction(self):
        tree = self.negation()
        while self.accept("AND"):
            tree = "AND", tree, self.negation()
        return tree

    def negation(self):
        if self.accept("NOT"):
            return "NOT", self.negation()
        if self.accept("("):
            tree = self.condition()
            self.take(")")
            return tree
        column = self.take()
        operation = self.take()
        if operation == "IS":
            operation = "IS_NOT_NULL" if self.accept("NOT") else "IS_NULL"
            self.take("NULL")
            literals = ()
        elif operation == "BETWEEN":
            first = self.literal()
            self.take("AND")
            literals = first, self.literal()
        elif operation == "IN":
            self.take("(")
            literals = [self.literal()]
            while self.accept(","):
                literals.append(self.literal())
            self.take(")")
            literals = tuple(literals)
        else:
            literals = (self.literal(),)
        return operation, column, literals
