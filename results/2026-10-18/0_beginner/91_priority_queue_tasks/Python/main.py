from heapq import heappush, heappop

operations = [
    "add email 3", "add backup 5", "add deploy 1", "run", "add report 3", "add test 2",
    "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run",
    "add build 1", "add docs 4", "run", "run",
]
queue = []
sequence = 0
for operation in operations:
    parts = operation.split()
    if parts[0] == "add":
        heappush(queue, (int(parts[2]), sequence, parts[1]))
        sequence += 1
    else:
        priority, _, name = heappop(queue)
        print(f"run: {name} (priority {priority})")
remaining = []
while queue:
    remaining.append(heappop(queue)[2])
print("remaining:", *remaining)
