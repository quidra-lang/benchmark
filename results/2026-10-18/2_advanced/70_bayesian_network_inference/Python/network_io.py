"""Read ordered network definitions, reordered samples, queries and settings."""

from collections import namedtuple
from pathlib import Path


Network = namedtuple("Network", "names states parents expert")


def read_network(path):
    lines = [line for line in Path(path).read_text(encoding="ascii").splitlines()
             if line and not line.startswith("#")]
    names, states, parents, expert, index = [], [], [], {}, {}
    position = 0
    while position < len(lines):
        fields = lines[position].split()
        position += 1
        if fields[0] == "VARIABLE":
            index[fields[1]] = len(names)
            names.append(fields[1])
            states.append(fields[2:])
            parents.append([])
        elif fields[0] == "PARENTS":
            parents[index[fields[1]]] = [index[name] for name in fields[2:]]
        else:
            variable = index[fields[1]]
            rows = 1
            for parent in parents[variable]:
                rows *= len(states[parent])
            expert[variable] = [list(map(float, line.split())) for line in lines[position:position + rows]]
            position += rows
    return Network(names, states, parents, expert)


def read_samples(path, network):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    columns = [network.names.index(name) for name in lines[0].split(",")]
    samples = []
    for line in lines[1:]:
        sample = [0] * len(network.names)
        for variable, name in zip(columns, line.split(",")):
            sample[variable] = network.states[variable].index(name)
        samples.append(sample)
    return samples


def read_inputs():
    network = read_network("input/network.txt")
    lines = Path("input/params.txt").read_text(encoding="ascii").splitlines()
    params = {"alpha": float(lines[0].split()[1]), "method": lines[1].split()[1],
              "order": [network.names.index(name) for name in lines[2].split()[1:]],
              "limit": int(lines[3].split()[1]), "seed": int(lines[4].split()[1]),
              "sources": [line.split()[2] for line in lines[5:]]}
    samples = read_samples("input/samples.csv", network)
    queries = Path("input/queries.txt").read_text(encoding="ascii").splitlines()
    return network, samples, queries, params
