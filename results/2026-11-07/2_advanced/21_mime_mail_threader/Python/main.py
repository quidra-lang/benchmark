import os
import string

from addresses import Group, parse_address_list
from dates import DateError, format_utc, parse_date
from headers import (
    collapse_whitespace, decode_unstructured, parse_fields, parse_parameters,
    remove_comments, split_words,
)
from mime import decode_base64_body, decode_quoted_printable
from threader import build_threads, root_subject


INPUT_DIR = "input"
OUTPUT_DIR = "output"
WHITESPACE = " \t"
CHECKED_FIELDS = (
    "From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References",
    "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition",
)
ID_FORBIDDEN = '<>()"\\'
IDENTITY_ENCODINGS = ("7bit", "8bit", "binary")
LINE_WIDTH = 72
HIDDEN_TAGS = ("head", "style", "script")
PARAGRAPH_TAGS = (
    "p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6",
)
CHARACTER_REFERENCES = {
    "amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'", "nbsp": " ",
}
TAG_NAME_CHARS = string.ascii_letters + string.digits
SENDERS_HEADER = "address,name,messages,threads,first,last"


def read_lines(path):
    with open(path) as handle:
        lines = handle.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def restore_from_line(line):
    unquoted = line.lstrip(">")
    if unquoted != line and unquoted.startswith("From "):
        return line[1:]
    return line


def read_mailbox(path):
    messages = []
    for number, line in enumerate(read_lines(path), 1):
        if line.startswith("From "):
            messages.append([])
        elif messages:
            messages[-1].append((number, restore_from_line(line)))
    for lines in messages:
        if lines and lines[-1][1] == "":
            lines.pop()
    return messages


def split_sections(lines):
    for index, (_, text) in enumerate(lines):
        if text == "":
            return lines[:index], lines[index + 1:]
    return lines, []


def is_message_id(text):
    if len(text) < 3 or not text.startswith("<") or not text.endswith(">"):
        return False
    inside = text[1:-1]
    if inside.count("@") != 1 or inside.startswith("@") or inside.endswith("@"):
        return False
    return all(33 <= ord(char) <= 126 and char not in ID_FORBIDDEN for char in inside)


def extract_ids(value):
    ids = []
    start = value.find("<")
    while start >= 0:
        end = value.find(">", start + 1)
        if end < 0:
            break
        if is_message_id(value[start:end + 1]):
            ids.append(value[start:end + 1])
        start = value.find("<", end + 1)
    return ids


def date_notation(seconds):
    return "invalid" if seconds is None else format_utc(seconds)


def subject_notation(subject):
    return subject if subject else "(no subject)"


class Entity:
    def __init__(self, number):
        self.number = number
        self.main_type = "text"
        self.subtype = "plain"
        self.parameters = {}
        self.disposition = None
        self.filename = None
        self.children = None
        self.content = ""

    def is_multipart(self):
        return self.children is not None

    def parameter(self, name):
        return self.parameters.get(name, "")


