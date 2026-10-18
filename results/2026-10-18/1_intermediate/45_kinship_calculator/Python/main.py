from math import gcd
import sys


SCALE = 1 << 37
SEX_INDEX = {"M": 0, "F": 1, "X": 2}
ORDINALS = (
    "first", "second", "third", "fourth", "fifth",
    "sixth", "seventh", "eighth", "ninth", "tenth",
)
TERMS = {
    "parent": ("father", "mother", "parent"),
    "child": ("son", "daughter", "child"),
    "sibling": ("brother", "sister", "sibling"),
    "pibling": ("uncle", "aunt", "pibling"),
    "nibling": ("nephew", "niece", "nibling"),
    "spouse": ("husband", "wife", "spouse"),
    "late": ("late husband", "late wife", "late spouse"),
    "survivor": ("widower", "widow", "surviving spouse"),
    "ex": ("ex-husband", "ex-wife", "ex-spouse"),
    "stepparent": ("stepfather", "stepmother", "stepparent"),
    "stepchild": ("stepson", "stepdaughter", "stepchild"),
    "stepsibling": ("stepbrother", "stepsister", "stepsibling"),
    "stepgrandparent": ("stepgrandfather", "stepgrandmother", "stepgrandparent"),
    "stepgrandchild": ("stepgrandson", "stepgranddaughter", "stepgrandchild"),
    "parent-in-law": ("father-in-law", "mother-in-law", "parent-in-law"),
    "child-in-law": ("son-in-law", "daughter-in-law", "child-in-law"),
    "sibling-in-law": ("brother-in-law", "sister-in-law", "sibling-in-law"),
}
STEPS = {
    "parent": ("parent", None),
    "father": ("parent", "M"),
    "mother": ("parent", "F"),
    "child": ("child", None),
    "son": ("child", "M"),
    "daughter": ("child", "F"),
    "sibling": ("sibling", None),
    "brother": ("sibling", "M"),
    "sister": ("sibling", "F"),
    "spouse": ("spouse", None),
    "husband": ("spouse", "M"),
    "wife": ("spouse", "F"),
}
MODIFYING = ("PERSON", "DEATH", "REMOVE", "PARENT", "UNPARENT", "SPOUSE", "DIVORCE")


class CommandError(Exception):
    pass


def gendered(kind, sex):
    return TERMS[kind][SEX_INDEX[sex]]


def generation_prefix(generations):
    if generations == 1:
        return ""
    return "great-" * (generations - 2) + "grand"


def ordinal(number):
    if number <= len(ORDINALS):
        return ORDINALS[number - 1]
    if number % 100 in (11, 12, 13):
        suffix = "th"
    elif number % 10 == 1:
        suffix = "st"
    elif number % 10 == 2:
        suffix = "nd"
    elif number % 10 == 3:
        suffix = "rd"
    else:
        suffix = "th"
    return f"{number}{suffix}"


def removal(distance):
    if distance == 0:
        return ""
    if distance == 1:
        return " once removed"
    if distance == 2:
        return " twice removed"
    return f" {distance} times removed"


def kinship_term(da, db, sex):
    if da == 0 and db == 0:
        return "self"
    if da == 0:
        return generation_prefix(db) + gendered("parent", sex)
    if db == 0:
        return generation_prefix(da) + gendered("child", sex)
    if da == 1 and db == 1:
        return gendered("sibling", sex)
    if da == 1:
        return generation_prefix(db - 1) + gendered("pibling", sex)
    if db == 1:
        return generation_prefix(da - 1) + gendered("nibling", sex)
    return ordinal(min(da, db) - 1) + " cousin" + removal(abs(da - db))


def life_years(person):
    death = "" if person.death is None else str(person.death)
    return f"{person.birth}-{death}"


def fraction_text(value):
    divisor = gcd(value, SCALE)
    return f"{value // divisor}/{SCALE // divisor}"


class Person:
    def __init__(self, ident, sex, birth, name):
        self.ident = ident
        self.sex = sex
        self.birth = birth
        self.name = name
        self.death = None
        self.parents = []

    def copy(self):
        person = Person(self.ident, self.sex, self.birth, self.name)
        person.death = self.death
        person.parents = list(self.parents)
        return person


