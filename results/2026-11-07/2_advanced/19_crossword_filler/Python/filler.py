from grid import EMPTY


COMPLETE = "complete"
FAIL = "fail"
ABORT = "abort"
OUTCOMES = {COMPLETE: "filled", FAIL: "unfillable", ABORT: "budget"}
TRACE_LIMIT = 10


class GridState:
    def __init__(self, letters, words):
        self.letters = letters
        self.words = words
        self.used = {word for word in words if word is not None}

    def copy(self):
        return GridState(list(self.letters), list(self.words))

    def pattern(self, slot):
        return "".join(self.letters[cell] for cell in slot.cells)

    def assign(self, slot, word):
        filled = []
        for cell, letter in zip(slot.cells, word):
            if self.letters[cell] == EMPTY:
                self.letters[cell] = letter
                filled.append(cell)
        self.words[slot.index] = word
        self.used.add(word)
        return filled

    def unassign(self, slot, filled):
        for cell in filled:
            self.letters[cell] = EMPTY
        self.used.discard(self.words[slot.index])
        self.words[slot.index] = None


class Attempt:
    def __init__(self, layout, index, initial, min_score, budget):
        self.layout = layout
        self.index = index
        self.state = initial.copy()
        self.min_score = min_score
        self.budget = budget
        self.nodes = 0
        self.backtracks = 0
        self.prunes = 0
        self.dead_ends = 0
        self.sequence = []
        self.max_depth = 0
        self.best = initial.copy()
        self.failures = [0] * len(layout.slots)
        self.trace = []
        self.outcome = None

    def run(self):
        self.outcome = OUTCOMES[self.search()]

    def final_state(self):
        return self.state if self.outcome == "filled" else self.best

    def candidates(self, slot):
        return self.index.candidates(self.state.pattern(slot), self.min_score, self.state.used)

    def choose_slot(self):
        chosen = None
        chosen_words = None
        for slot in self.layout.slots:
            if self.state.words[slot.index] is None:
                words = self.candidates(slot)
                if chosen is None or len(words) < len(chosen_words):
                    chosen = slot
                    chosen_words = words
        return chosen, chosen_words

    def wiped_out_slot(self, slot):
        for other in slot.crossings:
            crossing = self.layout.slots[other]
            if self.state.words[other] is None and not self.candidates(crossing):
                return crossing
        return None

    def search(self):
        slot, words = self.choose_slot()
        if slot is None:
            return COMPLETE
        if not words:
            self.dead_ends += 1
            self.failures[slot.index] += 1
            return FAIL
        for word in words:
            if self.nodes == self.budget:
                return ABORT
            self.nodes += 1
            filled = self.state.assign(slot, word)
            self.sequence.append(slot)
            wiped = self.wiped_out_slot(slot)
            if self.nodes <= TRACE_LIMIT:
                mark = "" if wiped is None else "!"
                self.trace.append(slot.label + "=" + word + mark)
            if wiped is not None:
                self.prunes += 1
                self.failures[wiped.index] += 1
                result = FAIL
            else:
                if len(self.sequence) > self.max_depth:
                    self.max_depth = len(self.sequence)
                    self.best = self.state.copy()
                result = self.search()
            if result != FAIL:
                return result
            self.state.unassign(slot, filled)
            self.sequence.pop()
            self.backtracks += 1
        return FAIL
