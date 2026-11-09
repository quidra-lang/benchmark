from headers import collapse_whitespace, decode_word, tokenize_address


PHRASE_KINDS = ("word", "quoted", ".")
DOT_ATOM_KINDS = ("word", ".")


class AddressError(Exception):
    pass


class Mailbox:
    def __init__(self, name, address):
        self.name = name
        self.address = address


class Group:
    def __init__(self, mailboxes):
        self.mailboxes = mailboxes


def is_dot_atom(tokens):
    if len(tokens) % 2 == 0:
        return False
    for index, token in enumerate(tokens):
        if token.kind != ("word" if index % 2 == 0 else "."):
            return False
    return True


def address_string(local, domain):
    if not is_dot_atom(local) or not is_dot_atom(domain):
        raise AddressError
    text = "".join(token.text for token in local) + "@" + "".join(token.text for token in domain)
    return text.lower()


class AddressParser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0
        self.encoding_error = False

    def peek(self):
        if self.position < len(self.tokens):
            return self.tokens[self.position].kind
        return None

    def expect(self, kind):
        if self.peek() != kind:
            raise AddressError
        self.position += 1

    def read_run(self, kinds):
        start = self.position
        while self.peek() in kinds:
            self.position += 1
        return self.tokens[start:self.position]

    def display_name(self, phrase):
        parts = []
        previous_decoded = False
        for index, token in enumerate(phrase):
            text = token.text
            decoded = False
            if token.kind == "word":
                text, decoded, failed = decode_word(token.text)
                self.encoding_error = self.encoding_error or failed
            if index > 0 and token.spaced and not (decoded and previous_decoded):
                parts.append(" ")
            parts.append(text)
            previous_decoded = decoded
        return collapse_whitespace("".join(parts))

    def parse_address(self, in_group):
        phrase = self.read_run(PHRASE_KINDS)
        following = self.peek()
        if following == "<":
            self.position += 1
            local = self.read_run(DOT_ATOM_KINDS)
            self.expect("@")
            domain = self.read_run(DOT_ATOM_KINDS)
            self.expect(">")
            return Mailbox(self.display_name(phrase), address_string(local, domain))
        if following == "@":
            self.position += 1
            domain = self.read_run(DOT_ATOM_KINDS)
            return Mailbox("", address_string(phrase, domain))
        if following == ":" and phrase and not in_group:
            self.position += 1
            mailboxes = []
            if self.peek() != ";":
                mailboxes.append(self.parse_address(True))
                while self.peek() == ",":
                    self.position += 1
                    mailboxes.append(self.parse_address(True))
            self.expect(";")
            return Group(mailboxes)
        raise AddressError

    def parse_list(self):
        addresses = [self.parse_address(False)]
        while self.peek() == ",":
            self.position += 1
            addresses.append(self.parse_address(False))
        if self.position != len(self.tokens):
            raise AddressError
        return addresses


def parse_address_list(value):
    tokens = tokenize_address(value)
    if not tokens:
        return None
    parser = AddressParser(tokens)
    try:
        addresses = parser.parse_list()
    except AddressError:
        return None
    return addresses, parser.encoding_error