class Marriage:
    def __init__(self, first, second, start):
        self.first = first
        self.second = second
        self.start = start
        self.end = None
        self.status = "current"
        self.died = None

    def contains(self, x):
        return x == self.first or x == self.second

    def other(self, x):
        return self.second if x == self.first else self.first

    def copy(self):
        record = Marriage(self.first, self.second, self.start)
        record.end = self.end
        record.status = self.status
        record.died = self.died
        return record


class Apex:
    def __init__(self, person, da, db, shares):
        self.person = person
        self.da = da
        self.db = db
        self.shares = shares

    def blood_term(self, sex):
        if self.shares == 1:
            prefix = "half-"
        elif self.shares >= 4:
            prefix = "double "
        else:
            prefix = ""
        return prefix + kinship_term(self.da, self.db, sex)


class Family:
    def __init__(self):
        self.persons = {}
        self.marriages = []

    def copy(self):
        family = Family()
        family.persons = {x: person.copy() for x, person in self.persons.items()}
        family.marriages = [record.copy() for record in self.marriages]
        return family

    def person(self, x):
        if x not in self.persons:
            raise CommandError(f"UNKNOWN PERSON {x}")
        return self.persons[x]

    def sex(self, x):
        return self.persons[x].sex

    def age_key(self, x):
        return self.persons[x].birth, x

    def person_list(self, ids):
        ordered = sorted(ids, key=self.age_key)
        return " ".join(ordered) if ordered else "-"

    def parents(self, x):
        return self.persons[x].parents

    def children(self, x):
        return [y for y, person in self.persons.items() if x in person.parents]

    def common_parents(self, x, y):
        return sum(p in self.parents(y) for p in self.parents(x))

    def are_siblings(self, x, y):
        return x != y and self.common_parents(x, y) > 0

    def siblings(self, x):
        return [y for y in self.persons if self.are_siblings(x, y)]

    def have_common_child(self, x, y):
        return any(x in person.parents and y in person.parents for person in self.persons.values())

    def records_of(self, x):
        return [record for record in self.marriages if record.contains(x)]

    def current_record(self, x):
        for record in self.marriages:
            if record.status == "current" and record.contains(x):
                return record
        return None

    def spouse(self, x):
        record = self.current_record(x)
        return None if record is None else record.other(x)

    def last_record(self, x, y):
        last = None
        for record in self.marriages:
            if record.contains(x) and record.contains(y):
                last = record
        return last

    def partners(self, x):
        latest = {}
        for record in self.records_of(x):
            latest[record.other(x)] = record
        return {y for y, record in latest.items() if record.status != "divorced"}

    def step_related(self, parents_x, parents_y):
        for p in parents_x:
            partners = self.partners(p)
            if any(q in partners for q in parents_y):
                return True
        return False

    def generation_distances(self, start, upward):
        distances = {start: 0}
        frontier = [start]
        while frontier:
            following = []
            for x in frontier:
                for y in self.parents(x) if upward else self.children(x):
                    if y not in distances:
                        distances[y] = distances[x] + 1
                        following.append(y)
            frontier = following
        return distances

    def lineage(self, x, upward):
        distances = self.generation_distances(x, upward)
        return sorted((g, y) for y, g in distances.items() if y != x)

    def is_ancestor(self, x, y):
        return x != y and x in self.generation_distances(y, True)

    def grandparents(self, x):
        return [y for y, g in self.generation_distances(x, True).items() if g == 2]

    def apex(self, a, b):
        up_a = self.generation_distances(a, True)
        up_b = self.generation_distances(b, True)
        if a in up_b:
            return Apex(a, 0, up_b[a], 0)
        if b in up_a:
            return Apex(b, up_a[b], 0, 0)
        best = min(
            ((up_a[c] + up_b[c], up_a[c], c) for c in up_a if c in up_b),
            default=None,
        )
        if best is None:
            return None
        total, da, c = best
        db = total - da
        shares = sum(1 for y in up_a if y in up_b and up_a[y] == da and up_b[y] == db)
        return Apex(c, da, db, shares)

    def relationship(self, a, b, sex):
        if a == b:
            return ["self"]
        terms = []
        apex = self.apex(a, b)
        if apex is not None:
            terms.append(apex.blood_term(sex))
        record = self.last_record(a, b)
        if record is None:
            if self.have_common_child(a, b):
                terms.append("co-parent")
        elif record.status == "current":
            terms.append(gendered("spouse", sex))
        elif record.status == "widowed":
            terms.append(gendered("late" if record.died == a else "survivor", sex))
        else:
            terms.append(gendered("ex", sex))
        parents_a = self.parents(a)
        parents_b = self.parents(b)
        partners_a = self.partners(a)
        partners_b = self.partners(b)
        if a not in parents_b and any(p in partners_a for p in parents_b):
            terms.append(gendered("stepparent", sex))
        if b not in parents_a and any(p in partners_b for p in parents_a):
            terms.append(gendered("stepchild", sex))
        if self.common_parents(a, b) == 0 and self.step_related(parents_a, parents_b):
            terms.append(gendered("stepsibling", sex))
        if not self.is_ancestor(a, b) and any(g in partners_a for g in self.grandparents(b)):
            terms.append(gendered("stepgrandparent", sex))
        if not self.is_ancestor(b, a) and any(g in partners_b for g in self.grandparents(a)):
            terms.append(gendered("stepgrandchild", sex))
        if any(a in self.parents(q) for q in partners_b):
            terms.append(gendered("parent-in-law", sex))
        if any(b in self.parents(q) for q in partners_a):
            terms.append(gendered("child-in-law", sex))
        sibling_of_partner = any(self.are_siblings(a, q) for q in partners_b)
        partner_of_sibling = any(self.are_siblings(q, b) for q in partners_a)
        if sibling_of_partner or partner_of_sibling:
            terms.append(gendered("sibling-in-law", sex))
        return terms

    def relationship_text(self, a, b):
        terms = self.relationship(a, b, self.sex(a))
        return ", ".join(terms) if terms else "no relation"

    def kinship_coefficient(self, a, b, memo):
        key = (min(a, b), max(a, b))
        if key in memo:
            return memo[key]
        if a == b:
            value = (SCALE + self.inbreeding_coefficient(a, memo)) // 2
        else:
            x, y = (a, b) if self.persons[a].birth >= self.persons[b].birth else (b, a)
            value = sum(self.kinship_coefficient(p, y, memo) for p in self.parents(x)) // 2
        memo[key] = value
        return value

    def inbreeding_coefficient(self, x, memo):
        parents = self.parents(x)
        if len(parents) < 2:
            return 0
        return self.kinship_coefficient(parents[0], parents[1], memo)

    def lineage_length(self, x, memo):
        if x not in memo:
            heights = [self.lineage_length(p, memo) for p in self.parents(x)]
            memo[x] = 1 + max(heights, default=0)
        return memo[x]

    def upward_path(self, start, depths):
        path = [start]
        while depths[path[-1]] > 0:
            current = path[-1]
            path.append(min(
                p for p in self.parents(current)
                if p in depths and depths[p] == depths[current] - 1
            ))
        return path

    def census_status(self, x, year):
        last = None
        for record in self.records_of(x):
            if record.start <= year:
                last = record
        if last is None:
            return "single"
        if last.end is None or last.end > year:
            return f"married {last.other(x)}"
        return last.status

    def step_targets(self, x, kind):
        if kind == "parent":
            return self.parents(x)
        if kind == "child":
            return self.children(x)
        if kind == "sibling":
            return self.siblings(x)
        spouse = self.spouse(x)
        return [] if spouse is None else [spouse]


