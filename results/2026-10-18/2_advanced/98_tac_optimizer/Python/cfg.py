"""Block construction, ordered DFS, dominance, and merged natural loops."""


class Block:
    def __init__(self, number, labels, start):
        self.number = number
        self.labels = tuple(labels)
        self.start = start
        self.end = None
        self.instructions = []
        self.predecessors = []
        self.successors = []


class Loop:
    def __init__(self, header, latches, blocks):
        self.header = header
        self.latches = tuple(latches)
        self.blocks = blocks
        self.depth = 0
        self.exits = set()
        self.outside = set()


class CFG:
    def __init__(self, function):
        self.function = function
        self.blocks = {}
        self.instructions = {}
        self.positions = {}
        self.block_of = {}
        self.split_blocks()
        self.connect_blocks()
        self.depth_first_search()
        self.compute_dominators()
        self.compute_loops()

    def split_blocks(self):
        pending, first_label = [], None
        current, previous_kind = None, None
        for index, line in enumerate(self.function.code):
            if isinstance(line, str):
                if not pending:
                    first_label = index
                pending.append(line)
                continue
            number = len(self.instructions) + 1
            if current is None or pending or previous_kind in ("goto", "if", "return"):
                start = first_label if pending else index
                if current is not None:
                    current.end = start
                current = Block(len(self.blocks) + 1, pending, start)
                self.blocks[current.number] = current
                pending = []
            self.instructions[number] = line
            self.positions[number] = index
            self.block_of[number] = current.number
            current.instructions.append(number)
            previous_kind = line.kind
        current.end = len(self.function.code)

    def connect_blocks(self):
        labels = {label: number for number, block in self.blocks.items() for label in block.labels}
        for number, block in self.blocks.items():
            last = self.instructions[block.instructions[-1]]
            if last.kind == "goto":
                block.successors = [labels[last.name]]
            elif last.kind == "if":
                block.successors = list(dict.fromkeys((number + 1, labels[last.name])))
            elif last.kind != "return":
                block.successors = [number + 1]
            for successor in block.successors:
                self.blocks[successor].predecessors.append(number)

    def depth_first_search(self):
        self.reachable = {1}
        self.postorder = []
        stack = [(1, iter(self.blocks[1].successors))]
        while stack:
            number, successors = stack[-1]
            successor = next(successors, None)
            if successor is None:
                self.postorder.append(number)
                stack.pop()
            elif successor not in self.reachable:
                self.reachable.add(successor)
                stack.append((successor, iter(self.blocks[successor].successors)))
        self.reverse_postorder = self.postorder[::-1]
        self.reachable_predecessors = {
            number: [predecessor for predecessor in self.blocks[number].predecessors
                     if predecessor in self.reachable]
            for number in self.reachable
        }

    def compute_dominators(self):
        self.dominators = {number: set(self.reachable) for number in self.reachable}
        self.dominators[1] = {1}
        changed = True
        while changed:
            changed = False
            for number in self.reverse_postorder[1:]:
                predecessors = self.reachable_predecessors[number]
                value = set(self.dominators[predecessors[0]])
                for predecessor in predecessors[1:]:
                    value.intersection_update(self.dominators[predecessor])
                value.add(number)
                if value != self.dominators[number]:
                    self.dominators[number] = value
                    changed = True
        self.immediate = {1: None}
        for number in sorted(self.reachable - {1}):
            self.immediate[number] = max(self.dominators[number] - {number},
                                         key=lambda parent: len(self.dominators[parent]))

    def compute_loops(self):
        self.loops = []
        for header in sorted(self.reachable):
            latches = [number for number in self.reachable_predecessors[header]
                       if header in self.dominators[number]]
            if not latches:
                continue
            members = {header, *latches}
            pending = [number for number in latches if number != header]
            while pending:
                number = pending.pop()
                for predecessor in self.reachable_predecessors[number]:
                    if predecessor not in members:
                        members.add(predecessor)
                        pending.append(predecessor)
            self.loops.append(Loop(header, latches, members))
        self.depth = {number: sum(number in loop.blocks for loop in self.loops)
                      for number in self.blocks}
        for loop in self.loops:
            loop.depth = sum(loop.header in other.blocks for other in self.loops)
            for number in loop.blocks:
                block = self.blocks[number]
                outside = set(block.successors) - loop.blocks
                loop.outside.update(outside)
                if outside or self.instructions[block.instructions[-1]].kind == "return":
                    loop.exits.add(number)
