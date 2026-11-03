from collections import Counter
from itertools import combinations
import sys


STYLES = ("APA", "IEEE", "CHICAGO", "MLA")
MONTH_MACROS = {
    "jan": "January", "feb": "February", "mar": "March", "apr": "April",
    "may": "May", "jun": "June", "jul": "July", "aug": "August",
    "sep": "September", "oct": "October", "nov": "November", "dec": "December",
}
MONTH_ABBREVIATIONS = {
    "January": "Jan.", "February": "Feb.", "March": "Mar.", "April": "Apr.",
    "May": "May", "June": "June", "July": "July", "August": "Aug.",
    "September": "Sep.", "October": "Oct.", "November": "Nov.", "December": "Dec.",
}
REQUIRED_FIELDS = {
    "article": ("author", "title", "journal", "year"),
    "book": ("author", "title", "publisher", "year"),
    "inproceedings": ("author", "title", "booktitle", "year"),
    "incollection": ("author", "title", "booktitle", "publisher", "year"),
    "techreport": ("author", "title", "institution", "year"),
    "phdthesis": ("author", "title", "school", "year"),
    "misc": ("author", "title", "year"),
}
KNOWN_FIELDS = (
    "author", "editor", "title", "journal", "booktitle", "edition", "volume", "number",
    "pages", "publisher", "institution", "school", "address", "howpublished", "month",
    "year", "doi", "note",
)
SMALL_WORDS = {
    "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor",
    "of", "on", "or", "over", "per", "so", "the", "to", "up", "via", "with", "yet",
}
ACCENT_SYMBOLS = "'\"`^~=."
ACCENT_COMMANDS = ACCENT_SYMBOLS + "cuvH"
LEADING_ARTICLES = ("a ", "an ", "the ")
EDITOR_SUFFIXES = {
    "APA": (" (Ed.)", " (Eds.)"),
    "IEEE": (", Ed.", ", Eds."),
    "CHICAGO": (", ed.", ", eds."),
    "MLA": (", editor", ", editors"),
}
HEADINGS = {
    "APA": "References",
    "IEEE": "References",
    "CHICAGO": "References",
    "MLA": "Works Cited",
}
TEMPLATES = {
    "APA": {
        "article": "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        "book": "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        "inproceedings": "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        "techreport": "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        "phdthesis": "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        "misc": "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>",
    },
    "IEEE": {
        "article": '{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.',
        "book": "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        "inproceedings": '{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.',
        "techreport": '{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.',
        "phdthesis": '{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.',
        "misc": '{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>',
    },
    "CHICAGO": {
        "article": '{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>',
        "book": "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        "inproceedings": '{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>',
        "techreport": "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        "phdthesis": '{author}. {year}. "{title}." PhD diss., {school}.',
        "misc": "{author}. {year}. {title}.< {howpublished}.>< {note}.>",
    },
    "MLA": {
        "article": '{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>',
        "book": "{author}. {title}.< {edition},> {publisher}, {year}.",
        "inproceedings": '{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.',
        "techreport": "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        "phdthesis": "{author}. {title}. {year}. {school}, PhD dissertation.",
        "misc": "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>",
    },
}
ARGUMENT_COUNTS = {
    "FORMAT": 2, "BIBLIOGRAPHY": 1, "CITE": 2, "KEYGEN": 0,
    "CHECK": 0, "SEARCH": 2, "EXPORT": 1, "STATS": 0,
}
STYLED_COMMANDS = ("FORMAT", "BIBLIOGRAPHY", "CITE")


class LoadError(Exception):
    pass


class CommandError(Exception):
    pass


def depths(text):
    result = []
    depth = 0
    for char in text:
        result.append(depth)
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
    return result


def split_top(text, separator):
    levels = depths(text)
    parts = []
    start = 0
    index = 0
    while index < len(text):
        if levels[index] == 0 and text.startswith(separator, index):
            parts.append(text[start:index])
            index += len(separator)
            start = index
        else:
            index += 1
    parts.append(text[start:])
    return parts


def plain(text):
    return text.replace("{", "").replace("}", "")


def letters_of(text):
    return "".join(char for char in text if char.isalpha())


def evaluate(expression, macros):
    depth = 0
    for char in expression:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth < 0:
                raise LoadError("unbalanced braces")
    if depth != 0:
        raise LoadError("unbalanced braces")
    parts = []
    for term in expression.split(" # "):
        if term.startswith(("{", '"')):
            parts.append(term[1:-1])
        elif term.isdigit():
            parts.append(term)
        elif term in macros:
            parts.append(macros[term])
        else:
            raise LoadError(f"unknown macro '{term}'")
    return "".join(parts)


