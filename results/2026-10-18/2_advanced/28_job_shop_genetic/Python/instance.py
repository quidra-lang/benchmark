MIN_DURATION = 1
MAX_DURATION = 99


class Operation:
    def __init__(self, ident, job, index, machine, duration, head):
        self.ident = ident
        self.job = job
        self.index = index
        self.machine = machine
        self.duration = duration
        self.head = head
        self.tail = 0
        self.job_prev = None
        self.job_next = None
        self.code = f"J{job}-{index}"


class Job:
    def __init__(self, number, operations):
        self.number = number
        self.operations = operations
        self.work = sum(operation.duration for operation in operations)


class Machine:
    def __init__(self, number, operations):
        self.number = number
        self.operations = operations
        self.load = sum(operation.duration for operation in operations)
        self.head = min(operation.head for operation in operations)
        self.tail = min(operation.tail for operation in operations)
        self.bound = self.head + self.load + self.tail


class Instance:
    def __init__(self, machine_count, jobs, errors):
        self.machine_count = machine_count
        self.jobs = jobs
        self.errors = errors
        self.job_map = {job.number: job for job in jobs}
        self.operations = [operation for job in jobs for operation in job.operations]
        self.durations = [operation.duration for operation in self.operations]
        self.machines = [
            Machine(number, [op for op in self.operations if op.machine == number])
            for number in range(1, machine_count + 1)
        ]


def token_error(machine, duration, steps, machine_count):
    if not 1 <= machine <= machine_count:
        return f"unknown machine {machine}"
    if not MIN_DURATION <= duration <= MAX_DURATION:
        return f"bad duration {duration}"
    if any(machine == used for used, _ in steps):
        return f"repeated machine {machine}"
    return None


def read_steps(number, line, machine_count, errors):
    steps = []
    for index, token in enumerate(line.split(" "), 1):
        machine, duration = (int(part) for part in token.split(":"))
        message = token_error(machine, duration, steps, machine_count)
        if message is not None:
            errors.append(f"job {number} operation {index}: {message}")
            return None
        steps.append((machine, duration))
    return steps


def build_job(number, steps, first_ident):
    operations = []
    head = 0
    for index, (machine, duration) in enumerate(steps, 1):
        ident = first_ident + index - 1
        operations.append(Operation(ident, number, index, machine, duration, head))
        head += duration
    for previous, following in zip(operations, operations[1:]):
        previous.job_next = following.ident
        following.job_prev = previous.ident
    job = Job(number, operations)
    for operation in operations:
        operation.tail = job.work - operation.head - operation.duration
    return job


def load_instance(path):
    with open(path) as file:
        lines = file.read().splitlines()
    job_count, machine_count = (int(value) for value in lines[0].split(" "))
    jobs = []
    errors = []
    first_ident = 0
    for number in range(1, job_count + 1):
        steps = read_steps(number, lines[number], machine_count, errors)
        if steps is not None:
            jobs.append(build_job(number, steps, first_ident))
            first_ident += len(steps)
    return Instance(machine_count, jobs, errors)
