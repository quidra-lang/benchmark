"""Lay out a monospaced document with optimal and greedy line breaking."""

from bisect import bisect_right
from collections import namedtuple
from pathlib import Path
import re

from document_parser import BODY_KINDS, parse_document
from hyphenation import Hyphenation, is_letter
from line_breaker import break_text
from page_builder import choose_pages
from renderer import display_line, format_table, pages_text, running_head


BreakPosition = namedtuple("BreakPosition", "start end midword append_hyphen")


def text_line(text):
    return {"text": text, "footnotes": (), "indexes": ()}


def split_label(text):
    if text.endswith("}") and " {#" in text:
        text, _, label = text.rpartition(" {#")
        return text, label[:-1]
    return text, None


def words_in(text):
    return [word for word in text.split(" ") if word]


class TextMetrics:
    """Number break positions and measure their spans without floating point."""

    def __init__(self, words, first_capacity, later_capacity, dictionary):
        self.words = words
        self.first_capacity = first_capacity
        self.later_capacity = later_capacity
        self.offsets = []
        self.breaks = [BreakPosition((0, 0), (0, 0), False, False)]
        offset = 0
        for index, word in enumerate(words):
            self.offsets.append(offset)
            offset += len(word) + 1
            for position, append_hyphen in dictionary.split_points(word):
                point = (index, position)
                self.breaks.append(BreakPosition(point, point, True,
                                                 append_hyphen))
            self.breaks.append(BreakPosition((index + 1, 0),
                                             (index, len(word)), False, False))
        self.end = len(self.breaks) - 1

    def capacity(self, start):
        return self.first_capacity if start == 0 else self.later_capacity

    def length(self, start, end):
        first_word, first_position = self.breaks[start].start
        last_word, last_position = self.breaks[end].end
        length = (self.offsets[last_word] + last_position
                  - self.offsets[first_word] - first_position)
        if self.breaks[end].append_hyphen:
            length += 1
        return length

    def slack(self, start, end):
        return self.capacity(start) - self.length(start, end)

    def measure(self, start, end):
        first_word, first_position = self.breaks[start].start
        last_word, last_position = self.breaks[end].end
        pieces = []
        ranges = []
        for word_number in range(first_word, last_word + 1):
            first = first_position if word_number == first_word else 0
            last = (last_position if word_number == last_word
                    else len(self.words[word_number]))
            pieces.append(self.words[word_number][first:last])
            ranges.append((word_number, first, last))
        if self.breaks[end].append_hyphen:
            pieces[-1] += "-"
        length = self.length(start, end)
        return {
            "start": start,
            "end": end,
            "pieces": pieces,
            "ranges": ranges,
            "gaps": len(pieces) - 1,
            "length": length,
            "capacity": self.capacity(start),
            "slack": self.capacity(start) - length,
            "last": end == self.end,
            "midword": self.breaks[end].midword,
        }