def accent_at(text, index):
    if text.startswith("\\&", index):
        return "&", 2
    command = text[index:index + 5]
    if len(command) < 3 or command[0] != "\\":
        return None
    if command[1] in ACCENT_SYMBOLS and command[2].isalpha():
        return command[2], 3
    if (len(command) == 5 and command[1] in ACCENT_COMMANDS and command[2] == "{"
            and command[3].isalpha() and command[4] == "}"):
        return command[3], 5
    return None


def remove_accents(text):
    result = []
    index = 0
    while index < len(text):
        if text[index] == "{":
            accent = accent_at(text, index + 1)
            if accent is not None and text.startswith("}", index + 1 + accent[1]):
                result.append(accent[0])
                index += accent[1] + 2
                continue
        accent = accent_at(text, index)
        if accent is None:
            result.append(text[index])
            index += 1
        else:
            result.append(accent[0])
            index += accent[1]
    return "".join(result)


def normalize(text):
    return " ".join(remove_accents(text).replace("~", " ").split())


def initials(first):
    words = []
    for word in plain(first).split():
        pieces = []
        for piece in word.split("-"):
            letter = next(char for char in piece if char.isalpha())
            pieces.append(letter.upper() + ".")
        words.append("-".join(pieces))
    return " ".join(words)


class Name:
    def __init__(self, first, von, last, jr):
        self.first = first
        self.von = von
        self.last = last
        self.jr = jr

    def __eq__(self, other):
        return (
            self.first == other.first and self.von == other.von
            and self.last == other.last and self.jr == other.jr
        )

    def surname(self):
        if self.von:
            return plain(self.von + " " + self.last)
        return plain(self.last)

    def given(self, full):
        return plain(self.first) if full else initials(self.first)

    def inverted(self, full):
        text = self.surname()
        if self.first:
            text += ", " + self.given(full)
        if self.jr:
            text += ", " + plain(self.jr)
        return text

    def direct(self, full):
        text = self.surname()
        if self.first:
            text = self.given(full) + " " + text
        if self.jr:
            text += ", " + plain(self.jr)
        return text


class NameList:
    def __init__(self, names, et_al):
        self.names = names
        self.et_al = et_al

    def __eq__(self, other):
        return self.names == other.names and self.et_al == other.et_al

    def single(self):
        return len(self.names) == 1 and not self.et_al


def lowercase_positions(words):
    return [index for index in range(len(words) - 1) if words[index][0].islower()]


def parse_name(text):
    parts = [part.strip() for part in split_top(text, ",")]
    words = split_top(parts[0], " ")
    lowercase = lowercase_positions(words)
    if len(parts) == 1:
        if not lowercase:
            return Name(" ".join(words[:-1]), "", words[-1], "")
        start, end = lowercase[0], lowercase[-1] + 1
        return Name(" ".join(words[:start]), " ".join(words[start:end]), " ".join(words[end:]), "")
    end = lowercase[-1] + 1 if lowercase else 0
    von = " ".join(words[:end])
    last = " ".join(words[end:])
    if len(parts) == 2:
        return Name(parts[1], von, last, "")
    return Name(parts[2], von, last, parts[1])


def parse_names(value):
    names = []
    et_al = False
    for part in split_top(value, " and "):
        if part == "others":
            et_al = True
        else:
            names.append(parse_name(part))
    return NameList(names, et_al)


def sentence_case(title):
    chars = list(title)
    for index, depth in enumerate(depths(title)):
        if depth == 0 and chars[index].isalpha():
            starts = index == 0 or (index >= 2 and title[index - 2:index] == ": ")
            chars[index] = chars[index].upper() if starts else chars[index].lower()
    return "".join(chars)


def lowercase_top(word):
    return "".join(
        char.lower() if depth == 0 else char
        for char, depth in zip(word, depths(word))
    )


def capitalize_first(word):
    levels = depths(word)
    for index, char in enumerate(word):
        if char.isalpha():
            if levels[index] == 0:
                return word[:index] + char.upper() + word[index + 1:]
            return word
    return word


def title_case(title):
    words = split_top(title, " ")
    converted = []
    for index, word in enumerate(words):
        small = letters_of(word).lower() in SMALL_WORDS
        inner = 0 < index < len(words) - 1
        if word.startswith("{"):
            converted.append(word)
        elif small and inner and not words[index - 1].endswith(":"):
            converted.append(lowercase_top(word))
        else:
            converted.append(capitalize_first(word))
    return " ".join(converted)


