"""Space-time A* with ordered actions, prohibitions and shared run budget."""

from heapq import heappop, heappush

from grid_map import destinations


class BudgetExceeded(Exception):
    """The expansion that exceeds the common low-level budget was counted."""


class Budget:
    def __init__(self, limit=None):
        self.limit = limit
        self.searches = 0
        self.expansions = 0

    def count_expansion(self):
        self.expansions += 1
        if self.limit is not None and self.expansions > self.limit:
            raise BudgetExceeded


class Prohibitions:
    def __init__(self, states=None, moves=None, permanent=None):
        self.states = set() if states is None else set(states)
        self.moves = set() if moves is None else set(moves)
        self.permanent = set() if permanent is None else set(permanent)

    def copy(self):
        return Prohibitions(self.states, self.moves, self.permanent)

    def state_allowed(self, cell, time):
        return ((cell, time) not in self.states
                and not any(position == cell and from_time <= time
                            for position, from_time in self.permanent))

    def action_allowed(self, source, destination, time):
        return (self.state_allowed(destination, time)
                and (source == destination
                     or (source, destination, time) not in self.moves))

    def arrival_allowed(self, goal):
        forbidden = [time for cell, time in self.states if cell == goal]
        return max(forbidden) + 1 if forbidden else 0


def reserve_path(prohibitions, path, start_time=0, permanent=False):
    for step, cell in enumerate(path):
        time = start_time + step
        prohibitions.states.add((cell, time))
        if step and cell != path[step - 1]:
            prohibitions.moves.add((cell, path[step - 1], time))
    if permanent:
        prohibitions.permanent.add((path[-1], start_time + len(path) - 1))


def search(grid, agent, distance, start, t0, prohibitions, tmax,
           budget, window=False):
    """Search a shortest walk; return (path or None, expansions within search).

    A generated state is never inserted a second time. Heap priorities are
    (f, -g, insertion number), as specified by the benchmark.
    """
    budget.searches += 1
    beginning = budget.expansions
    goal = agent["goal"]
    arrival = prohibitions.arrival_allowed(goal)
    heap = []
    insertion = 0
    start_state = (start, t0)
    parents = {start_state: None}
    heappush(heap, (distance[start], 0, 0, start_state))

    while heap:
        _, _, _, state = heappop(heap)
        budget.count_expansion()
        cell, time = state
        if (cell == goal and time >= arrival) or (window and time == tmax):
            reversed_cells = []
            current = state
            while current is not None:
                reversed_cells.append(current[0])
                current = parents[current]
            return list(reversed(reversed_cells)), budget.expansions - beginning
        if time == tmax:
            continue
        for destination, _ in destinations(grid, cell):
            next_time = time + 1
            next_state = (destination, next_time)
            if (destination not in distance
                    or next_state in parents
                    or not prohibitions.action_allowed(cell, destination, next_time)):
                continue
            insertion += 1
            parents[next_state] = state
            g = next_time - t0
            h = distance[destination]
            heappush(heap, (g + h, -g, insertion, next_state))
    return None, budget.expansions - beginning
