from collections import Counter, namedtuple


MIN_INT = -2147483648
MAX_INT = 2147483647
Frame = namedtuple("Frame", "locals return_address")
BINARY = frozenset(("ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE"))


class RuntimeFault(Exception):
    pass


def trunc_div(a, b):
    quotient = abs(a) // abs(b)
    return -quotient if (a < 0) != (b < 0) else quotient


def calculate(op, a, b=None):
    if op in ("DIV", "MOD") and b == 0:
        raise RuntimeFault("division by zero")
    if op == "ADD":
        result = a + b
    elif op == "SUB":
        result = a - b
    elif op == "MUL":
        result = a * b
    elif op == "DIV":
        result = trunc_div(a, b)
    elif op == "MOD":
        result = a - trunc_div(a, b) * b
    elif op == "NEG":
        result = -a
    elif op == "NOT":
        result = int(a == 0)
    elif op == "LT":
        result = int(a < b)
    elif op == "LE":
        result = int(a <= b)
    elif op == "GT":
        result = int(a > b)
    elif op == "GE":
        result = int(a >= b)
    elif op == "EQ":
        result = int(a == b)
    elif op == "NE":
        result = int(a != b)
    else:
        raise ValueError(op)
    if not MIN_INT <= result <= MAX_INT:
        raise RuntimeFault("integer overflow")
    return result


class Execution:
    def __init__(self, code, owners, starts, global_size, inputs):
        self.code = code
        self.owners = owners
        self.starts = starts
        self.inputs = inputs
        self.globals = [0] * global_size
        self.stack = []
        self.frames = []
        self.read_position = 0
        self.pc = 0
        self.executed = 0
        self.counts = [0] * len(code)
        self.calls = Counter()
        self.pairs = Counter()
        self.max_stack = 0
        self.max_depth = 0
        self.output = []
        self.error = None
        self.error_pc = None

    def step(self):
        instruction = self.code[self.pc]
        op, args = instruction.op, instruction.args
        stack = self.stack
        next_pc = self.pc + 1
        if op == "PUSH":
            stack.append(args[0])
        elif op == "POP":
            stack.pop()
        elif op == "LOADG":
            stack.append(self.globals[args[0]])
        elif op == "STOREG":
            self.globals[args[0]] = stack.pop()
        elif op == "LOADL":
            stack.append(self.frames[-1].locals[args[0]])
        elif op == "STOREL":
            self.frames[-1].locals[args[0]] = stack.pop()
        elif op in ("LOADA", "STOREA"):
            if op == "STOREA":
                value = stack.pop()
            index = stack.pop()
            address, size = args
            if index < 0 or index >= size:
                raise RuntimeFault(f"index {index} out of bounds for array of size {size}")
            if op == "LOADA":
                stack.append(self.globals[address + index])
            else:
                self.globals[address + index] = value
        elif op in BINARY:
            b, a = stack.pop(), stack.pop()
            stack.append(calculate(op, a, b))
        elif op in ("NEG", "NOT"):
            stack.append(calculate(op, stack.pop()))
        elif op == "JUMP":
            next_pc = args[0]
        elif op in ("JUMPF", "JUMPT"):
            value = stack.pop()
            if (value == 0) == (op == "JUMPF"):
                next_pc = args[0]
        elif op == "CALL":
            if len(self.frames) == 100:
                raise RuntimeFault("call depth limit exceeded")
            target, count = args
            values = stack[-count:] if count else []
            if count:
                del stack[-count:]
            self.frames.append(Frame(values, next_pc))
            callee = self.starts[target]
            self.calls[callee] += 1
            self.pairs[self.owners[self.pc], callee] += 1
            next_pc = target
        elif op == "ENTER":
            local = self.frames[-1].locals
            local.extend([0] * (args[0] - len(local)))
        elif op in ("RET", "RETV"):
            next_pc = self.frames.pop().return_address
        elif op == "READ":
            if self.read_position == len(self.inputs):
                raise RuntimeFault("read past end of input")
            stack.append(self.inputs[self.read_position])
            self.read_position += 1
        elif op == "PRINT":
            count = args[0]
            values = stack[-count:]
            del stack[-count:]
            self.output.append(" ".join(str(value) for value in values))
        self.max_stack = max(self.max_stack, len(stack))
        self.max_depth = max(self.max_depth, len(self.frames))
        self.pc = next_pc
        return op != "HALT"

    def run(self):
        while True:
            if self.executed == 100000:
                self.error = "instruction limit exceeded"
                self.error_pc = self.pc
                break
            self.executed += 1
            self.counts[self.pc] += 1
            try:
                if not self.step():
                    break
            except RuntimeFault as error:
                self.error = str(error)
                self.error_pc = self.pc
                break
        return self