class Message:
    def __init__(self, number):
        self.number = number
        self.problems = []
        self.sender = None
        self.to = []
        self.cc = []
        self.subject = ""
        self.base_subject = ""
        self.reply = False
        self.date = None
        self.id = ""
        self.references = []
        self.body = None
        self.sort_key = None
        self.thread = 0
        self.depth = 0
        self.parent = None

    def problem(self, text):
        self.problems.append(text)

    def process(self, lines, known_ids):
        header_lines, body_lines = split_sections(lines)
        header = parse_fields(header_lines)
        for line_number in header.invalid_lines:
            self.problem(f"bad header line {line_number}")
        for name in CHECKED_FIELDS:
            if header.count(name) > 1:
                self.problem("duplicate " + name)
        self.read_sender(header.value("From"))
        self.to = self.read_recipients(header.value("To"), "To")
        self.cc = self.read_recipients(header.value("Cc"), "Cc")
        self.read_subject(header.value("Subject"))
        self.read_date(header.value("Date"))
        self.read_id(header.value("Message-ID"), known_ids)
        self.read_references(header.value("References"), header.value("In-Reply-To"))
        mime = self.mime_enabled(header.value("MIME-Version"))
        self.body = self.parse_entity("1", header, body_lines, mime)
        if self.date is None:
            self.sort_key = (1, 0, self.id, self.number)
        else:
            self.sort_key = (0, self.date, self.id, self.number)

    def read_sender(self, value):
        if value is None:
            self.problem("missing From")
            return
        parsed = parse_address_list(value)
        if parsed is None or len(parsed[0]) != 1 or isinstance(parsed[0][0], Group):
            self.problem("bad From")
            return
        addresses, encoding_error = parsed
        self.sender = addresses[0]
        if encoding_error:
            self.problem("bad encoded word in From")

    def read_recipients(self, value, name):
        if value is None:
            return []
        parsed = parse_address_list(value)
        if parsed is None:
            self.problem("bad " + name)
            return []
        addresses, encoding_error = parsed
        recipients = []
        for address in addresses:
            if isinstance(address, Group):
                recipients.extend(mailbox.address for mailbox in address.mailboxes)
            else:
                recipients.append(address.address)
        if encoding_error:
            self.problem("bad encoded word in " + name)
        return recipients

    def read_subject(self, value):
        self.subject, encoding_error = decode_unstructured(value or "")
        if encoding_error:
            self.problem("bad encoded word in Subject")
        base = self.subject
        while base[:3].lower() == "re:":
            base = base[3:].lstrip(" ")
            self.reply = True
        self.base_subject = base

    def read_date(self, value):
        if value is None:
            self.problem("missing Date")
            return
        try:
            self.date = parse_date(value)
        except DateError as error:
            self.problem(str(error))

    def read_id(self, value, known_ids):
        if value is None:
            self.problem("missing Message-ID")
        elif not is_message_id(value):
            self.problem("bad Message-ID")
        elif value in known_ids:
            self.problem(f"Message-ID already used by message {known_ids[value]}")
        else:
            self.id = value
            known_ids[value] = self.number

    def read_references(self, references, in_reply_to):
        self.references = extract_ids(references or "")
        replies = extract_ids(in_reply_to or "")
        if replies and (not self.references or self.references[-1] != replies[0]):
            self.references.append(replies[0])

    def mime_enabled(self, value):
        if value is None:
            return False
        text = remove_comments(value)
        if text is not None and text.replace(" ", "").replace("\t", "") == "1.0":
            return True
        self.problem("bad MIME-Version")
        return False

    def parse_entity(self, number, header, lines, mime):
        entity = Entity(number)
        content_type = header.value("Content-Type")
        if mime and content_type is not None:
            parsed = parse_parameters(content_type, True)
            if parsed is None:
                self.problem(f"bad Content-Type in part {number}")
            else:
                entity.main_type, entity.subtype, entity.parameters = parsed
        disposition = header.value("Content-Disposition")
        if mime and disposition is not None:
            parsed = parse_parameters(disposition, False)
            if parsed is None:
                self.problem(f"bad Content-Disposition in part {number}")
            else:
                entity.disposition, _, parameters = parsed
                entity.filename = parameters.get("filename")
        if not entity.filename:
            entity.filename = entity.parameters.get("name")
        charset = entity.parameters.get("charset")
        if entity.main_type == "text" and charset is not None and charset.lower() != "us-ascii":
            self.problem(f'unsupported charset "{charset.lower()}" in part {number}')
        if mime and entity.main_type == "multipart":
            boundary = entity.parameter("boundary")
            if boundary:
                self.split_multipart(entity, lines, boundary)
                return entity
            self.problem(f"missing boundary in part {number}")
        self.decode_leaf(entity, header, lines, mime)
        return entity

    def split_multipart(self, entity, lines, boundary):
        parts = []
        closed = False
        for line in lines:
            text = line[1].rstrip(WHITESPACE)
            if text == "--" + boundary + "--":
                closed = True
                break
            if text == "--" + boundary:
                parts.append([])
            elif parts:
                parts[-1].append(line)
        if not parts:
            self.problem(f"no parts in part {entity.number}")
        elif not closed:
            self.problem(f"unterminated multipart in part {entity.number}")
        entity.children = []
        for index, part_lines in enumerate(parts, 1):
            header_lines, body_lines = split_sections(part_lines)
            header = parse_fields(header_lines)
            for line_number in header.invalid_lines:
                self.problem(f"bad header line {line_number}")
            number = f"{entity.number}.{index}"
            entity.children.append(self.parse_entity(number, header, body_lines, True))

    def decode_leaf(self, entity, header, lines, mime):
        original = "\n".join(text for _, text in lines)
        encoding = "7bit"
        transfer_encoding = header.value("Content-Transfer-Encoding")
        if mime and transfer_encoding is not None:
            encoding = transfer_encoding.lower()
        if encoding == "base64":
            content = decode_base64_body(original)
            if content is None:
                self.problem(f"bad base64 in part {entity.number}")
                content = ""
        elif encoding == "quoted-printable":
            content, error = decode_quoted_printable(original)
            if error:
                self.problem(f"bad quoted-printable in part {entity.number}")
        else:
            content = original
            if encoding not in IDENTITY_ENCODINGS:
                self.problem(f'unknown encoding "{encoding}" in part {entity.number}')
        entity.content = content


