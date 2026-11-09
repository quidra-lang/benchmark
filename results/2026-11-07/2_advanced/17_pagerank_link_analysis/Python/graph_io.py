import os


class Page:
    def __init__(self, ident, host, title):
        self.ident = ident
        self.host = host
        self.title = title
        self.words = title.split(" ")


class LinkRecord:
    def __init__(self, line, source, target):
        self.line = line
        self.source = source
        self.target = target


class Query:
    def __init__(self, number, words, seeds):
        self.number = number
        self.words = words
        self.seeds = seeds


class Settings:
    def __init__(self, entries):
        self.damping = float(entries["DAMPING"][0])
        self.iterations = int(entries["PAGERANK_ITERATIONS"][0])
        self.tolerance = float(entries["TOLERANCE"][0])
        self.sweep = [float(value) for value in entries["DAMPING_SWEEP"]]
        self.trusted = [int(value) for value in entries["TRUSTED"]]
        self.spam_top = int(entries["SPAM_TOP"][0])
        self.spam_threshold = float(entries["SPAM_THRESHOLD"][0])
        self.hits_iterations = int(entries["HITS_ITERATIONS"][0])
        self.top_k = int(entries["TOP_K"][0])
        self.root_limit = int(entries["ROOT_LIMIT"][0])
        self.neighbor_limit = int(entries["NEIGHBOR_LIMIT"][0])


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_pages(path):
    pages = []
    for text in read_lines(path)[1:]:
        ident, host, title = text.split(",")
        pages.append(Page(int(ident), host, title))
    return pages


def read_links(path):
    records = []
    for number, text in enumerate(read_lines(path)[1:], 2):
        source, target = text.split(",")
        records.append(LinkRecord(number, int(source), int(target)))
    return records


def read_queries(path):
    queries = []
    for number, text in enumerate(read_lines(path), 1):
        words, seeds = text.split(" | ")
        queries.append(Query(number, words.split(" "), [int(seed) for seed in seeds.split(" ")]))
    return queries


def read_settings(path):
    entries = {}
    for text in read_lines(path):
        keyword, *values = text.split(" ")
        entries[keyword] = values
    return Settings(entries)


def read_input(directory):
    pages = read_pages(os.path.join(directory, "pages.csv"))
    records = read_links(os.path.join(directory, "links.csv"))
    queries = read_queries(os.path.join(directory, "queries.txt"))
    settings = read_settings(os.path.join(directory, "params.txt"))
    return pages, records, queries, settings
