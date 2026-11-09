from pathlib import Path


def read_inputs():
    cases = []
    deaths = []
    rows = Path("input/cases.csv").read_text(encoding="ascii").splitlines()
    for line in rows[1:]:
        _, count, dead = map(int, line.split(","))
        cases.append(count)
        deaths.append(dead)
    groups = []
    contacts = []
    for line in Path("input/population.txt").read_text(encoding="ascii").splitlines():
        kind, *values = line.split(" ")
        if kind == "group":
            groups.append((values[0], int(values[1]), float(values[2])))
        else:
            contacts.append(list(map(float, values)))
    interventions = []
    for line in Path("input/interventions.txt").read_text(encoding="ascii").splitlines():
        day, multiplier = line.split(" ")
        interventions.append((int(day), float(multiplier)))
    params = {"scenario": [], "contact_change": []}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        name, *values = line.split(" ")
        if name == "scenario":
            params[name].append((values[0], float(values[1])))
        elif name == "contact_change":
            params[name].append((values[0], values[1], float(values[2])))
        elif name in ("holdout", "death_lag", "generation", "horizon"):
            params[name] = int(values[0])
        elif name in ("milestones", "golden"):
            params[name] = tuple(map(int, values))
        elif name in ("beta_grid", "rho_grid"):
            params[name] = (float(values[0]), float(values[1]), int(values[2]))
        elif name == "nelder_mead":
            params[name] = (*map(float, values[:4]), int(values[4]))
        elif name in ("initial", "simplex"):
            params[name] = tuple(map(float, values))
        else:
            params[name] = float(values[0])
    return cases, deaths, groups, contacts, interventions, params


def write_outputs(outputs):
    folder = Path("output")
    folder.mkdir(parents=True, exist_ok=True)
    for name, lines in outputs.items():
        text = "\n".join(lines) + ("\n" if lines else "")
        (folder / name).write_text(text, encoding="ascii", newline="\n")
