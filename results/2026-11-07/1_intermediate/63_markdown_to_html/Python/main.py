import re
import string
import sys
from collections import namedtuple


TERMINATOR = "@@END@@"
WHITESPACE = " \n"
PUNCTUATION = frozenset(string.punctuation)
URL_PRECEDERS = " \n*_~("
URL_TRAILERS = ".,:;!?*_~)"
TOC_MARKER = "\0toc\0"
HTML_ESCAPES = str.maketrans({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"})

FENCE = re.compile(r"`{3,}|~{3,}")
ATX_HEADING = re.compile(r"(#{1,6})(?: |$)")
RULE = re.compile(r"-{3,}|\*{3,}|_{3,}")
ALERT = re.compile(r"\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]")
LIST_ITEM = re.compile(r"(?:([-*+])|([0-9]{1,9})([.)])) +")
FOOTNOTE_DEFINITION = re.compile(r"\[\^([A-Za-z0-9_-]+)\]:(.*)")
CELL_TOKEN = re.compile(r"\\.|\||[^\\|]+|\\")
DELIMITER_CELL = re.compile(r":?-+:?")
UNDERLINE = re.compile(r"={3,}|-{3,}")
LABEL = re.compile(r"[A-Za-z0-9_-]+")
NON_SLUG = re.compile(r"[^a-z0-9_ \n-]")
BACKTICKS = re.compile(r"`+")
AUTOLINK = re.compile(r"<([^ \n<>]*)>")
ANGLE_URL = re.compile(r"https?://.")
EMAIL = re.compile(r"[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+")
BARE_URL = re.compile(r"https?://[^ \n<]*")
TAG = re.compile(r"<[^>]*>")

ALIGNMENTS = {
    (True, True): "center",
    (True, False): "left",
    (False, True): "right",
    (False, False): None,
}
TASK_BOXES = {
    "[ ] ": '<input type="checkbox" disabled="" />',
    "[x] ": '<input type="checkbox" checked="" disabled="" />',
    "[X] ": '<input type="checkbox" checked="" disabled="" />',
}
EMPHASIS_TAGS = {
    1: ("<em>", "</em>"),
    2: ("<strong>", "</strong>"),
    3: ("<em><strong>", "</strong></em>"),
}
STRIKETHROUGH_TAGS = ("<del>", "</del>")

Heading = namedtuple("Heading", "level text")
Paragraph = namedtuple("Paragraph", "text")
CodeBlock = namedtuple("CodeBlock", "language lines")
Quote = namedtuple("Quote", "blocks")
Alert = namedtuple("Alert", "kind blocks")
ListBlock = namedtuple("ListBlock", "ordered start items")
Table = namedtuple("Table", "alignments header rows")
ListMarker = namedtuple("ListMarker", "kind number content")
Reference = namedtuple("Reference", "url title")
Delimiter = namedtuple("Delimiter", "char length can_open can_close")


class HorizontalRule:
    pass


class TableOfContents:
    pass


class TocEntry:
    def __init__(self, level, identifier, label):
        self.level = level
        self.identifier = identifier
        self.label = label
        self.children = []


def escape_html(text):
    return text.translate(HTML_ESCAPES)


def strip_tags(html):
    return TAG.sub("", html)


def normalize_label(label):
    return " ".join(label.lower().split())


def skip_whitespace(text, position):
    while position < len(text) and text[position] in WHITESPACE:
        position += 1
    return position


def escaped_read(text, position, stops):
    chars = []
    while position < len(text) and text[position] not in stops:
        if text[position] == "\\" and text[position + 1:position + 2] in PUNCTUATION:
            position += 1
        chars.append(text[position])
        position += 1
    return "".join(chars), position


def opening_fence(line):
    match = FENCE.match(line)
    if match is None:
        return None
    fence = match.group()
    info = line[len(fence):].strip(" ")
    if fence[0] == "`" and "`" in info:
        return None
    return fence, info


def atx_heading(line):
    match = ATX_HEADING.match(line)
    if match is None:
        return None
    level = len(match.group(1))
    text = line[level:].strip(" ")
    trimmed = text.rstrip("#")
    if trimmed == "" or trimmed.endswith(" "):
        text = trimmed.strip(" ")
    return Heading(level, text)


def is_rule(line):
    return RULE.fullmatch(line.replace(" ", "")) is not None


def list_marker(line):
    match = LIST_ITEM.match(line)
    if match is None or is_rule(line):
        return None
    bullet, digits, delimiter = match.groups()
    number = int(digits) if digits else None
    return ListMarker(bullet or delimiter, number, line[match.end():])


def interrupts_paragraph(line):
    return not line.startswith(" ") and (
        opening_fence(line) is not None
        or ATX_HEADING.match(line) is not None
        or is_rule(line)
        or line.startswith(">")
        or LIST_ITEM.match(line) is not None
    )


def indented_code(lines, index):
    end = index
    while end < len(lines) and (lines[end] == "" or lines[end].startswith("    ")):
        end += 1
    while lines[end - 1] == "":
        end -= 1
    return CodeBlock("", [line[4:] for line in lines[index:end]]), end


def fenced_code(lines, index, fence, info):
    end = index + 1
    while end < len(lines):
        line = lines[end]
        if len(line) >= len(fence) and line.strip(fence[0]) == "":
            break
        end += 1
    language = info.partition(" ")[0]
    return CodeBlock(language, lines[index + 1:end]), end + 1


def split_cells(line):
    tokens = CELL_TOKEN.findall(line.strip(" ").removeprefix("|"))
    if tokens and tokens[-1] == "|":
        tokens.pop()
    cells = [""]
    for token in tokens:
        if token == "|":
            cells.append("")
        else:
            cells[-1] += "|" if token == "\\|" else token
    return [cell.strip(" ") for cell in cells]


def parse_table(lines, index):
    if index + 1 >= len(lines) or "|" not in lines[index] or "|" not in lines[index + 1]:
        return None
    header = split_cells(lines[index])
    delimiters = split_cells(lines[index + 1])
    if len(header) != len(delimiters):
        return None
    if not all(DELIMITER_CELL.fullmatch(cell) for cell in delimiters):
        return None
    alignments = [ALIGNMENTS[cell.startswith(":"), cell.endswith(":")] for cell in delimiters]
    columns = len(delimiters)
    rows = []
    end = index + 2
    while end < len(lines) and "|" in lines[end]:
        cells = split_cells(lines[end])[:columns]
        rows.append(cells + [""] * (columns - len(cells)))
        end += 1
    return Table(alignments, header, rows), end


def paragraph(lines, index):
    end = index + 1
    level = None
    while end < len(lines) and lines[end] != "":
        line = lines[end]
        if UNDERLINE.fullmatch(line):
            level = 1 if line[0] == "=" else 2
            break
        if interrupts_paragraph(line):
            break
        end += 1
    text = "\n".join(line.lstrip(" ") for line in lines[index:end])
    if level is not None:
        return Heading(level, text), end + 1
    if text == "[TOC]":
        return TableOfContents(), end
    return Paragraph(text), end


class BlockParser:
    def __init__(self):
        self.references = {}
        self.footnotes = {}

    def parse(self, lines):
        blocks = []
        index = 0
        while index < len(lines):
            if lines[index] == "":
                index += 1
                continue
            block, index = self.next_block(lines, index)
            if block is not None:
                blocks.append(block)
        return blocks

    def next_block(self, lines, index):
        line = lines[index]
        if line.startswith("    "):
            return indented_code(lines, index)
        if line.startswith(" "):
            return paragraph(lines, index)
        if fence := opening_fence(line):
            return fenced_code(lines, index, *fence)
        if heading := atx_heading(line):
            return heading, index + 1
        if is_rule(line):
            return HorizontalRule(), index + 1
        if line.startswith(">"):
            return self.quote(lines, index)
        if marker := list_marker(line):
            return self.list_block(lines, index, marker)
        if self.footnote_definition(line) or self.link_definition(line):
            return None, index + 1
        return parse_table(lines, index) or paragraph(lines, index)

    def quote(self, lines, index):
        content = []
        while index < len(lines) and lines[index].startswith(">"):
            content.append(lines[index][1:].removeprefix(" "))
            index += 1
        if alert := ALERT.fullmatch(content[0]):
            return Alert(alert.group(1), self.parse(content[1:])), index
        return Quote(self.parse(content)), index

    def list_block(self, lines, index, marker):
        kind = marker.kind
        start = marker.number
        items = []
        while True:
            content = [marker.content]
            index += 1
            while index < len(lines) and lines[index].startswith("  "):
                content.append(lines[index][2:])
                index += 1
            items.append(self.parse(content))
            following = index
            while following < len(lines) and lines[following] == "":
                following += 1
            marker = list_marker(lines[following]) if following < len(lines) else None
            if marker is None or marker.kind != kind:
                return ListBlock(start is not None, start, items), index
            index = following

    def footnote_definition(self, line):
        match = FOOTNOTE_DEFINITION.match(line)
        if match is None:
            return False
        body = match.group(2).strip(" ")
        if body == "":
            return False
        self.footnotes.setdefault(match.group(1).lower(), body)
        return True

    def link_definition(self, line):
        if not line.startswith("["):
            return False
        close = line.find("]")
        if close < 0 or not line.startswith(":", close + 1):
            return False
        label = line[1:close]
        if "[" in label or label.strip(" ") == "" or label.startswith("^"):
            return False
        url, end = escaped_read(line, skip_whitespace(line, close + 2), " ")
        if url == "":
            return False
        position = skip_whitespace(line, end)
        title = None
        if position < len(line):
            if position == end or line[position] not in "\"'":
                return False
            title, end = escaped_read(line, position + 1, line[position])
            if end != len(line) - 1:
                return False
        self.references.setdefault(normalize_label(label), Reference(url, title))
        return True


def backtick_closer(text, start, length):
    for match in BACKTICKS.finditer(text, start):
        if len(match.group()) == length:
            return match.start()
    return -1


def backtick_length(text, position):
    return BACKTICKS.match(text, position).end() - position


def code_span(text, position):
    length = backtick_length(text, position)
    closer = backtick_closer(text, position + length, length)
    if closer < 0:
        return "`" * length, position + length
    code = text[position + length:closer].replace("\n", " ")
    if code.startswith(" ") and code.endswith(" ") and code.strip(" "):
        code = code[1:-1]
    return f"<code>{escape_html(code)}</code>", closer + length


def autolink(text, position):
    match = AUTOLINK.match(text, position)
    if match is None:
        return None
    target = match.group(1)
    if ANGLE_URL.match(target):
        href = target
    elif EMAIL.fullmatch(target):
        href = "mailto:" + target
    else:
        return None
    return f'<a href="{escape_html(href)}">{escape_html(target)}</a>', match.end()


def url_autolink(text, position):
    if position > 0 and text[position - 1] not in URL_PRECEDERS:
        return None
    match = BARE_URL.match(text, position)
    if match is None:
        return None
    url = match.group().rstrip(URL_TRAILERS)
    if url in ("http://", "https://"):
        return None
    return f'<a href="{escape_html(url)}">{escape_html(url)}</a>', position + len(url)


def delimiter(text, position):
    char = text[position]
    end = position
    while end < len(text) and text[end] == char:
        end += 1
    length = end - position
    before = text[position - 1] if position > 0 else " "
    after = text[end] if end < len(text) else " "
    can_open = after not in WHITESPACE
    can_close = before not in WHITESPACE
    if char == "_" and before.isalnum() and after.isalnum():
        can_open = can_close = False
    if (char != "~" and length <= 3) or (char == "~" and length == 2):
        return Delimiter(char, length, can_open, can_close), end
    return char * length, end


def find_closing_bracket(text, opening):
    depth = 0
    position = opening
    while position < len(text):
        char = text[position]
        if char == "\\":
            position += 2
            continue
        if char == "`":
            length = backtick_length(text, position)
            closer = backtick_closer(text, position + length, length)
            position = position + length if closer < 0 else closer + length
            continue
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return position
        position += 1
    return -1


def find_emphasis_closer(pieces, opener, end):
    opening = pieces[opener]
    for index in range(opener + 1, end):
        piece = pieces[index]
        if (
            isinstance(piece, Delimiter)
            and piece.can_close
            and piece.char == opening.char
            and piece.length == opening.length
        ):
            return index
    return None


def build_html(pieces, start, end):
    parts = []
    index = start
    while index < end:
        piece = pieces[index]
        if isinstance(piece, str):
            parts.append(piece)
        elif piece.can_open and (closer := find_emphasis_closer(pieces, index, end)) is not None:
            tags = STRIKETHROUGH_TAGS if piece.char == "~" else EMPHASIS_TAGS[piece.length]
            parts.append(tags[0] + build_html(pieces, index + 1, closer) + tags[1])
            index = closer
        else:
            parts.append(piece.char * piece.length)
        index += 1
    return "".join(parts)


class InlineParser:
    def __init__(self, renderer, text, links, footnotes):
        self.renderer = renderer
        self.text = text
        self.links = links
        self.footnotes = footnotes

    def convert(self):
        pieces = []
        position = 0
        while position < len(self.text):
            piece, position = self.next_piece(position)
            pieces.append(piece)
        return build_html(pieces, 0, len(pieces))

    def next_piece(self, position):
        text = self.text
        char = text[position]
        following = text[position + 1:position + 2]
        if char == "\\":
            if following in PUNCTUATION:
                return escape_html(following), position + 2
            if following == "\n":
                return "<br />\n", position + 2
            return "\\", position + 1
        if char == "`":
            return code_span(text, position)
        if self.links:
            if char == "<" and (link := autolink(text, position)):
                return link
            if link := url_autolink(text, position):
                return link
        if char == "[" or (char == "!" and following == "["):
            return self.bracket(position) or (char, position + 1)
        if char in "*_~":
            return delimiter(text, position)
        return escape_html(char), position + 1

    def bracket(self, position):
        text = self.text
        renderer = self.renderer
        if self.footnotes and text.startswith("[^", position):
            close = text.find("]", position + 2)
            if close >= 0 and (name := text[position + 2:close].lower()) in renderer.footnotes:
                return renderer.footnote_reference(name), close + 1
        image = text[position] == "!"
        if not image and not self.links:
            return None
        opening = position + 1 if image else position
        closing = find_closing_bracket(text, opening)
        if closing < 0:
            return None
        label = text[opening + 1:closing]
        destination = self.destination(closing + 1, label)
        if destination is None:
            return None
        reference, end = destination
        url = escape_html(reference.url)
        title = "" if reference.title is None else f' title="{escape_html(reference.title)}"'
        content = renderer.inline(label, links=False, footnotes=False)
        if image:
            return f'<img src="{url}" alt="{strip_tags(content)}"{title} />', end
        return f'<a href="{url}"{title}>{content}</a>', end

    def destination(self, position, label):
        text = self.text
        references = self.renderer.references
        if text.startswith("[", position):
            close = text.find("]", position + 1)
            if close >= 0 and "[" not in text[position + 1:close]:
                name = normalize_label(text[position + 1:close] or label)
                if name not in references:
                    return None
                return references[name], close + 1
        elif text.startswith("(", position) and (link := self.inline_destination(position + 1)):
            return link
        name = normalize_label(label)
        if name in references:
            return references[name], position
        return None

    def inline_destination(self, position):
        text = self.text
        url, end = escaped_read(text, skip_whitespace(text, position), WHITESPACE + ")")
        position = skip_whitespace(text, end)
        title = None
        if position > end and text.startswith(('"', "'"), position):
            title, end = escaped_read(text, position + 1, text[position])
            if end == len(text):
                return None
            position = skip_whitespace(text, end + 1)
        if text.startswith(")", position):
            return Reference(url, title), position + 1
        return None


def heading_slug(text):
    slug = NON_SLUG.sub("", text.lower())
    return slug.replace(" ", "-").replace("\n", "-") or "heading"


def footnote_reference_id(number, count):
    return f"fnref-{number}" if count == 1 else f"fnref-{number}-{count}"


def toc_list(entries):
    items = []
    for entry in entries:
        link = f'<li><a href="#{entry.identifier}">{entry.label}</a>'
        if entry.children:
            items.append(f"{link}\n{toc_list(entry.children)}\n</li>\n")
        else:
            items.append(f"{link}</li>\n")
    return "<ul>\n" + "".join(items) + "</ul>"


class Renderer:
    def __init__(self, references, footnotes):
        self.references = references
        self.footnotes = footnotes
        self.used_ids = set()
        self.headings = []
        self.footnote_numbers = {}
        self.footnote_counts = {}

    def inline(self, text, links=True, footnotes=True):
        return InlineParser(self, text, links, footnotes).convert()

    def render_document(self, blocks):
        html = self.render_blocks(blocks).replace(TOC_MARKER, self.table_of_contents())
        if self.footnote_numbers:
            html += self.footnote_list()
        return html

    def render_blocks(self, blocks):
        return "".join(self.render_block(block) + "\n" for block in blocks)

    def render_block(self, block):
        match block:
            case Heading(level, text):
                return self.render_heading(level, text)
            case Paragraph(text):
                return f"<p>{self.inline(text)}</p>"
            case HorizontalRule():
                return "<hr />"
            case CodeBlock(language, lines):
                attribute = f' class="language-{escape_html(language)}"' if language else ""
                code = "".join(escape_html(line) + "\n" for line in lines)
                return f"<pre><code{attribute}>{code}</code></pre>"
            case Quote(blocks):
                return f"<blockquote>\n{self.render_blocks(blocks)}</blockquote>"
            case Alert(kind, blocks):
                return (
                    f'<div class="alert alert-{kind.lower()}">\n'
                    f'<p class="alert-title">{kind.capitalize()}</p>\n'
                    f"{self.render_blocks(blocks)}</div>"
                )
            case ListBlock():
                return self.render_list(block)
            case Table():
                return self.render_table(block)
            case TableOfContents():
                return TOC_MARKER

    def render_heading(self, level, text):
        start = text.rfind(" {#")
        if text.endswith("}") and start >= 0 and LABEL.fullmatch(text[start + 3:-1]):
            identifier = text[start + 3:-1]
            text = text[:start].rstrip(" ")
        else:
            identifier = self.unique_id(heading_slug(text))
        self.used_ids.add(identifier)
        html = self.inline(text)
        self.headings.append(TocEntry(level, identifier, strip_tags(html)))
        return f'<h{level} id="{identifier}">{html}</h{level}>'

    def unique_id(self, base):
        identifier = base
        suffix = 1
        while identifier in self.used_ids:
            identifier = f"{base}-{suffix}"
            suffix += 1
        return identifier

    def render_list(self, block):
        if not block.ordered:
            opening, closing = "<ul>", "</ul>"
        elif block.start == 1:
            opening, closing = "<ol>", "</ol>"
        else:
            opening, closing = f'<ol start="{block.start}">', "</ol>"
        items = "".join(self.render_item(item) + "\n" for item in block.items)
        return f"{opening}\n{items}{closing}"

    def render_item(self, blocks):
        html = "<li>"
        for position, block in enumerate(blocks):
            if isinstance(block, Paragraph):
                text = block.text
                checkbox = TASK_BOXES.get(text[:4]) if position == 0 and len(text) > 4 else None
                if checkbox:
                    html += f"{checkbox} {self.inline(text[4:])}"
                else:
                    html += self.inline(text)
            else:
                if not html.endswith("\n"):
                    html += "\n"
                html += self.render_block(block) + "\n"
        return html + "</li>"

    def render_table(self, table):
        lines = ["<table>", "<thead>", "<tr>"]
        lines += self.table_cells("th", table.alignments, table.header)
        lines += ["</tr>", "</thead>"]
        if table.rows:
            lines.append("<tbody>")
            for row in table.rows:
                lines.append("<tr>")
                lines += self.table_cells("td", table.alignments, row)
                lines.append("</tr>")
            lines.append("</tbody>")
        lines.append("</table>")
        return "\n".join(lines)

    def table_cells(self, tag, alignments, cells):
        html = []
        for alignment, cell in zip(alignments, cells):
            style = f' style="text-align:{alignment}"' if alignment else ""
            html.append(f"<{tag}{style}>{self.inline(cell)}</{tag}>")
        return html

    def table_of_contents(self):
        if not self.headings:
            return '<nav class="toc">\n</nav>'
        roots = []
        parents = []
        for heading in self.headings:
            while parents and parents[-1].level >= heading.level:
                parents.pop()
            (parents[-1].children if parents else roots).append(heading)
            parents.append(heading)
        return f'<nav class="toc">\n{toc_list(roots)}\n</nav>'

    def footnote_reference(self, name):
        if name not in self.footnote_numbers:
            self.footnote_numbers[name] = len(self.footnote_numbers) + 1
            self.footnote_counts[name] = 0
        number = self.footnote_numbers[name]
        self.footnote_counts[name] += 1
        reference_id = footnote_reference_id(number, self.footnote_counts[name])
        return f'<sup id="{reference_id}"><a href="#fn-{number}">{number}</a></sup>'

    def footnote_list(self):
        lines = ['<section class="footnotes">', "<ol>"]
        for name, number in self.footnote_numbers.items():
            body = self.inline(self.footnotes[name], footnotes=False)
            backlinks = " ".join(
                f'<a href="#{footnote_reference_id(number, count)}">&#8617;</a>'
                for count in range(1, self.footnote_counts[name] + 1)
            )
            lines.append(f'<li id="fn-{number}">{body} {backlinks}</li>')
        lines += ["</ol>", "</section>"]
        return "".join(line + "\n" for line in lines)


def main():
    lines = sys.stdin.read().split("\n")
    parser = BlockParser()
    blocks = parser.parse(lines[:lines.index(TERMINATOR)])
    renderer = Renderer(parser.references, parser.footnotes)
    sys.stdout.write(renderer.render_document(blocks))


if __name__ == "__main__":
    main()
