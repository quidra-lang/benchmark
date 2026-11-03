"""The five safety properties and their persistent global records."""

from itertools import combinations


PROPERTIES = ("ELECTION_SAFETY", "LEADER_COMPLETENESS", "LOG_MATCHING",
              "STATE_MACHINE_SAFETY", "COMMITTED_KEPT")


class Checker:
    def __init__(self):
        self.violations = dict.fromkeys(PROPERTIES, 0)
        self.leaders = {}
        self.committed = {}
        self.applied = {}
        self.elected = 0
        self.log_checks = 0
        self.pair_checks = 0
        self.applies = 0
        self.truncations = 0
        self.removed = 0

    def leader(self, node):
        self.elected += 1
        if node.term not in self.leaders:
            self.leaders[node.term] = node.number
        elif self.leaders[node.term] != node.number:
            self.violations["ELECTION_SAFETY"] += 1
        if any(index > node.last_index or node.term_at(index) != term
               for index, (term, time) in self.committed.items()):
            self.violations["LEADER_COMPLETENESS"] += 1

    def commit(self, index, term, time):
        self.committed.setdefault(index, (term, time))

    def apply(self, index, entry, result):
        self.applies += 1
        if index not in self.applied:
            self.applied[index] = entry, result
        elif self.applied[index][0] != entry:
            self.violations["STATE_MACHINE_SAFETY"] += 1

    def truncate(self, first, entries):
        self.truncations += 1
        self.removed += len(entries)
        for index, entry in enumerate(entries, first):
            if index in self.committed and self.committed[index][0] == entry.term:
                self.violations["COMMITTED_KEPT"] += 1

    def check_logs(self, nodes):
        self.log_checks += 1
        for first, second in combinations(nodes, 2):
            self.pair_checks += 1
            limit = min(first.last_index, second.last_index)
            if first.log[:limit] == second.log[:limit]:
                continue
            greatest = 0
            for index in range(limit, 0, -1):
                if first.term_at(index) == second.term_at(index):
                    greatest = index
                    break
            if any(first.log[index] != second.log[index] for index in range(greatest)):
                self.violations["LOG_MATCHING"] += 1

    def lines(self, maximum_term):
        details = {
            "ELECTION_SAFETY": f"terms {maximum_term} leaders {len(self.leaders)} elected {self.elected}",
            "LEADER_COMPLETENESS": f"checks {self.elected} committed {len(self.committed)}",
            "LOG_MATCHING": f"checks {self.log_checks} pairs {self.pair_checks}",
            "STATE_MACHINE_SAFETY": f"applies {self.applies} indices {len(self.applied)}",
            "COMMITTED_KEPT": f"truncations {self.truncations} removed {self.removed}",
        }
        lines = []
        for name in PROPERTIES:
            violations = self.violations[name]
            verdict = "OK" if violations == 0 else "FAIL"
            lines.append(f"{name} {verdict} violations {violations} {details[name]}")
        return lines