class Typesetter:
    def __init__(self, document, params, dictionary_lines):
        self.document = document
        self.params = params
        self.blocks = document["blocks"]
        self.warnings = document["warnings"]
        self.labels = {}
        self.bibliography = {}
        self.cited_entries = []
        self.body_blocks = []
        self.headings = []
        self.numbered_tables = []
        self.footnotes = []
        self.index_marks = []
        self.index_entries = {}
        self.dictionary = Hyphenation(
            dictionary_lines, document["hyphenation_words"],
            params["left_min"], params["right_min"],
        )
        self.register_document()
        self.check_document()
        self.assign_bibliography_labels()
        self.prepare_index()
        self.warnings.sort(key=lambda warning: warning[0])

    def warn(self, line_number, message):
        self.warnings.append((line_number, message))

    def register_document(self):
        chapter = 0
        section = 0
        table_number = 0
        previous = None
        for index, block in enumerate(self.blocks):
            block["id"] = index
            block["label"] = None
            kind = block["kind"]
            if kind in {"h1", "h2"}:
                block["text"], block["label"] = split_label(block["argument"])
                if kind == "h1":
                    chapter += 1
                    section = 0
                    block["number"] = str(chapter)
                    if index:
                        block["page_break"] = True
                else:
                    section += 1
                    block["number"] = f"{chapter}.{section}"
                self.headings.append(block)
            elif kind == "enum":
                if previous is not None and previous["kind"] == "enum":
                    block["number"] = previous["number"] + 1
                else:
                    block["number"] = 1
            elif kind == "table":
                block["caption"], block["label"] = split_label(block["caption"])
                block["number"] = None
                if block["caption"]:
                    table_number += 1
                    block["number"] = str(table_number)
                    self.numbered_tables.append(block)
            if block["label"] is not None:
                label = block["label"]
                if label in self.labels:
                    self.warn(block["line_number"], f"duplicate label {label}")
                    block["label"] = None
                else:
                    self.labels[label] = block
            if (kind == "paragraph" and previous is not None
                    and previous["kind"] in {"h1", "h2"}):
                block["indent"] = 0
            if kind in BODY_KINDS:
                self.body_blocks.append(block)
                block["paragraph_number"] = len(self.body_blocks)
            previous = block

        for original in self.document["bibliography"]:
            key = original["key"]
            if key in self.bibliography:
                self.warn(original["line_number"],
                          f"duplicate bibliography key {key}")
            else:
                self.bibliography[key] = {**original, "cited": False}

    def check_table(self, block):
        count = len(block["columns"])
        rows = []
        for line_number, text in block["inner_lines"]:
            cells = [cell.strip(" ") for cell in text.split("|")]
            if len(cells) != count:
                self.warn(line_number,
                          f"table row has {len(cells)} cells, expected {count}")
                cells = (cells + [""] * max(0, count - len(cells)))[:count]
            rows.append(cells)
        block["rows"] = rows
        lines = format_table(rows, block["columns"], block["caption"],
                             block["number"])
        block["table_lines"] = lines
        excess = max(map(len, lines)) - block["width"]
        if excess > 0:
            self.warn(block["line_number"], f"table too wide by {excess}")

    def accept_command(self, name, argument, line_number):
        if name in {"ref", "page"}:
            if argument not in self.labels:
                self.warn(line_number, f"undefined label {argument}")
        elif name == "cite":
            for key in argument.split(","):
                if key in self.bibliography:
                    self.bibliography[key]["cited"] = True
                else:
                    self.warn(line_number, f"undefined citation {key}")
        elif name == "fn":
            self.footnotes.append(argument)
            return name, len(self.footnotes)
        elif name == "idx":
            self.index_marks.append(argument)
            return name, len(self.index_marks)
        return name, argument

    def parse_body_line(self, text, line_number):
        tokens = []
        position = 0
        while position < len(text):
            opening = text.find("{", position)
            if opening == -1:
                tokens.append(text[position:])
                break
            if opening > position:
                tokens.append(text[position:opening])
            closing = text.find("}", opening + 1)
            if closing == -1:
                self.warn(line_number, "unclosed brace")
                tokens.append(text[opening:])
                break
            content = text[opening + 1:closing]
            name, separator, argument = content.partition(":")
            if (name in {"ref", "page", "fn", "idx", "cite"}
                    and separator and argument):
                tokens.append(self.accept_command(name, argument, line_number))
            else:
                self.warn(line_number, f"bad command {{{content}}}")
            position = closing + 1
        return tokens

    def check_document(self):
        for block in self.blocks:
            kind = block["kind"]
            if kind == "table":
                self.check_table(block)
            elif kind == "verbatim":
                for line_number, text in block["inner_lines"]:
                    excess = len(text) - block["width"]
                    if excess > 0:
                        self.warn(line_number,
                                  f"verbatim line too long by {excess}")
            elif kind in BODY_KINDS:
                tokens = []
                for index, (line_number, text) in enumerate(block["body_lines"]):
                    if index:
                        tokens.append(" ")
                    tokens.extend(self.parse_body_line(text, line_number))
                block["tokens"] = tokens
        for entry in self.bibliography.values():
            if not entry["cited"]:
                self.warn(entry["line_number"],
                          f"unused bibliography entry {entry['key']}")

    def assign_bibliography_labels(self):
        for entry in self.bibliography.values():
            if not entry["cited"]:
                continue
            surnames = entry["author"].split(" and ")
            if len(surnames) == 1:
                base = surnames[0][:3]
            elif len(surnames) <= 4:
                base = "".join(surname[0] for surname in surnames)
            else:
                base = "".join(surname[0] for surname in surnames[:3]) + "+"
            entry["base_label"] = base + entry["year"][-2:]
            self.cited_entries.append(entry)
        self.cited_entries.sort(key=lambda entry: (
            entry["base_label"], entry["author"], entry["title"], entry["key"]
        ))
        groups = {}
        for entry in self.cited_entries:
            groups.setdefault(entry["base_label"], []).append(entry)
        for base, entries in groups.items():
            for index, entry in enumerate(entries):
                suffix = chr(ord("a") + index) if len(entries) > 1 else ""
                entry["label"] = base + suffix

    def prepare_index(self):
        for number, phrase in enumerate(self.index_marks, 1):
            entry_part, has_reference, reference = phrase.partition("|")
            parent_name, has_child, child_name = entry_part.partition("!")
            parent = self.index_entries.setdefault(parent_name, {
                "name": parent_name, "marks": [], "references": set(),
                "children": {},
            })
            entry = parent
            if has_child:
                entry = parent["children"].setdefault(child_name, {
                    "name": child_name, "marks": [], "references": set(),
                })
            if has_reference:
                entry["references"].add(reference)
            else:
                entry["marks"].append(number)

    def citation_text(self, argument):
        labels = set()
        undefined = False
        for key in argument.split(","):
            entry = self.bibliography.get(key)
            if entry is None:
                undefined = True
            else:
                labels.add(entry["label"])
        parts = sorted(labels)
        if undefined:
            parts.append("?")
        return "[" + ", ".join(parts) + "]"

    def expand_body(self, block, page_values):
        parts = []
        marks = []
        offset = 0
        for token in block["tokens"]:
            if isinstance(token, str):
                text = token
            else:
                name, argument = token
                if name == "idx":
                    marks.append((offset - 1, name, argument))
                    continue
                if name == "fn":
                    marks.append((offset, name, argument))
                    text = f"[{argument}]"
                elif name == "ref":
                    target = self.labels.get(argument)
                    text = target["number"] if target is not None else "??"
                elif name == "page":
                    text = page_values.get(argument, "??")
                else:
                    text = self.citation_text(argument)
            parts.append(text)
            offset += len(text)
        expanded = "".join(parts)
        matches = list(re.finditer(r"[^ ]+", expanded))
        words = [match.group() for match in matches]
        starts = [match.start() for match in matches]
        word_marks = {}
        for offset, kind, number in marks:
            word = bisect_right(starts, offset) - 1
            position = offset - starts[word]
            word_marks.setdefault(word, []).append((kind, number, position))
        return words, word_marks

    @staticmethod
    def place_marks(line, measured, word_marks):
        footnotes = []
        indexes = []
        for word, first, last in measured["ranges"]:
            for kind, number, position in word_marks.get(word, ()):
                if first <= position < last:
                    if kind == "fn":
                        footnotes.append(number)
                    else:
                        indexes.append(number)
        line["footnotes"] = tuple(footnotes)
        line["indexes"] = tuple(indexes)

    def lay_out_text(self, words, capacities, alignment, prefixes, method,
                     word_marks=None):
        metrics = TextMetrics(words, *capacities, self.dictionary)
        breaking, cost = break_text(metrics, method, self.params)
        lines = []
        measured_lines = []
        start = 0
        for index, end in enumerate(breaking):
            measured = metrics.measure(start, end)
            text = display_line(measured["pieces"], measured["slack"],
                                alignment, measured["last"])
            prefix = prefixes[0] if index == 0 else prefixes[1]
            line = text_line(prefix + text)
            if word_marks:
                self.place_marks(line, measured, word_marks)
            lines.append(line)
            measured_lines.append(measured)
            start = end
        return {"lines": lines, "broken": measured_lines, "cost": cost}

    @staticmethod
    def body_format(block):
        width = block["width"]
        kind = block["kind"]
        if kind == "paragraph":
            indent = block["indent"]
            return (width - indent, width), (" " * indent, "")
        if kind == "item":
            return (width - 2, width - 2), ("- ", "  ")
        if kind == "enum":
            prefix = f"{block['number']:2d}. "
            return (width - 4, width - 4), (prefix, " " * 4)
        if kind == "quote":
            return (width - 8, width - 8), (" " * 4, " " * 4)
        first = block["term"].ljust(12) if len(block["term"]) <= 10 else " " * 12
        return (width - 12, width - 12), (first, " " * 12)

    def lay_out_body(self, block, page_values, method):
        words, marks = self.expand_body(block, page_values)
        capacities, prefixes = self.body_format(block)
        result = self.lay_out_text(words, capacities, block["align"], prefixes,
                                  method, marks)
        if block["kind"] == "term" and len(block["term"]) >= 11:
            result["lines"].insert(0, text_line(block["term"]))
        return result

    def lay_out_footnotes(self, method):
        results = {}
        for number, text in enumerate(self.footnotes, 1):
            prefix = f"[{number}] "
            capacity = self.document["page_width"] - len(prefix)
            results[number] = self.lay_out_text(
                words_in(text), (capacity, capacity), "left",
                (prefix, " " * len(prefix)), method,
            )
        return results

    def lay_out_reference(self, entry, width, method):
        margin = max(len(item["label"]) for item in self.cited_entries) + 3
        text = f"{entry['author']}. {entry['year']}. {entry['title']}"
        capacity = width - margin
        prefix = f"[{entry['label']}]".ljust(margin)
        return self.lay_out_text(
            words_in(text), (capacity, capacity), "left",
            (prefix, " " * margin), method,
        )

    @staticmethod
    def page_list(numbers):
        numbers = sorted(set(numbers))
        parts = []
        index = 0
        while index < len(numbers):
            last = index
            while last + 1 < len(numbers) and numbers[last + 1] == numbers[last] + 1:
                last += 1
            if last - index >= 2:
                parts.append(f"{numbers[index]}-{numbers[last]}")
            else:
                parts.extend(str(number) for number in numbers[index:last + 1])
            index = last + 1
        return ", ".join(parts)

    def index_entry_line(self, entry, mark_pages, child=False):
        text = ("  " if child else "") + entry["name"]
        numbers = [mark_pages[number] for number in entry["marks"]
                   if number in mark_pages]
        if numbers:
            text += ", " + self.page_list(numbers)
        if entry["references"]:
            text += ", see " + ", ".join(sorted(entry["references"]))
        return text

    def index_lines(self, mark_pages):
        lines = []
        previous_group = None
        for name in sorted(self.index_entries, key=lambda name: (name.lower(), name)):
            parent = self.index_entries[name]
            group = name[0].upper() if is_letter(name[0]) else "Symbols"
            if group != previous_group:
                lines.append(group)
                previous_group = group
            lines.append(self.index_entry_line(parent, mark_pages))
            children = parent["children"]
            for child in sorted(children, key=lambda name: (name.lower(), name)):
                lines.append(self.index_entry_line(children[child], mark_pages, True))
        return lines

    def contents_lines(self, block, block_pages):
        entries = self.headings if block["kind"] == "toc" else self.numbered_tables
        lines = []
        for entry in entries:
            if block["kind"] == "toc":
                left = f"{entry['number']} {entry['text']}"
                if entry["kind"] == "h2":
                    left = "  " + left
            else:
                left = f"Table {entry['number']}. {entry['caption']}"
            page = block_pages.get(entry["id"])
            number = page["display"] if page is not None else "??"
            dots = block["width"] - len(left) - len(number) - 2
            lines.append(left + " " + "." * dots + " " + number)
        return lines

    @staticmethod
    def add_layout_block(layout, source, kind, lines, list_mark=False, first=True):
        if first:
            lines[0]["anchor"] = source["id"]
            if source["kind"] == "h1":
                lines[0]["chapter_start"] = True
        layout.append({
            "kind": kind,
            "lines": lines,
            "list": list_mark,
            "page_break": first and source["page_break"],
        })

    def build_layout_blocks(self, page_values, method, result):
        layout = []
        for block in self.blocks:
            kind = block["kind"]
            if kind in BODY_KINDS:
                body = self.lay_out_body(block, page_values, method)
                result["bodies"][block["id"]] = body
                name = f"paragraph {block['paragraph_number']}"
                result["warning_texts"].append((name, body, block["align"] == "justify"))
                self.add_layout_block(layout, block, "flow", body["lines"],
                                      kind in {"item", "enum", "term"})
            elif kind in {"title", "author"}:
                text = block["argument"]
                if kind == "title":
                    text = text.upper()
                text = " " * ((block["width"] - len(text)) // 2) + text
                self.add_layout_block(layout, block, "heading", [text_line(text)])
            elif kind in {"h1", "h2"}:
                text = block["text"].upper() if kind == "h1" else block["text"]
                text = f"{block['number']} {text}"
                rule = ("=" if kind == "h1" else "-") * len(text)
                lines = [text_line(text), text_line(rule)]
                self.add_layout_block(layout, block, "heading", lines)
            elif kind == "table":
                lines = [text_line(text) for text in block["table_lines"]]
                self.add_layout_block(layout, block, "solid", lines)
            elif kind == "verbatim":
                lines = [text_line(text) for _, text in block["inner_lines"]]
                self.add_layout_block(layout, block, "flow", lines)
            elif kind in {"toc", "lot", "index"}:
                title = {"toc": "CONTENTS", "lot": "TABLES", "index": "INDEX"}[kind]
                heading = [text_line(title), text_line("=" * len(title))]
                self.add_layout_block(layout, block, "heading", heading)
                entries = (self.index_lines({}) if kind == "index"
                           else self.contents_lines(block, {}))
                lines = [text_line(text) for text in entries]
                self.add_layout_block(layout, block, "flow", lines, first=False)
                result["generated"].append((block, lines))
            elif kind == "bibliography":
                heading = [text_line("REFERENCES"), text_line("==========")]
                self.add_layout_block(layout, block, "heading", heading)
                for entry in self.cited_entries:
                    reference = self.lay_out_reference(entry, block["width"], method)
                    result["warning_texts"].append((
                        f"reference {entry['label']}", reference, False
                    ))
                    self.add_layout_block(layout, block, "flow", reference["lines"],
                                          list_mark=True, first=False)
        return layout

    @staticmethod
    def roman(number):
        units = ("", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix")
        tens, remainder = divmod(number, 10)
        return "x" * tens + units[remainder]

    def number_pages(self, pages, result):
        numbered = []
        for page in pages:
            chapter_start = bool(page["content"][0].get("chapter_start"))
            serial = len(numbered) + 1
            if chapter_start and serial % 2 == 0:
                numbered.append({
                    "serial": serial, "blank": True, "content": [],
                    "footnotes": (), "height": 0, "ends_by_force": True,
                    "chapter_start": False,
                })
                serial += 1
            page["serial"] = serial
            page["chapter_start"] = chapter_start
            numbered.append(page)
        block_pages = {}
        for page in numbered:
            for line in page["content"]:
                if "anchor" in line:
                    block_pages[line["anchor"]] = page
        front_matter = 0
        if self.headings:
            first_chapter = self.headings[0]
            front_matter = block_pages[first_chapter["id"]]["serial"] - 1
        mark_pages = {}
        for page in numbered:
            serial = page["serial"]
            page["body_number"] = serial - front_matter
            page["display"] = (self.roman(serial) if serial <= front_matter
                               else str(page["body_number"]))
            for line in page["content"]:
                for mark in line["indexes"]:
                    mark_pages[mark] = page["body_number"]
        result["pages"] = numbered
        result["front_matter"] = front_matter
        result["block_pages"] = block_pages
        result["mark_pages"] = mark_pages
        result["label_values"] = {
            label: block_pages[block["id"]]["display"]
            for label, block in self.labels.items()
        }

    def layout_once(self, page_values, method):
        footnotes = self.lay_out_footnotes(method)
        result = {
            "method": method, "bodies": {}, "footnotes": footnotes,
            "warning_texts": [], "generated": [],
        }
        layout = self.build_layout_blocks(page_values, method, result)
        heights = {number: len(note["lines"]) for number, note in footnotes.items()}
        pages = choose_pages(layout, heights, self.document["height"],
                             self.params["orphan_lines"], self.params["widow_lines"])
        self.number_pages(pages, result)
        for number, note in footnotes.items():
            result["warning_texts"].append((f"footnote {number}", note, False))
        return result

    def complete_generated_lines(self, result):
        for block, records in result["generated"]:
            if block["kind"] == "index":
                texts = self.index_lines(result["mark_pages"])
            else:
                texts = self.contents_lines(block, result["block_pages"])
            # These records are shared by the layout blocks and page contents.
            for record, text in zip(records, texts, strict=True):
                record["text"] = text

    def assemble_pages(self, result):
        chapter = ""
        section = ""
        height = self.document["height"]
        total = len(result["pages"]) - result["front_matter"]
        for page in result["pages"]:
            if page["blank"]:
                page["header"] = ""
                page["footer"] = ""
                page["body"] = [""] * height
                continue
            for line in page["content"]:
                if "anchor" not in line:
                    continue
                block = self.blocks[line["anchor"]]
                if block["kind"] == "h1":
                    chapter = f"{block['number']} {block['text']}"
                    section = ""
                elif block["kind"] == "h2":
                    section = f"{block['number']} {block['text']}"
            values = {
                "page": page["display"], "pages": str(total),
                "chapter": chapter, "section": section,
            }
            page["header"] = "" if page["chapter_start"] else running_head(
                self.document["header"], values, self.document["page_width"],
                page["serial"],
            )
            page["footer"] = running_head(
                self.document["footer"], values, self.document["page_width"],
                page["serial"],
            )
            content = [line["text"] for line in page["content"]]
            note_lines = []
            for number in page["footnotes"]:
                note_lines.extend(line["text"]
                                  for line in result["footnotes"][number]["lines"])
            if note_lines:
                padding = height - len(content) - len(note_lines) - 1
                page["body"] = content + [""] * padding + ["----------"] + note_lines
            else:
                page["body"] = content + [""] * (height - len(content))

    def layout(self, method):
        page_values = {label: "??" for label in self.labels}
        while True:
            result = self.layout_once(page_values, method)
            if result["label_values"] == page_values:
                break
            page_values = result["label_values"]
        self.complete_generated_lines(result)
        self.assemble_pages(result)
        return result

    def layout_warnings(self, result):
        warnings = []
        for name, text, justify in result["warning_texts"]:
            for number, line in enumerate(text["broken"], 1):
                slack = line["slack"]
                if slack < 0:
                    warnings.append(f"{name} line {number}: overfull by {-slack}")
                elif (justify and not line["last"]
                      and slack >= self.params["underfull_slack"]):
                    warnings.append(f"{name} line {number}: underfull, slack {slack}")
        for page in result["pages"]:
            if page["blank"] or page["ends_by_force"]:
                continue
            empty = self.document["height"] - page["height"]
            if empty >= self.params["underfull_page"]:
                warnings.append(f"page {page['serial']}: underfull, {empty} empty lines")
        hyphenated = sum(line["midword"] for body in result["bodies"].values()
                         for line in body["broken"])
        warnings.append(f"{len(result['pages'])} pages, {hyphenated} hyphenated lines")
        return [f"{result['method']}: {message}" for message in warnings]

    def statistics(self, optimal, greedy):
        lines = ["paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"]
        totals = [0, 0, 0, 0]
        for block in self.body_blocks:
            kp_body = optimal["bodies"][block["id"]]
            greedy_body = greedy["bodies"][block["id"]]
            values = [len(kp_body["broken"]), kp_body["cost"],
                      len(greedy_body["broken"]), greedy_body["cost"]]
            for index, value in enumerate(values):
                totals[index] += value
            row = [str(block["paragraph_number"])] + list(map(str, values))
            lines.append(",".join(row))
        lines.append("total," + ",".join(map(str, totals)))
        return "\n".join(lines) + "\n"

    def write_outputs(self, directory, optimal, greedy):
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "pages.txt").write_text(pages_text(optimal["pages"]),
                                             encoding="ascii", newline="\n")
        (directory / "greedy_pages.txt").write_text(pages_text(greedy["pages"]),
                                                    encoding="ascii", newline="\n")
        (directory / "stats.csv").write_text(self.statistics(optimal, greedy),
                                             encoding="ascii", newline="\n")
        warnings = [f"line {number}: {message}" for number, message in self.warnings]
        warnings.extend(self.layout_warnings(optimal))
        warnings.extend(self.layout_warnings(greedy))
        (directory / "log.txt").write_text("\n".join(warnings) + "\n",
                                           encoding="ascii", newline="\n")


def main():
    inputs = Path("input")
    params = {}
    for line in (inputs / "params.txt").read_text(encoding="ascii").splitlines():
        name, value = line.split(" ")
        params[name] = int(value)
    dictionary = (inputs / "hyphenation.txt").read_text(encoding="ascii").splitlines()
    lines = (inputs / "document.txt").read_text(encoding="ascii").splitlines()
    typesetter = Typesetter(parse_document(lines), params, dictionary)
    optimal = typesetter.layout("kp")
    greedy = typesetter.layout("greedy")
    typesetter.write_outputs(Path("output"), optimal, greedy)


if __name__ == "__main__":
    main()
