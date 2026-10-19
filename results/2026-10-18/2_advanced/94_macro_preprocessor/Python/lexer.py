"""Preprocessing tokens, physical positions, splicing, and logical lines."""

from collections import namedtuple


Token = namedtuple("Token", "kind spelling line space hide", defaults=[frozenset()])
LogicalLine = namedtuple("LogicalLine", "tokens start end")
PUNCTUATORS = (
    "...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
    "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##", "[", "]", "(", ")", "{", "}",
    ".", "&", "*", "+", "-", "~", "!", "/", "%", "<", ">", "^", "|", "?", ":", ";", "=", ",", "#",
)


def identifier_start(character):
    return character == "_" or "a" <= character <= "z" or "A" <= character <= "Z"


def digit(character):
    return "0" <= character <= "9"


def read_token(text, position=0, header=False):
    character, length = text[position], len(text)
    if header and character == "<":
        closing, newline = text.find(">", position + 1), text.find("\n", position + 1)
        if closing >= 0 and (newline < 0 or closing < newline):
            return "header", text[position:closing + 1], closing + 1
    if identifier_start(character):
        end = position + 1
        while end < length and (identifier_start(text[end]) or digit(text[end])):
            end += 1
        return "identifier", text[position:end], end
    if digit(character) or character == "." and position + 1 < length and digit(text[position + 1]):
        end = position + 1
        while end < length:
            if text[end] in "eEpP" and end + 1 < length and text[end + 1] in "+-":
                end += 2
            elif identifier_start(text[end]) or digit(text[end]) or text[end] == ".":
                end += 1
            else:
                break
        return "number", text[position:end], end
    if character in "\"'":
        end = position + 1
        while end < length and text[end] != "\n":
            if text[end] == character:
                kind = "string" if character == '"' else "character"
                return kind, text[position:end + 1], end + 1
            if text[end] == "\\" and end + 1 < length and text[end + 1] != "\n":
                end += 2
            else:
                end += 1
    for punctuator in PUNCTUATORS:
        if text.startswith(punctuator, position):
            return "punctuator", punctuator, position + len(punctuator)
    return "other", character, position + 1


def splice(text):
    characters, positions = [], []
    index, line = 0, 1
    while index < len(text):
        if text.startswith("\\\n", index):
            index += 2
            line += 1
            continue
        character = text[index]
        characters.append(character)
        positions.append(line)
        if character == "\n":
            line += 1
        index += 1
    return "".join(characters), positions


def scan(text, positions, start=1):
    lines, tokens = [], []
    index, spaced = 0, True
    while index < len(text):
        if text[index] == " ":
            spaced = True
            index += 1
        elif text[index] == "\n":
            end = positions[index]
            lines.append(LogicalLine(tuple(tokens), start, end))
            tokens, start, spaced = [], end + 1, True
            index += 1
        elif text.startswith("/*", index):
            closing = text.find("*/", index + 2)
            index = len(text) if closing < 0 else closing + 2
            spaced = True
        elif text.startswith("//", index):
            closing = text.find("\n", index + 2)
            index = len(text) if closing < 0 else closing
            spaced = True
        else:
            header = len(tokens) == 2 and tokens[0].spelling == "#" and tokens[1].spelling == "include"
            kind, spelling, end = read_token(text, index, header)
            tokens.append(Token(kind, spelling, positions[index], spaced))
            index, spaced = end, False
    if tokens:
        lines.append(LogicalLine(tuple(tokens), start, positions[-1]))
    return tuple(lines)


def lex_source(text):
    spliced, positions = splice(text)
    return scan(spliced, positions)


def lex_definition(text, line):
    text += "\n"
    lines = scan(text, [line] * len(text), line)
    return tuple(token for logical in lines for token in logical.tokens)


def render(tokens):
    return "".join((" " if index and token.space else "") + token.spelling for index, token in enumerate(tokens))


def single_token(text):
    if not text or text.startswith(("//", "/*")):
        return None
    kind, _, end = read_token(text)
    return kind if end == len(text) else None
