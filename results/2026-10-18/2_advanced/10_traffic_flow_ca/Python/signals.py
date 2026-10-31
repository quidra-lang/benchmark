class Phase:
    def __init__(self, token):
        duration, greens = token.split(":")
        self.duration = int(duration)
        self.token = greens
        self.greens = set() if greens == "-" else set(greens.split(","))


class Junction:
    def __init__(self, node, offset, phase_tokens):
        self.node = node
        self.offset = offset
        self.phases = [Phase(token) for token in phase_tokens]
        self.cycle = sum(phase.duration for phase in self.phases)
        self.incoming = []

    def phase_at(self, step):
        tau = (step - 1 + self.offset) % self.cycle
        for phase in self.phases:
            if tau < phase.duration:
                return phase
            tau -= phase.duration

    def green(self, segment_id, step):
        if not self.phases:
            return True
        return segment_id in self.phase_at(step).greens

    def plan_lines(self):
        if not self.phases:
            return [f"JUNCTION {self.node} unsignalized"]
        lines = [f"JUNCTION {self.node} signal cycle {self.cycle} offset {self.offset}"]
        begin = 0
        for number, phase in enumerate(self.phases, 1):
            end = begin + phase.duration - 1
            lines.append(f"  PHASE {number} {begin}-{end} {phase.token}")
            begin = end + 1
        return lines