class KinshipCalculator:
    def __init__(self):
        self.family = Family()
        self.history = []
        self.output = []

    def emit(self, line):
        self.output.append(line)

    def add_person(self, arguments):
        x, sex, birth, name = arguments
        if x in self.family.persons:
            raise CommandError(f"DUPLICATE PERSON {x}")
        self.family.persons[x] = Person(x, sex, int(birth), name)
        self.emit(f"ADDED {x} {name} {sex} {birth}")

    def record_death(self, arguments):
        x, year_text = arguments
        year = int(year_text)
        family = self.family
        person = family.person(x)
        if person.death is not None:
            raise CommandError(f"ALREADY DECEASED {x}")
        years = [person.birth]
        for record in family.records_of(x):
            years.append(record.start)
            if record.end is not None:
                years.append(record.end)
        if year < max(years):
            raise CommandError(f"BAD YEAR {x}")
        late = [c for c in family.children(x) if family.persons[c].birth > year + 1]
        if late:
            raise CommandError(f"AFTER DEATH {min(late)} {x}")
        person.death = year
        record = family.current_record(x)
        if record is None:
            self.emit(f"DIED {x} {year}")
            return
        record.end = year
        record.status = "widowed"
        record.died = x
        self.emit(f"DIED {x} {year} spouse={record.other(x)}")

    def remove_person(self, arguments):
        x = arguments[0]
        family = self.family
        family.person(x)
        for person in family.persons.values():
            if x in person.parents:
                person.parents.remove(x)
        family.marriages = [record for record in family.marriages if not record.contains(x)]
        del family.persons[x]
        self.emit(f"REMOVED {x}")

    def link_parent(self, arguments):
        child_id, parent_id = arguments
        family = self.family
        child = family.person(child_id)
        parent = family.person(parent_id)
        if child_id == parent_id:
            raise CommandError(f"SAME PERSON {child_id}")
        if parent_id in child.parents:
            raise CommandError(f"ALREADY PARENT {child_id} {parent_id}")
        if len(child.parents) == 2:
            raise CommandError(f"TOO MANY PARENTS {child_id}")
        if family.is_ancestor(child_id, parent_id):
            raise CommandError(f"CYCLE {child_id} {parent_id}")
        if parent.birth + 12 > child.birth:
            raise CommandError(f"AGE GAP {child_id} {parent_id}")
        if parent.death is not None and parent.death + 1 < child.birth:
            raise CommandError(f"AFTER DEATH {child_id} {parent_id}")
        child.parents.append(parent_id)
        self.emit(f"LINKED {child_id} {parent_id} {gendered('parent', parent.sex)}")

    def unlink_parent(self, arguments):
        child_id, parent_id = arguments
        child = self.family.person(child_id)
        self.family.person(parent_id)
        if parent_id not in child.parents:
            raise CommandError(f"NOT PARENT {child_id} {parent_id}")
        child.parents.remove(parent_id)
        self.emit(f"UNLINKED {child_id} {parent_id}")

    def marry(self, arguments):
        first_id, second_id, year_text = arguments
        year = int(year_text)
        family = self.family
        couple = ((first_id, family.person(first_id)), (second_id, family.person(second_id)))
        if first_id == second_id:
            raise CommandError(f"SAME PERSON {first_id}")
        for x, person in couple:
            if person.death is not None:
                raise CommandError(f"DECEASED {x}")
        for x, person in couple:
            if family.spouse(x) is not None:
                raise CommandError(f"ALREADY MARRIED {x}")
        if (
            family.is_ancestor(first_id, second_id)
            or family.is_ancestor(second_id, first_id)
            or family.are_siblings(first_id, second_id)
        ):
            raise CommandError(f"CLOSE KIN {first_id} {second_id}")
        for x, person in couple:
            if year < person.birth + 16:
                raise CommandError(f"TOO YOUNG {x}")
        for x, person in couple:
            records = family.records_of(x)
            if any(record.end is not None and record.end >= year for record in records):
                raise CommandError(f"BAD YEAR {x}")
        family.marriages.append(Marriage(first_id, second_id, year))
        self.emit(f"MARRIED {first_id} {second_id} {year}")

    def divorce(self, arguments):
        first_id, second_id, year_text = arguments
        year = int(year_text)
        family = self.family
        family.person(first_id)
        family.person(second_id)
        if family.spouse(first_id) != second_id:
            raise CommandError(f"NOT MARRIED {first_id} {second_id}")
        record = family.current_record(first_id)
        if year <= record.start:
            raise CommandError(f"BAD YEAR {first_id}")
        record.end = year
        record.status = "divorced"
        self.emit(f"DIVORCED {first_id} {second_id} {year}")

    def undo(self, arguments):
        if not self.history:
            raise CommandError("NOTHING TO UNDO")
        line, family = self.history.pop()
        self.family = family
        self.emit(f"UNDONE {line}")

    def info(self, arguments):
        x = arguments[0]
        family = self.family
        person = family.person(x)
        self.emit(f"INFO {x} {person.name} {person.sex} {life_years(person)}")
        self.emit(f"  parents: {family.person_list(person.parents)}")
        for record in family.records_of(x):
            end = "" if record.end is None else str(record.end)
            self.emit(f"  marriage: {record.other(x)} {record.start}-{end} {record.status}")
        self.emit(f"  children: {family.person_list(family.children(x))}")
        self.emit(f"  siblings: {family.person_list(family.siblings(x))}")
        inbreeding = family.inbreeding_coefficient(x, {})
        self.emit(f"  inbreeding: {fraction_text(inbreeding)}")

    def relation(self, arguments):
        a, b = arguments
        self.family.person(a)
        self.family.person(b)
        self.emit(f"RELATION {a} {b}: {self.family.relationship_text(a, b)}")

    def relatives(self, arguments):
        x = arguments[0]
        family = self.family
        family.person(x)
        lines = []
        for y in sorted(family.persons):
            if y == x:
                continue
            terms = family.relationship(y, x, family.sex(y))
            if terms:
                lines.append(f"  {y}: {', '.join(terms)}")
        self.emit(f"RELATIVES {x} {len(lines)}")
        self.output.extend(lines)

    def who(self, arguments):
        x = arguments[0]
        query = " ".join(arguments[1:])
        family = self.family
        family.person(x)
        lines = []
        for y in sorted(family.persons):
            if y == x:
                continue
            terms = family.relationship(y, x, family.sex(y))
            neutral_terms = family.relationship(y, x, "X")
            for term, neutral in zip(terms, neutral_terms):
                if query in (term, neutral):
                    lines.append(f"  {y}: {term}")
                    break
        self.emit(f"WHO {x} {query} {len(lines)}")
        self.output.extend(lines)

    def path(self, arguments):
        a, b = arguments
        family = self.family
        family.person(a)
        family.person(b)
        apex = family.apex(a, b)
        if apex is None:
            self.emit(f"PATH {a} {b} none")
            return
        depths = family.generation_distances(apex.person, False)
        descent = family.upward_path(b, depths)[:-1]
        descent.reverse()
        route = family.upward_path(a, depths) + descent
        self.emit(f"PATH {a} {b} {apex.da + apex.db}: {' '.join(route)}")

    def common(self, arguments):
        a, b = arguments
        family = self.family
        family.person(a)
        family.person(b)
        up_a = family.generation_distances(a, True)
        up_b = family.generation_distances(b, True)
        shared = {c for c in up_a if c in up_b}
        nearest = [
            c for c in shared
            if not any(child in shared for child in family.children(c))
        ]
        nearest.sort(key=lambda c: (up_a[c] + up_b[c], c))
        self.emit(f"COMMON {a} {b} {len(nearest)}")
        for c in nearest:
            self.emit(f"  {c} {up_a[c]} {up_b[c]}")

    def ancestors(self, arguments):
        x = arguments[0]
        family = self.family
        family.person(x)
        entries = family.lineage(x, True)
        self.emit(f"ANCESTORS {x} {len(entries)}")
        for g, y in entries:
            self.emit(f"  {g} {y} {kinship_term(0, g, family.sex(y))}")

    def descendants(self, arguments):
        x = arguments[0]
        family = self.family
        family.person(x)
        entries = family.lineage(x, False)
        self.emit(f"DESCENDANTS {x} {len(entries)}")
        for g, y in entries:
            self.emit(f"  {g} {y} {kinship_term(g, 0, family.sex(y))}")

    def cousins(self, arguments):
        x, degree_text = arguments
        degree = int(degree_text)
        family = self.family
        family.person(x)
        matches = []
        for y in family.persons:
            if y == x:
                continue
            apex = family.apex(y, x)
            if apex is None or apex.da < 2 or apex.db < 2:
                continue
            if min(apex.da, apex.db) - 1 == degree:
                matches.append((abs(apex.da - apex.db), y, apex.blood_term(family.sex(y))))
        matches.sort()
        self.emit(f"COUSINS {x} {degree} {len(matches)}")
        for _, y, term in matches:
            self.emit(f"  {y} {term}")

    def siblings(self, arguments):
        x = arguments[0]
        family = self.family
        family.person(x)
        parents = family.parents(x)
        entries = []
        earlier = 0
        for y in sorted(family.persons, key=family.age_key):
            if y == x:
                continue
            shared = family.common_parents(x, y)
            if shared == 2:
                kind = "full"
            elif shared == 1:
                kind = "half"
            elif family.step_related(parents, family.parents(y)):
                kind = "step"
            else:
                continue
            if kind != "step" and family.age_key(y) < family.age_key(x):
                earlier += 1
            entries.append(f"  {y} {kind} {family.persons[y].birth}")
        self.emit(f"SIBLINGS {x} {len(entries)} order={earlier + 1}")
        self.output.extend(entries)

    def generations(self, arguments):
        x = arguments[0]
        family = self.family
        family.person(x)
        groups = {}
        for g, y in family.lineage(x, False):
            groups.setdefault(g, []).append(family.persons[y])
        self.emit(f"GENERATIONS {x} {len(groups)}")
        for g in sorted(groups):
            members = groups[g]
            births = [person.birth for person in members]
            living = sum(person.death is None for person in members)
            self.emit(f"  {g} {len(members)} {living} {min(births)}-{max(births)}")

    def visit(self, x, depth, lines, visited):
        indent = " " * (2 * (depth + 1))
        if x in visited:
            lines.append(f"{indent}{x} (see above)")
            return
        visited.add(x)
        family = self.family
        person = family.persons[x]
        line = f"{indent}{x} {person.name} {life_years(person)}"
        spouse = family.spouse(x)
        if spouse is not None:
            line += f" = {spouse}"
        lines.append(line)
        for child in sorted(family.children(x), key=family.age_key):
            self.visit(child, depth + 1, lines, visited)

    def tree(self, arguments):
        x = arguments[0]
        family = self.family
        family.person(x)
        lines = []
        self.visit(x, 0, lines, set())
        self.emit(f"TREE {x} {len(family.lineage(x, False))}")
        self.output.extend(lines)

    def enter(self, x, number, generation, depth, lines, entered):
        family = self.family
        person = family.persons[x]
        indent = " " * (2 * (generation + 1))
        lines.append(f"{indent}{number} {x} {person.name} {life_years(person)}")
        entered.add(x)
        if generation < depth:
            parents = sorted(person.parents, key=lambda p: (SEX_INDEX[family.sex(p)], p))
            for index, parent in enumerate(parents):
                self.enter(parent, 2 * number + index, generation + 1, depth, lines, entered)

    def pedigree(self, arguments):
        x, depth_text = arguments
        depth = int(depth_text)
        self.family.person(x)
        lines = []
        entered = set()
        self.enter(x, 1, 0, depth, lines, entered)
        self.emit(f"PEDIGREE {x} {depth} entries={len(lines)} distinct={len(entered)}")
        self.output.extend(lines)

    def timeline(self, arguments):
        x = arguments[0]
        family = self.family
        person = family.person(x)
        events = [(person.birth, 0, "", "born")]
        for record in family.records_of(x):
            other = record.other(x)
            events.append((record.start, 1, other, f"married {other}"))
            if record.status == "divorced":
                events.append((record.end, 3, other, f"divorced {other}"))
            elif record.status == "widowed" and record.died == other:
                events.append((record.end, 4, other, f"widowed {other}"))
        children = family.children(x)
        for child in children:
            events.append((family.persons[child].birth, 2, child, f"child {child}"))
        for label, relatives in (("parent", person.parents), ("child", children)):
            for other in relatives:
                death = family.persons[other].death
                if death is None or death < person.birth:
                    continue
                if person.death is None or death <= person.death:
                    events.append((death, 5, other, f"lost {label} {other}"))
        if person.death is not None:
            events.append((person.death, 6, "", "died"))
        events.sort(key=lambda event: event[:3])
        self.emit(f"TIMELINE {x} {len(events)}")
        for year, _, _, text in events:
            self.emit(f"  {year} {text}")

    def census(self, arguments):
        year = int(arguments[0])
        family = self.family
        residents = [
            x for x, person in family.persons.items()
            if person.birth <= year and (person.death is None or person.death > year)
        ]
        residents.sort(key=family.age_key)
        self.emit(f"CENSUS {year} {len(residents)}")
        for x in residents:
            age = year - family.persons[x].birth
            self.emit(f"  {x} {age} {family.census_status(x, year)}")

    def kinship(self, arguments):
        a, b = arguments
        family = self.family
        family.person(a)
        family.person(b)
        value = family.kinship_coefficient(a, b, {})
        self.emit(f"KINSHIP {a} {b} {fraction_text(value)}")

    def find(self, arguments):
        x, route = arguments
        family = self.family
        family.person(x)
        current = {x}
        for step in route.split("."):
            kind, sex = STEPS[step]
            collected = set()
            for y in current:
                for z in family.step_targets(y, kind):
                    if sex is None or family.sex(z) == sex:
                        collected.add(z)
            current = collected
        current.discard(x)
        self.emit(f"FIND {x} {route} {len(current)}")
        for y in sorted(current):
            self.emit(f"  {y}: {family.relationship_text(y, x)}")

    def term(self, arguments):
        da, db, sex = int(arguments[0]), int(arguments[1]), arguments[2]
        self.emit(f"TERM {da} {db} {sex} {kinship_term(da, db, sex)}")

    def stats(self, arguments):
        family = self.family
        persons = family.persons.values()
        living = sum(person.death is None for person in persons)
        links = sum(len(person.parents) for person in persons)
        couples = sum(record.status == "current" for record in family.marriages)
        founders = sum(not person.parents for person in persons)
        memo = {}
        longest = max((family.lineage_length(x, memo) for x in family.persons), default=0)
        self.emit(
            f"STATS persons={len(family.persons)} living={living} links={links} "
            f"couples={couples} founders={founders} generations={longest}"
        )

    def audit(self, arguments):
        family = self.family
        lines = []
        for record in family.marriages:
            apex = family.apex(record.first, record.second)
            if apex is not None:
                term = apex.blood_term(family.sex(record.first))
                lines.append(f"  marriage {record.first} {record.second} {term}")
        memo = {}
        for x in sorted(family.persons):
            value = family.inbreeding_coefficient(x, memo)
            if value != 0:
                lines.append(f"  inbred {x} {fraction_text(value)}")
        self.emit(f"AUDIT {len(lines)}")
        self.output.extend(lines)

    def execute(self, line):
        command, *arguments = line.split(" ")
        handlers = {
            "PERSON": self.add_person,
            "DEATH": self.record_death,
            "REMOVE": self.remove_person,
            "PARENT": self.link_parent,
            "UNPARENT": self.unlink_parent,
            "SPOUSE": self.marry,
            "DIVORCE": self.divorce,
            "UNDO": self.undo,
            "INFO": self.info,
            "RELATION": self.relation,
            "RELATIVES": self.relatives,
            "WHO": self.who,
            "PATH": self.path,
            "COMMON": self.common,
            "ANCESTORS": self.ancestors,
            "DESCENDANTS": self.descendants,
            "COUSINS": self.cousins,
            "SIBLINGS": self.siblings,
            "GENERATIONS": self.generations,
            "TREE": self.tree,
            "PEDIGREE": self.pedigree,
            "TIMELINE": self.timeline,
            "CENSUS": self.census,
            "KINSHIP": self.kinship,
            "FIND": self.find,
            "TERM": self.term,
            "STATS": self.stats,
            "AUDIT": self.audit,
        }
        try:
            if command in MODIFYING:
                saved = self.family.copy()
                handlers[command](arguments)
                self.history.append((line, saved))
            else:
                handlers[command](arguments)
        except CommandError as error:
            self.emit(f"ERROR {error}")


def main():
    calculator = KinshipCalculator()
    count = int(sys.stdin.readline())
    for _ in range(count):
        calculator.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(calculator.output) + "\n")


if __name__ == "__main__":
    main()
