class Attempt:
    def __init__(self, courses, graph, limit, candidate_slots):
        self.courses = courses
        self.graph = graph
        self.limit = limit
        self.candidate_slots = candidate_slots
        self.dead_ends = 0
        self.dead_end_course = None
        self.aborted = False
        self.chosen = []

    def saturation(self, course_id, assignment):
        neighbours = self.graph.neighbours(course_id)
        return len({assignment[other] for other in neighbours if other in assignment})

    def priority(self, course_id, assignment):
        return -self.saturation(course_id, assignment), -self.graph.degree(course_id), course_id

    def search(self, assignment):
        remaining = [course_id for course_id in self.courses if course_id not in assignment]
        if not remaining:
            return True
        course_id = min(remaining, key=lambda other: self.priority(other, assignment))
        self.chosen.append((course_id, self.saturation(course_id, assignment)))
        for slot in self.candidate_slots(course_id, assignment):
            assignment[course_id] = slot
            if self.search(assignment):
                return True
            del assignment[course_id]
            if self.aborted:
                return False
        self.chosen.pop()
        self.dead_ends += 1
        self.dead_end_course = course_id
        self.aborted = self.dead_ends > self.limit
        return False


def greedy_numbering(order, graph):
    numbers = {}
    for course_id in order:
        taken = {numbers[other] for other in graph.neighbours(course_id) if other in numbers}
        number = 1
        while number in taken:
            number += 1
        numbers[course_id] = number
    return max(numbers.values())