class LogicalLine:
    def __init__(self, depth, text, flowing=False):
        self.depth = depth
        self.text = text
        self.flowing = flowing


def collect_text_parts(entity, allow_html):
    if not entity.is_multipart():
        if entity.disposition == "attachment" or entity.main_type != "text":
            return []
        if entity.subtype == "plain" or entity.subtype == "html" and allow_html:
            return [entity]
        return []
    if entity.subtype == "alternative":
        for html_pass in (False, True):
            for child in entity.children:
                parts = collect_text_parts(child, html_pass)
                if parts:
                    return parts
        return []
    parts = []
    for child in entity.children:
        parts.extend(collect_text_parts(child, allow_html))
    return parts


def quote_prefix(depth):
    return ">" * depth + " " if depth > 0 else ""


def wrap(text, prefix):
    lines = []
    current = ""
    for word in split_words(text):
        if current and len(current) + 1 + len(word) > LINE_WIDTH:
            lines.append(current)
            current = word
        elif current:
            current += " " + word
        else:
            current = word
    lines.append(current)
    return [prefix + line for line in lines]


def flowed_lines(content, delete_space):
    if content == "":
        return []
    logical = []
    for line in content.split("\n"):
        text = line.lstrip(">")
        depth = len(line) - len(text)
        if text.startswith(" "):
            text = text[1:]
        flowing = text.endswith(" ") and text != "-- "
        previous = logical[-1] if logical else None
        if previous is not None and previous.flowing and previous.depth == depth:
            if delete_space:
                previous.text = previous.text[:-1]
            previous.text += text
            previous.flowing = flowing
        else:
            logical.append(LogicalLine(depth, text, flowing))
    lines = []
    for line in logical:
        lines.extend(wrap(line.text, quote_prefix(line.depth)))
    return lines


def tag_name(text):
    end = 0
    while end < len(text) and text[end] in TAG_NAME_CHARS:
        end += 1
    return text[:end].lower()


def reference_value(name):
    if name in CHARACTER_REFERENCES:
        return CHARACTER_REFERENCES[name]
    digits = name[1:]
    if name.startswith("#") and 1 <= len(digits) <= 3 and digits.isdigit():
        if 32 <= int(digits) <= 126:
            return chr(int(digits))
    return None


def replace_references(text):
    result = []
    position = 0
    while position < len(text):
        replacement = None
        if text[position] == "&":
            end = text.find(";", position + 1)
            if end >= 0:
                replacement = reference_value(text[position + 1:end])
        if replacement is None:
            result.append(text[position])
            position += 1
        else:
            result.append(replacement)
            position = end + 1
    return "".join(result)


