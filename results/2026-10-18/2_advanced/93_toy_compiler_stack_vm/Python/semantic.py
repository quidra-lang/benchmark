from lexer import CompileError
from parser import expression_children


def can_complete(statement):
    pending = [(statement, False)]
    while pending:
        node, expanded = pending.pop()
        if hasattr(node, "completes"):
            continue
        if node.kind in ("return", "break", "continue"):
            node.completes = False
        elif node.kind == "block":
            if expanded:
                node.completes = all(child.completes for child in node.statements)
            else:
                pending.append((node, True))
                pending.extend((child, False) for child in node.statements)
        elif node.kind == "if" and node.otherwise is not None:
            if expanded:
                node.completes = node.then.completes or node.otherwise.completes
            else:
                pending.append((node, True))
                pending.append((node.then, False))
                pending.append((node.otherwise, False))
        else:
            node.completes = True
    return statement.completes


class Analyzer:
    def __init__(self, declarations, end_position):
        self.declarations = declarations
        self.end_position = end_position
        self.globals = {}
        self.functions = []
        self.variables = []
        self.scopes = []
        self.function = None

    def fail(self, position, message):
        raise CompileError("semantic", position, message)

    def prepare(self, declaration):
        declaration.references = []
        declaration.read_accesses = 0
        if declaration.kind == "function":
            declaration.calls = set()
            self.functions.append(declaration)
        else:
            self.variables.append(declaration)

    def lookup(self, name, position, read=True):
        referent = None
        for scope in reversed(self.scopes):
            if name in scope:
                referent = scope[name]
                break
        if referent is None:
            referent = self.globals.get(name)
        if referent is not None:
            referent.references.append(position)
            referent.read_accesses += int(read)
        return referent

    def variable(self, name, position, indexed, read=True):
        referent = self.lookup(name, position, read)
        if referent is None:
            self.fail(position, f"undeclared identifier '{name}'")
        if referent.kind == "function":
            self.fail(position, f"'{name}' is a function, not a variable")
        is_array = referent.kind == "global" and referent.size is not None
        if indexed and not is_array:
            self.fail(position, f"'{name}' is not an array")
        if not indexed and is_array:
            self.fail(position, f"array '{name}' used without index")
        return referent

    def expression(self, node, call_statement=False):
        kind = node.kind
        if kind in ("integer", "read"):
            result = "int"
        elif kind == "boolean":
            result = "bool"
        elif kind in ("variable", "array"):
            node.referent = self.variable(node.name, node.position, kind == "array")
            if kind == "array" and self.expression(node.index) != "int":
                self.fail(node.position, f"index of '{node.name}' must be int")
            result = node.referent.type
        elif kind == "call":
            referent = self.lookup(node.name, node.position)
            if referent is None:
                self.fail(node.position, f"undeclared function '{node.name}'")
            if referent.kind != "function":
                self.fail(node.position, f"'{node.name}' is not a function")
            node.referent = referent
            self.function.calls.add(referent)
            expected, found = len(referent.parameters), len(node.arguments)
            if expected != found:
                self.fail(node.position, f"wrong number of arguments to '{node.name}' (expected {expected}, found {found})")
            for number, (argument, parameter) in enumerate(zip(node.arguments, referent.parameters), 1):
                if self.expression(argument) != parameter.type:
                    self.fail(node.position, f"argument {number} of '{node.name}' must be {parameter.type}")
            if not call_statement and referent.type == "void":
                self.fail(node.position, f"void function '{node.name}' used as a value")
            result = referent.type
        elif kind == "unary":
            result = self.expression(node.operand)
            required = "int" if node.operator == "-" else "bool"
            if result != required:
                self.fail(node.position, f"operator '{node.operator}' requires {required} operand")
        else:
            left = self.expression(node.left)
            right = self.expression(node.right)
            operator = node.operator
            if operator in ("+", "-", "*", "/", "%", "<", "<=", ">", ">="):
                if left != "int" or right != "int":
                    self.fail(node.position, f"operator '{operator}' requires int operands")
                result = "int" if operator in ("+", "-", "*", "/", "%") else "bool"
            elif operator in ("==", "!="):
                if left != right:
                    self.fail(node.position, f"operator '{operator}' requires operands of the same type")
                result = "bool"
            else:
                if left != "bool" or right != "bool":
                    self.fail(node.position, f"operator '{operator}' requires bool operands")
                result = "bool"
        node.type = result
        return result

    def constant_initializer(self, node):
        positions = []
        pending = [node]
        while pending:
            current = pending.pop()
            if current.kind in ("variable", "array", "call", "read"):
                positions.append(current.position)
            pending.extend(expression_children(current))
        if positions:
            self.fail(min(positions), "global initializer must be constant")
        return self.expression(node)

    def statement(self, node, loop_depth=0):
        kind = node.kind
        if kind == "declaration":
            if node.type == "void":
                self.fail(node.name_position, f"variable '{node.name}' cannot have type void")
            if node.name in self.scopes[-1]:
                self.fail(node.name_position, f"redeclaration of '{node.name}'")
            if node.initializer is not None and self.expression(node.initializer) != node.type:
                self.fail(node.name_position, f"type mismatch in initialization of '{node.name}'")
            self.prepare(node)
            self.scopes[-1][node.name] = node
        elif kind == "assignment":
            node.referent = self.variable(node.name, node.position, node.index is not None, read=False)
            if node.index is not None and self.expression(node.index) != "int":
                self.fail(node.position, f"index of '{node.name}' must be int")
            if self.expression(node.value) != node.referent.type:
                self.fail(node.position, f"type mismatch in assignment to '{node.name}'")
        elif kind == "call_statement":
            self.expression(node.expression, call_statement=True)
        elif kind in ("if", "while"):
            if self.expression(node.condition) != "bool":
                self.fail(node.position, f"condition of '{kind}' must be bool")
            if kind == "if":
                self.statement(node.then, loop_depth)
                if node.otherwise is not None:
                    self.statement(node.otherwise, loop_depth)
            else:
                self.statement(node.body, loop_depth + 1)
        elif kind == "for":
            self.scopes.append({})
            if node.initial is not None:
                self.statement(node.initial, loop_depth)
            if node.condition is not None and self.expression(node.condition) != "bool":
                self.fail(node.position, "condition of 'for' must be bool")
            if node.update is not None:
                self.statement(node.update, loop_depth)
            self.statement(node.body, loop_depth + 1)
            self.scopes.pop()
        elif kind in ("break", "continue"):
            if loop_depth == 0:
                self.fail(node.position, f"'{kind}' outside loop")
        elif kind == "return":
            if self.function.type == "void" and node.value is not None:
                self.fail(node.position, f"function '{self.function.name}' must not return a value")
            if self.function.type != "void":
                if node.value is None:
                    self.fail(node.position, f"function '{self.function.name}' must return a value")
                if self.expression(node.value) != self.function.type:
                    self.fail(node.position, f"return value of '{self.function.name}' must be {self.function.type}")
        elif kind == "print":
            for number, argument in enumerate(node.arguments, 1):
                if self.expression(argument) != "int":
                    self.fail(node.position, f"argument {number} of 'print' must be int")
        elif kind == "block":
            self.scopes.append({})
            for child in node.statements:
                self.statement(child, loop_depth)
            self.scopes.pop()

    def analyze(self):
        for node in self.declarations:
            if node.kind == "global":
                if node.size is not None:
                    if node.type != "int":
                        self.fail(node.name_position, f"array '{node.name}' must have element type int")
                    if node.size == 0:
                        self.fail(node.size_position, f"array '{node.name}' must have a positive size")
                elif node.type == "void":
                    self.fail(node.name_position, f"variable '{node.name}' cannot have type void")
            if node.name in self.globals:
                self.fail(node.name_position, f"redeclaration of '{node.name}'")
            if node.kind == "global":
                if node.initializer is not None and self.constant_initializer(node.initializer) != node.type:
                    self.fail(node.name_position, f"type mismatch in initialization of '{node.name}'")
            else:
                names = set()
                for parameter in node.parameters:
                    if parameter.type == "void":
                        self.fail(parameter.name_position, f"parameter '{parameter.name}' cannot have type void")
                    if parameter.name in names:
                        self.fail(parameter.name_position, f"redeclaration of '{parameter.name}'")
                    names.add(parameter.name)
                    self.prepare(parameter)
            self.prepare(node)
            self.globals[node.name] = node
        main = self.globals.get("main")
        if main is None or main.kind != "function":
            self.fail(self.end_position, "no main function")
        if main.type != "void" or main.parameters:
            self.fail(main.name_position, "main must be declared as 'void main()'")
        for function in self.functions:
            self.function = function
            self.scopes = [{parameter.name: parameter for parameter in function.parameters}]
            for statement in function.body.statements:
                self.statement(statement)
            if function.type != "void" and can_complete(function.body):
                self.fail(function.name_position, f"missing return in function '{function.name}'")
        return self