def styled_title(title, style):
    if style == "APA":
        return sentence_case(title)
    if style == "IEEE":
        return title
    return title_case(title)


class Entry:
    def __init__(self, key, kind, fields):
        self.key = key
        self.kind = kind
        self.fields = fields
        self.authors = parse_names(fields["author"]) if "author" in fields else None
        self.editors = parse_names(fields["editor"]) if "editor" in fields else None
        self.primary = self.authors if self.authors is not None else self.editors
        self.suffix = ""

    def plain_field(self, name):
        return plain(self.fields.get(name, ""))

    def sort_title(self):
        title = self.plain_field("title").lower()
        for article in LEADING_ARTICLES:
            if title.startswith(article):
                return title[len(article):]
        return title

    def order_key(self):
        lead = self.primary.names[0]
        return plain(lead.last).lower(), self.plain_field("year"), self.sort_title(), self.key

    def year_label(self, style):
        if style in ("APA", "CHICAGO"):
            return self.plain_field("year") + self.suffix
        return self.plain_field("year")


class Element:
    def __init__(self, kind, text="", children=None):
        self.kind = kind
        self.text = text
        self.children = children if children is not None else []


def parse_elements(template, index):
    elements = []
    while index < len(template) and template[index] != ">":
        char = template[index]
        if char == "{":
            end = template.index("}", index)
            elements.append(Element("field", template[index + 1:end]))
            index = end + 1
        elif char == "<":
            children, index = parse_elements(template, index + 1)
            elements.append(Element("optional", children=children))
            index += 1
        else:
            elements.append(Element("text", char))
            index += 1
    return elements, index


def parse_template(template):
    elements, _ = parse_elements(template, 0)
    return elements


def render(elements, values, output=""):
    for element in elements:
        if element.kind == "field":
            output += values.get(element.text, "")
        elif element.kind == "optional":
            fields = [child.text for child in element.children if child.kind == "field"]
            if all(values.get(name, "") for name in fields):
                output = render(element.children, values, output)
        elif element.text != "." or not output.endswith((".", "?", "!")):
            output += element.text
    return output


def list_a(names, conjunction):
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + ", " + conjunction + " " + names[-1]


def list_b(names, conjunction):
    if len(names) == 2:
        return f"{names[0]} {conjunction} {names[1]}"
    return list_a(names, conjunction)


def author_names(name_list, style):
    names = name_list.names
    if style == "APA":
        forms = [name.inverted(False) for name in names]
        if name_list.et_al:
            return ", ".join(forms) + ", et al."
        if len(forms) <= 20:
            return list_a(forms, "&")
        return ", ".join(forms[:19]) + ", . . . " + forms[-1]
    if style == "IEEE":
        forms = [name.direct(False) for name in names]
        if name_list.et_al or len(forms) >= 7:
            return forms[0] + " et al."
        return list_b(forms, "and")
    forms = [names[0].inverted(True)] + [name.direct(True) for name in names[1:]]
    if style == "CHICAGO":
        if name_list.et_al or len(forms) >= 11:
            return ", ".join(forms[:7]) + ", et al."
        return list_a(forms, "and")
    if name_list.et_al or len(forms) >= 3:
        return forms[0] + ", et al."
    return list_a(forms, "and")


def editor_names(name_list, style):
    full = style in ("CHICAGO", "MLA")
    forms = [name.direct(full) for name in name_list.names]
    if name_list.et_al:
        return forms[0] + " et al."
    return list_b(forms, "&" if style == "APA" else "and")


def edition_text(edition):
    if not edition.isdigit():
        return edition + " ed."
    number = int(edition)
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
    return f"{edition}{suffix} ed."


def short_name(entry, style, ampersand):
    surnames = [name.surname() for name in entry.primary.names]
    limit = 4 if style == "CHICAGO" else 3
    if entry.primary.et_al or len(surnames) >= limit:
        return surnames[0] + " et al."
    if len(surnames) == 3:
        return f"{surnames[0]}, {surnames[1]}, and {surnames[2]}"
    if len(surnames) == 2:
        conjunction = "&" if ampersand else "and"
        return f"{surnames[0]} {conjunction} {surnames[1]}"
    return surnames[0]


