def kahn(courses, pairs):
    graph = {course: [] for course in courses}
    indegree = dict.fromkeys(courses, 0)
    for source, target in pairs:
        graph[source].append(target)
        indegree[target] += 1
    ready = sorted(course for course in courses if indegree[course] == 0)
    order = []
    while ready:
        course = ready.pop(0)
        order.append(course)
        for target in graph[course]:
            indegree[target] -= 1
            if indegree[target] == 0:
                ready.append(target)
        ready.sort()
    return order, sorted(set(courses) - set(order))


courses1 = "physics algebra graphics programming statistics calculus databases algorithms".split()
pairs1 = [
    ("calculus", "physics"), ("algebra", "calculus"), ("programming", "algorithms"),
    ("algebra", "statistics"), ("algorithms", "databases"), ("statistics", "databases"),
    ("calculus", "graphics"), ("algorithms", "graphics"), ("physics", "graphics"),
]
courses2 = "music ecology art geology biology chemistry".split()
pairs2 = [
    ("music", "art"), ("art", "ecology"), ("biology", "chemistry"),
    ("chemistry", "ecology"), ("ecology", "geology"), ("geology", "chemistry"),
]
order1, _ = kahn(courses1, pairs1)
order2, cycle = kahn(courses2, pairs2)
print("order: " + " -> ".join(order1))
print("order: " + " -> ".join(order2))
print("cycle:", *cycle)
