"""Explicit-stack leftmost-first backtracking VM, including nested LOOK bodies."""

from charset import assertion, equal, test_any, test_char, test_class


class TooManySteps(Exception):
    """Raised exactly when a command has attempted instruction number 200001."""


class BacktrackingVM:
    def __init__(self, program, flags, group_count, text, full=False):
        self.program = program
        self.flags = flags
        self.groups = group_count
        self.text = text
        self.full = full
        self.steps = 0

    def _execute(self, initial_pc, start, captures, partial):
        stack = [(initial_pc, start, captures.copy(), frozenset())]
        while stack:
            pc, pos, stored, visited = stack.pop()
            while True:
                self.steps += 1
                if self.steps > 200000:
                    raise TooManySteps()
                ins = self.program[pc]
                op = ins["op"]
                if op in ("CHAR", "ANY", "CLASS"):
                    success = (
                        test_char(self.text, pos, ins["char"], self.flags)
                        if op == "CHAR" else
                        test_any(self.text, pos, self.flags)
                        if op == "ANY" else
                        test_class(self.text, pos, ins["set"], ins["neg"],
                                   self.flags)
                    )
                    if not success:
                        break
                    pc += 1
                    pos += 1
                    visited = frozenset()
                elif op == "SPLIT":
                    if pc in visited:
                        break
                    new_visited = visited | {pc}
                    stack.append((
                        ins["y"], pos, stored.copy(), new_visited
                    ))
                    visited = new_visited
                    pc = ins["x"]
                elif op == "JMP":
                    pc = ins["x"]
                elif op == "SAVE":
                    stored[ins["slot"]] = pos
                    pc += 1
                elif op == "ASSERT":
                    if not assertion(ins["kind"], self.text, pos, self.flags):
                        break
                    pc += 1
                elif op == "BACKREF":
                    group = ins["group"]
                    first, last = stored[2 * group:2 * group + 2]
                    if first is None or last is None or first > last:
                        break
                    literal = self.text[first:last]
                    if (pos + len(literal) > len(self.text)
                            or not all(equal(self.text[pos + i], letter, self.flags)
                                       for i, letter in enumerate(literal))):
                        break
                    pos += len(literal)
                    pc += 1
                    if literal:
                        visited = frozenset()
                elif op == "LOOK":
                    found = self._execute(pc + 1, pos, stored, True)
                    kind = ins["kind"]
                    if kind == "NOT":
                        if found is not None:
                            break
                    else:
                        if found is None:
                            break
                        next_captures, next_pos = found
                        stored = next_captures
                        if kind == "ATOMIC":
                            if next_pos > pos:
                                visited = frozenset()
                            pos = next_pos
                    pc = ins["x"]
                elif op == "MATCH":
                    if partial or not self.full or pos == len(self.text):
                        return stored, pos
                    break
                else:
                    raise ValueError("unknown VM instruction " + op)
        return None

    def search(self, start=0):
        positions = [0] if self.full else range(start, len(self.text) + 1)
        for position in positions:
            captures = [None] * (2 * self.groups + 2)
            result = self._execute(0, position, captures, False)
            if result is not None:
                return result[0]
        return None
