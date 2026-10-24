class ConflictGraph:
    def __init__(self, vertices, student_courses):
        self.vertices = sorted(vertices)
        self.shared = {vertex: {} for vertex in self.vertices}
        for course_ids in student_courses:
            for index, first in enumerate(course_ids):
                for second in course_ids[index + 1:]:
                    self.shared[first][second] = self.shared[first].get(second, 0) + 1
                    self.shared[second][first] = self.shared[second].get(first, 0) + 1

    def neighbours(self, course_id):
        return self.shared.get(course_id, {})

    def degree(self, course_id):
        return len(self.neighbours(course_id))

    def shared_total(self, course_id):
        return sum(self.neighbours(course_id).values())

    def edges(self):
        return [
            (first, second, count)
            for first in self.vertices
            for second, count in sorted(self.shared[first].items())
            if first < second
        ]

    def components(self):
        seen = set()
        components = []
        for vertex in self.vertices:
            if vertex in seen:
                continue
            seen.add(vertex)
            component = [vertex]
            index = 0
            while index < len(component):
                for neighbour in self.shared[component[index]]:
                    if neighbour not in seen:
                        seen.add(neighbour)
                        component.append(neighbour)
                index += 1
            components.append(sorted(component))
        components.sort(key=lambda component: (-len(component), component[0]))
        return components

    def greedy_clique(self, candidates):
        clique = []
        while candidates:
            chosen = min(candidates, key=lambda course_id: (-self.degree(course_id), course_id))
            clique.append(chosen)
            candidates = [
                course_id for course_id in candidates if course_id in self.shared[chosen]
            ]
        return clique

    def kempe_chain(self, assignment, start, first_slot, second_slot):
        slots = (first_slot, second_slot)
        chain = [start]
        seen = {start}
        index = 0
        while index < len(chain):
            for neighbour in self.neighbours(chain[index]):
                if neighbour not in seen and assignment.get(neighbour) in slots:
                    seen.add(neighbour)
                    chain.append(neighbour)
            index += 1
        return sorted(chain)


def reachable(arrows, source, target):
    stack = [source]
    seen = {source}
    while stack:
        node = stack.pop()
        if node == target:
            return True
        for successor in arrows.get(node, []):
            if successor not in seen:
                seen.add(successor)
                stack.append(successor)
    return False