def number_ranges(numbers):
    parts = []
    start = 0
    while start < len(numbers):
        end = start
        while end + 1 < len(numbers) and numbers[end + 1] == numbers[end] + 1:
            end += 1
        if end - start >= 2:
            parts.append(f"[{numbers[start]}]-[{numbers[end]}]")
        else:
            parts.extend(f"[{number}]" for number in numbers[start:end + 1])
        start = end + 1
    return ", ".join(parts)


class Citation:
    def __init__(self, start, end, command, keys):
        self.start = start
        self.end = end
        self.command = command
        self.keys = keys


def find_citations(text):
    citations = []
    start = text.find("\\")
    while start != -1:
        brace = text.index("{", start)
        end = text.index("}", brace)
        keys = list(dict.fromkeys(text[brace + 1:end].split(",")))
        citations.append(Citation(start, end + 1, text[start + 1:brace], keys))
        start = text.find("\\", end)
    return citations


def base_key(entry):
    last = letters_of(plain(entry.primary.names[0].last)).lower()
    year = "".join(char for char in entry.fields["year"] if char.isdigit())
    word = ""
    for candidate in entry.plain_field("title").split():
        letters = letters_of(candidate).lower()
        if letters and letters not in SMALL_WORDS:
            word = letters
            break
    return last + year + word


def entry_warnings(entry, titles):
    messages = []
    if "pages" in entry.fields:
        pages = entry.plain_field("pages")
        if "-" in pages and "--" not in pages:
            messages.append("pages use a single hyphen")
        numbers = [part for part in pages.split("-") if part]
        if len(numbers) == 2 and all(part.isdigit() for part in numbers):
            if int(numbers[0]) > int(numbers[1]):
                messages.append("pages are reversed")
    year = entry.plain_field("year")
    if len(year) != 4 or not year.isdigit():
        messages.append("year is not 4 digits")
    title = entry.plain_field("title")
    lowercase = sum(char.islower() for char in title)
    uppercase = sum(char.isupper() for char in title)
    if lowercase == 0 and uppercase >= 2:
        messages.append("title is all caps")
    if entry.kind == "article" and "doi" not in entry.fields:
        messages.append("article has no doi")
    lowered = title.lower()
    if lowered in titles:
        messages.append(f"same title as {titles[lowered]}")
    else:
        titles[lowered] = entry.key
    for name in sorted(entry.fields):
        if name not in KNOWN_FIELDS:
            messages.append(f"unknown field '{name}'")
    return messages


class Database:
    def __init__(self):
        self.macros = dict(MONTH_MACROS)
        self.macro_count = 0
        self.entries = []
        self.by_key = {}
        self.messages = []

    def report(self, index, name, reason):
        self.messages.append(f"ERROR line {index + 1}: {name}: {reason}")

    def load(self, lines):
        index = 0
        while lines[index] != "%%":
            line = lines[index]
            if line.startswith("@string{"):
                self.define_macro(line, index)
            elif line.startswith("@"):
                end = index + 1
                while lines[end] != "}":
                    end += 1
                self.read_entry(lines, index, end)
                index = end
            index += 1
        self.assign_suffixes()
        return index

    def define_macro(self, line, index):
        name, expression = line[len("@string{"):-1].split(" = ", 1)
        try:
            value = evaluate(expression, self.macros)
        except LoadError as error:
            self.report(index, name, error)
            return
        if name in self.macros:
            self.report(index, name, "duplicate macro")
            return
        self.macros[name] = value
        self.macro_count += 1

    def read_entry(self, lines, start, end):
        header = lines[start]
        brace = header.index("{")
        kind = header[1:brace]
        key = header[brace + 1:-1]
        if kind not in REQUIRED_FIELDS:
            self.report(start, key, f"unknown type '{kind}'")
            return
        if key in self.by_key:
            self.report(start, key, "duplicate key")
            return
        fields = {}
        for index in range(start + 1, end):
            name, expression = lines[index][2:].split(" = ", 1)
            if expression.endswith(","):
                expression = expression[:-1]
            try:
                value = normalize(evaluate(expression, self.macros))
            except LoadError as error:
                self.report(index, key, error)
                return
            if name in fields:
                self.report(index, key, f"duplicate field '{name}'")
                return
            fields[name] = value
        for name in REQUIRED_FIELDS[kind]:
            substituted = name == "author" and kind == "book" and "editor" in fields
            if name not in fields and not substituted:
                self.report(end, key, f"missing field '{name}'")
                return
        entry = Entry(key, kind, fields)
        self.entries.append(entry)
        self.by_key[key] = entry

    def assign_suffixes(self):
        for entry in self.entries:
            group = [
                other for other in self.entries
                if other.primary == entry.primary and other.fields["year"] == entry.fields["year"]
            ]
            if len(group) > 1:
                group.sort(key=lambda other: (other.sort_title(), other.key))
                entry.suffix = chr(ord("a") + group.index(entry))

    def summary(self):
        return (
            f"LOADED entries={len(self.entries)} macros={self.macro_count} "
            f"errors={len(self.messages)}"
        )