def html_blocks(content):
    blocks = []
    depth = 0
    text = []
    hide = None
    position = 0
    while position < len(content):
        char = content[position]
        close = content.find(">", position + 1) if char == "<" else -1
        if close < 0:
            if hide is None:
                text.append(char)
            position += 1
            continue
        inside = content[position + 1:close]
        position = close + 1
        end_tag = inside.startswith("/")
        name = tag_name(inside[1:] if end_tag else inside)
        if hide is not None:
            if end_tag and name == hide:
                hide = None
        elif not end_tag and name in HIDDEN_TAGS:
            hide = name
        elif name == "br" or name == "li" and not end_tag:
            blocks.append(LogicalLine(depth, "".join(text)))
            text = ["* "] if name == "li" else []
        elif name in PARAGRAPH_TAGS:
            blocks.append(LogicalLine(depth, "".join(text)))
            blocks.append(LogicalLine(depth, ""))
            text = []
            if name == "blockquote":
                depth = max(depth - 1, 0) if end_tag else depth + 1
    blocks.append(LogicalLine(depth, "".join(text)))
    return blocks


def html_lines(content):
    lines = []
    for block in html_blocks(content):
        text = collapse_whitespace(block.text.replace("\n", " "))
        text = replace_references(text).strip(" ")
        if text:
            lines.extend(wrap(text, quote_prefix(block.depth)))
        elif lines and lines[-1] != "":
            lines.append("")
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def display_lines(entity):
    if entity.subtype == "html":
        return "html", html_lines(entity.content)
    if entity.parameter("format").lower() == "flowed":
        delete_space = entity.parameter("delsp").lower() == "yes"
        return "flowed", flowed_lines(entity.content, delete_space)
    if entity.content == "":
        return "plain", []
    return "plain", entity.content.split("\n")


def line_counts(lines):
    stripped = [line.rstrip(WHITESPACE) for line in lines]
    quoted = sum(1 for line in stripped if line.startswith(">"))
    signature = 0
    for index, line in enumerate(stripped):
        if line == "--":
            signature = len(stripped) - index - 1
    return quoted, signature


class Thread:
    def __init__(self, number, root):
        self.number = number
        self.root = root
        self.entries = []
        self.walk(root, "", "", 0)
        self.messages = [
            container.message for container, _, _ in self.entries
            if container.message is not None
        ]

    def walk(self, container, prefix, stem, depth):
        self.entries.append((container, prefix, depth))
        last = len(container.children) - 1
        for index, child in enumerate(container.children):
            if index < last:
                self.walk(child, stem + "+- ", stem + "|  ", depth + 1)
            else:
                self.walk(child, stem + "`- ", stem + "   ", depth + 1)

    def place_messages(self):
        for container, _, depth in self.entries:
            message = container.message
            if message is None:
                continue
            message.thread = self.number
            message.depth = depth
            parent = container.parent
            message.parent = parent.message if parent is not None else None

    def subject(self):
        if self.root.subject is not None:
            return self.root.subject
        return root_subject(self.root)

    def report(self):
        depth = max(depth for _, _, depth in self.entries)
        senders = {
            message.sender.address for message in self.messages if message.sender is not None
        }
        dates = [message.date for message in self.messages if message.date is not None]
        lines = [
            f"thread {self.number} messages {len(self.messages)} depth {depth} "
            f"senders {len(senders)}"
        ]
        if dates:
            lines.append(f"span {format_utc(min(dates))} .. {format_utc(max(dates))}")
        else:
            lines.append("span -")
        lines.append("subject " + subject_notation(self.subject()))
        for container, prefix, _ in self.entries:
            lines.append(prefix + container_notation(container))
        return lines


def container_notation(container):
    message = container.message
    if message is not None:
        sender = message.sender.address if message.sender is not None else "-"
        return (
            f"[{message.number}] {date_notation(message.date)} {sender} "
            f"{subject_notation(message.subject)}"
        )
    if container.subject is not None:
        return "[subject] " + container.subject
    return "[missing] " + container.id


def check_parent_dates(messages):
    for message in messages:
        parent = message.parent
        if parent is None or message.date is None or parent.date is None:
            continue
        if message.date < parent.date:
            message.problem(f"dated before parent message {parent.number}")


def sender_notation(sender):
    if sender is None:
        return "-"
    if sender.name:
        return f"{sender.name} <{sender.address}>"
    return sender.address


