"""Register producers, source readiness and forwarding paths."""


def dependencies(instructions):
    last_writer = {}
    sources = []
    for index, instruction in enumerate(instructions):
        current = []
        for field in ("rs1", "rs2"):
            register = instruction[field]
            if register is not None and register != 0:
                current.append({"field": field, "register": register,
                                "producer": last_writer.get(register)})
        sources.append(current)
        destination = instruction["rd"]
        if destination is not None and destination != 0:
            last_writer[destination] = index
    return sources


def id_resolved(instruction, variant):
    if instruction["class"] == "JUMP" and instruction["rs1"] is None:
        return True
    return instruction["class"] in ("BRANCH", "JUMP") and variant["stage"] == "ID"


def ready_cycle(instruction, producer, producer_time, variant):
    if not variant["forwarding"]:
        return producer_time["W"] + 1
    result = producer_time["W"] if producer["class"] == "LOAD" else producer_time["M"]
    return result + int(id_resolved(instruction, variant))


def forwarding_path(instruction, producer_time, instruction_time, variant):
    if producer_time is None or not variant["forwarding"]:
        return "regfile"
    resolved = id_resolved(instruction, variant)
    use_cycle = instruction_time["X"] - 1 if resolved else instruction_time["X"]
    if producer_time["M"] == use_cycle:
        return "ex_mem"
    if not resolved and producer_time["W"] == use_cycle:
        return "mem_wb"
    return "regfile"