class CitationManager:
    def __init__(self, database):
        self.database = database
        self.record = []
        self.output = []

    def emit(self, text):
        self.output.append(text)

    def entry(self, key):
        if key not in self.database.by_key:
            raise CommandError(f"unknown key '{key}'")
        return self.database.by_key[key]

    def ieee_order(self):
        rest = sorted(key for key in self.database.by_key if key not in self.record)
        return self.record + rest

    def ieee_numbers(self):
        return {key: number for number, key in enumerate(self.ieee_order(), 1)}

    def template_values(self, entry, style, repeated):
        values = {name: plain(value) for name, value in entry.fields.items()}
        author = "---" if repeated else author_names(entry.primary, style)
        if entry.authors is None:
            single, plural = EDITOR_SUFFIXES[style]
            author += single if entry.primary.single() else plural
        values["author"] = author
        values["editor"] = ""
        values["eds"] = ""
        if entry.editors is not None:
            values["editor"] = editor_names(entry.editors, style)
            values["eds"] = "Ed." if entry.editors.single() else "Eds."
        values["title"] = plain(styled_title(entry.fields["title"], style))
        values["year"] = entry.year_label(style)
        values["pp"] = ""
        if "pages" in entry.fields:
            pages = values["pages"].replace("--", "-")
            values["pages"] = pages
            values["pp"] = ("pp. " if "-" in pages else "p. ") + pages
        if "edition" in entry.fields:
            values["edition"] = edition_text(values["edition"])
        month = values.get("month", "")
        values["mon"] = MONTH_ABBREVIATIONS.get(month, month)
        return values

    def reference(self, entry, style, repeated=False):
        kind = "inproceedings" if entry.kind == "incollection" else entry.kind
        template = parse_template(TEMPLATES[style][kind])
        text = render(template, self.template_values(entry, style, repeated))
        if style == "IEEE":
            return f"[{self.ieee_numbers()[entry.key]}] {text}"
        return text

    def format(self, arguments):
        style, *keys = arguments
        for key in keys:
            if key in self.database.by_key:
                self.emit(self.reference(self.database.by_key[key], style))
            else:
                self.emit(f"ERROR unknown key '{key}'")

    def bibliography(self, arguments):
        style = arguments[0]
        self.emit(HEADINGS[style])
        if style == "IEEE":
            entries = [self.database.by_key[key] for key in self.ieee_order()]
        else:
            entries = sorted(self.database.entries, key=Entry.order_key)
        previous = None
        for entry in entries:
            repeated = (
                style in ("CHICAGO", "MLA") and previous is not None
                and entry.primary == previous.primary
            )
            self.emit(self.reference(entry, style, repeated))
            previous = entry

    def author_year(self, entries, style, parenthetical):
        groups = []
        for entry in entries:
            name = short_name(entry, style, style == "APA" and parenthetical)
            label = entry.year_label(style)
            if groups and groups[-1][0] == name:
                groups[-1][1].append(label)
            else:
                groups.append((name, [label]))
        if not parenthetical:
            return "; ".join(f"{name} ({', '.join(labels)})" for name, labels in groups)
        separator = ", " if style == "APA" else " "
        return "(" + "; ".join(name + separator + ", ".join(labels) for name, labels in groups) + ")"

    def citation_text(self, command, entries, style):
        if command == "citeauthor":
            return "; ".join(short_name(entry, style, False) for entry in entries)
        if command == "citeyear":
            return ", ".join(entry.year_label(style) for entry in entries)
        parenthetical = command in ("cite", "citep")
        if style == "IEEE":
            numbers = self.ieee_numbers()
            if parenthetical:
                return number_ranges(sorted(numbers[entry.key] for entry in entries))
            return "; ".join(
                f"{short_name(entry, style, False)} [{numbers[entry.key]}]" for entry in entries
            )
        if style == "MLA":
            names = "; ".join(short_name(entry, style, False) for entry in entries)
            return f"({names})" if parenthetical else names
        if parenthetical:
            entries = sorted(entries, key=Entry.order_key)
        return self.author_year(entries, style, parenthetical)

    def cite(self, arguments):
        style, text = arguments
        citations = find_citations(text)
        cited = [[self.entry(key) for key in citation.keys] for citation in citations]
        for entries in cited:
            for entry in entries:
                if entry.key not in self.record:
                    self.record.append(entry.key)
        pieces = []
        position = 0
        for citation, entries in zip(citations, cited):
            pieces.append(text[position:citation.start])
            pieces.append(self.citation_text(citation.command, entries, style))
            position = citation.end
        pieces.append(text[position:])
        self.emit("".join(pieces))

    def keygen(self, arguments):
        bases = [base_key(entry) for entry in self.database.entries]
        counts = Counter(bases)
        used = Counter()
        for entry, base in zip(self.database.entries, bases):
            generated = base
            if counts[base] > 1:
                generated = base + chr(ord("a") + used[base])
                used[base] += 1
            self.emit(f"{entry.key} -> {generated}")

    def check(self, arguments):
        titles = {}
        count = 0
        for entry in self.database.entries:
            messages = entry_warnings(entry, titles)
            for message in messages:
                self.emit(f"WARN {entry.key}: {message}")
            count += len(messages)
        self.emit(f"CHECK warnings={count}")

    def search(self, arguments):
        field, needle = arguments
        needle = needle.lower()
        keys = [
            entry.key for entry in self.database.entries
            if field in entry.fields and needle in entry.plain_field(field).lower()
        ]
        if keys:
            self.emit(f"MATCHES {len(keys)}: " + " ".join(keys))
        else:
            self.emit("MATCHES 0")

    def export(self, arguments):
        entry = self.entry(arguments[0])
        known = [name for name in KNOWN_FIELDS if name in entry.fields]
        unknown = sorted(name for name in entry.fields if name not in KNOWN_FIELDS)
        names = known + unknown
        self.emit(f"@{entry.kind}{{{entry.key},")
        for index, name in enumerate(names):
            ending = "," if index < len(names) - 1 else ""
            self.emit(f"  {name} = {{{entry.fields[name]}}}{ending}")
        self.emit("}")

    def stats(self, arguments):
        entries = self.database.entries
        self.emit(f"ENTRIES {len(entries)}")
        types = Counter(entry.kind for entry in entries)
        for kind in sorted(types):
            self.emit(f"TYPE {kind} {types[kind]}")
        years = Counter(entry.plain_field("year") for entry in entries)
        for year in sorted(years):
            self.emit(f"YEAR {year} {years[year]}")
        authors = set()
        pairs = Counter()
        for entry in entries:
            if entry.authors is None:
                continue
            forms = sorted({name.direct(True) for name in entry.authors.names})
            authors.update(forms)
            for pair in combinations(forms, 2):
                pairs[pair] += 1
        self.emit(f"AUTHORS {len(authors)}")
        if not pairs:
            self.emit("PAIR none")
            return
        (first, second), count = min(pairs.items(), key=lambda item: (-item[1], item[0]))
        self.emit(f"PAIR {first} & {second} {count}")

    def execute(self, line):
        if line.split(" ", 1)[0] in ("CITE", "SEARCH"):
            command, *arguments = line.split(" ", 2)
        else:
            command, *arguments = line.split(" ")
        handlers = {
            "FORMAT": self.format,
            "BIBLIOGRAPHY": self.bibliography,
            "CITE": self.cite,
            "KEYGEN": self.keygen,
            "CHECK": self.check,
            "SEARCH": self.search,
            "EXPORT": self.export,
            "STATS": self.stats,
        }
        try:
            if command not in handlers:
                raise CommandError(f"unknown command '{command}'")
            expected = ARGUMENT_COUNTS[command]
            if command == "FORMAT":
                valid = len(arguments) >= expected
            else:
                valid = len(arguments) == expected
            if not valid:
                raise CommandError("wrong number of arguments")
            if command in STYLED_COMMANDS and arguments[0] not in STYLES:
                raise CommandError(f"unknown style '{arguments[0]}'")
            handlers[command](arguments)
        except CommandError as error:
            self.emit(f"ERROR {error}")


def main():
    lines = sys.stdin.read().splitlines()
    database = Database()
    separator = database.load(lines)
    manager = CitationManager(database)
    count = int(lines[separator + 1])
    for line in lines[separator + 2:separator + 2 + count]:
        manager.execute(line)
    output = database.messages + [database.summary()] + manager.output
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