def entity_lines(entity, lines):
    line = f"part {entity.number} {entity.main_type}/{entity.subtype}"
    if entity.is_multipart():
        lines.append(line)
        for child in entity.children:
            entity_lines(child, lines)
        return
    line += f" {len(entity.content)}"
    if entity.disposition is not None:
        line += " " + entity.disposition
    if entity.filename:
        line += f' "{entity.filename}"'
    lines.append(line)


def message_report(message):
    parent = message.parent.number if message.parent is not None else "-"
    lines = [
        f"message {message.number}",
        "id " + (message.id or "-"),
        "date " + date_notation(message.date),
        "from " + sender_notation(message.sender),
        "to " + (", ".join(message.to) or "-"),
        "cc " + (", ".join(message.cc) or "-"),
        "subject " + subject_notation(message.subject),
        "refs " + (" ".join(message.references) or "-"),
        f"thread {message.thread} depth {message.depth} parent {parent}",
    ]
    entity_lines(message.body, lines)
    return lines


def body_report(request, messages_by_id):
    lines = ["request " + request]
    message = messages_by_id.get(request)
    if message is None:
        lines.append("not found")
        return lines
    parts = collect_text_parts(message.body, True)
    lines.append(f"message {message.number} text parts {len(parts)}")
    for part in parts:
        text_format, display = display_lines(part)
        quoted, signature = line_counts(display)
        lines.append(
            f"part {part.number} {text_format} lines {len(display)} "
            f"quoted {quoted} signature {signature}"
        )
        for line in display:
            line = line.rstrip(WHITESPACE)
            lines.append("| " + line if line else "|")
    return lines


class SenderStats:
    def __init__(self, address):
        self.address = address
        self.count = 0
        self.threads = set()
        self.first = None
        self.last = None
        self.name = ""

    def add(self, message):
        self.count += 1
        self.threads.add(message.thread)
        if message.date is not None:
            if self.first is None or message.date < self.first:
                self.first = message.date
            if self.last is None or message.date > self.last:
                self.last = message.date
        if message.sender.name:
            self.name = message.sender.name

    def order(self):
        return -self.count, self.address


def csv_field(text):
    if "," in text or '"' in text:
        return '"' + text.replace('"', '""') + '"'
    return text


def senders_report(messages):
    stats = {}
    for message in messages:
        if message.sender is None:
            continue
        address = message.sender.address
        if address not in stats:
            stats[address] = SenderStats(address)
        stats[address].add(message)
    lines = [SENDERS_HEADER]
    for entry in sorted(stats.values(), key=SenderStats.order):
        first = format_utc(entry.first) if entry.first is not None else "-"
        last = format_utc(entry.last) if entry.last is not None else "-"
        lines.append(
            f"{entry.address},{csv_field(entry.name)},{entry.count},"
            f"{len(entry.threads)},{first},{last}"
        )
    return lines


def malformed_report(messages):
    flagged = [message for message in messages if message.problems]
    total = sum(len(message.problems) for message in messages)
    lines = [f"messages {len(messages)} malformed {len(flagged)} problems {total}"]
    for message in flagged:
        for problem in message.problems:
            lines.append(f"message {message.number}: {problem}")
    return lines


def join_blocks(blocks):
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


def write_output(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    messages = []
    known_ids = {}
    for number, lines in enumerate(read_mailbox(os.path.join(INPUT_DIR, "mailbox.mbox")), 1):
        message = Message(number)
        message.process(lines, known_ids)
        messages.append(message)
    threads = [Thread(number, root) for number, root in enumerate(build_threads(messages), 1)]
    for thread in threads:
        thread.place_messages()
    check_parent_dates(messages)
    messages_by_id = {message.id: message for message in messages if message.id}
    requests = read_lines(os.path.join(INPUT_DIR, "requests.txt"))
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_output("threads.txt", join_blocks(thread.report() for thread in threads))
    write_output("messages.txt", join_blocks(message_report(message) for message in messages))
    write_output(
        "bodies.txt",
        join_blocks(body_report(request, messages_by_id) for request in requests),
    )
    write_output("senders.csv", senders_report(messages))
    write_output("malformed.txt", malformed_report(messages))


if __name__ == "__main__":
    main()
