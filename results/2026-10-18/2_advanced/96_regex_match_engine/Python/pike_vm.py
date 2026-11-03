"""Priority-preserving Pike VM, with epsilon closure and per-list marks."""

from charset import assertion, test_any, test_char, test_class


class PikeVM:
    def __init__(self, program, flags, group_count, text, full=False):
        self.program = program
        self.flags = flags
        self.groups = group_count
        self.text = text
        self.full = full
        self.steps = 0

    def _add(self, threads, marks, pc, captures, pos):
        if pc in marks:
            return
        marks.add(pc)
        self.steps += 1
        ins = self.program[pc]
        op = ins["op"]
        if op == "JMP":
            self._add(threads, marks, ins["x"], captures, pos)
        elif op == "SPLIT":
            self._add(threads, marks, ins["x"], captures, pos)
            self._add(threads, marks, ins["y"], captures, pos)
        elif op == "SAVE":
            updated = captures.copy()
            updated[ins["slot"]] = pos
            self._add(threads, marks, pc + 1, updated, pos)
        elif op == "ASSERT":
            if assertion(ins["kind"], self.text, pos, self.flags):
                self._add(threads, marks, pc + 1, captures, pos)
        else:
            threads.append((pc, captures.copy()))

    def search(self, start=0):
        threads = []
        marks = set()
        cursor = start
        matched = None
        while True:
            if matched is None and (not self.full or cursor == start):
                self._add(threads, marks, 0,
                          [None] * (2 * self.groups + 2), cursor)
            following = []
            next_marks = set()
            for pc, captures in threads:
                self.steps += 1
                ins = self.program[pc]
                op = ins["op"]
                if op == "MATCH":
                    if not self.full or cursor == len(self.text):
                        matched = captures
                        break
                elif cursor < len(self.text):
                    works = (
                        test_char(self.text, cursor, ins["char"], self.flags)
                        if op == "CHAR" else
                        test_any(self.text, cursor, self.flags)
                        if op == "ANY" else
                        test_class(self.text, cursor, ins["set"], ins["neg"],
                                   self.flags)
                    )
                    if works:
                        self._add(following, next_marks, pc + 1,
                                  captures, cursor + 1)
            if cursor == len(self.text):
                return matched
            if not following and (matched is not None or self.full):
                return matched
            threads = following
            marks = next_marks
            cursor += 1
