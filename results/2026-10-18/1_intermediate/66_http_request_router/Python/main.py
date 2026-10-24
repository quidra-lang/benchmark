import re
import string
import sys
import zlib
from collections import Counter


ROUTE_METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE")
KNOWN_METHODS = ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
OVERRIDE_METHODS = ("PUT", "PATCH", "DELETE")
REDIRECT_CODES = ("301", "302", "307", "308")
NO_ROLE = "none"
ADMIN_ROLE = "admin"
DEFAULT_TYPE = "application/json"
REASONS = {
    200: "OK",
    204: "No Content",
    301: "Moved Permanently",
    302: "Found",
    304: "Not Modified",
    307: "Temporary Redirect",
    308: "Permanent Redirect",
    400: "Bad Request",
    401: "Unauthorized",
    403: "Forbidden",
    404: "Not Found",
    405: "Method Not Allowed",
    406: "Not Acceptable",
    412: "Precondition Failed",
    429: "Too Many Requests",
    501: "Not Implemented",
}
HEADER_ORDER = (
    "Location",
    "Allow",
    "Retry-After",
    "WWW-Authenticate",
    "Access-Control-Allow-Origin",
    "Access-Control-Allow-Methods",
    "Vary",
    "ETag",
    "Content-Type",
    "Content-Length",
)
UNRESERVED = frozenset(string.ascii_letters + string.digits + "-._~")

VALID_NAME = re.compile(r"[a-z][a-z0-9_]{0,19}")
ROLE_NAME = re.compile(r"[a-z]{1,16}")
SEGMENT = re.compile(r"[A-Za-z0-9._~-]+")
MEDIA_TYPE = re.compile(r"[a-z0-9.+-]+/[a-z0-9.+-]+")
MAIN_TYPE_RANGE = re.compile(r"[a-z0-9.+-]+/\*")
TOKEN_VALUE = re.compile(r"[A-Za-z0-9._-]{1,32}")
ORIGIN = re.compile(r"https?://[a-z0-9.:-]+")
DECIMAL = re.compile(r"0|[1-9][0-9]*")
REQUEST_METHOD = re.compile(r"[A-Z]{1,16}")
HEADER_NAME = re.compile(r"[A-Za-z0-9-]+")
ESCAPE = re.compile(r"%([0-9A-Fa-f]{2})")
INT_VALUE = re.compile(r"[0-9]{1,9}")
SLUG_VALUE = re.compile(r"[a-z0-9-]+")
Q_VALUE = re.compile(r"0(\.[0-9]{0,3})?|1(\.0{0,3})?")
PARAMETER_PIECE = re.compile(r"\{([a-z][a-z0-9_]{0,19})(?::(int|slug))?\}")
WILDCARD_PIECE = re.compile(r"\{\*([a-z][a-z0-9_]{0,19})\}")

LITERAL = "literal"
UNTYPED = "untyped"
INT = "int"
SLUG = "slug"
WILDCARD = "wildcard"
PARAMETER_KINDS = {None: UNTYPED, "int": INT, "slug": SLUG}


class ConfigError(Exception):
    pass


class UrlError(Exception):
    pass


def is_segment(text):
    return SEGMENT.fullmatch(text) is not None and text not in (".", "..")


def is_canonical_path(path):
    if path == "/":
        return True
    return path.startswith("/") and all(is_segment(part) for part in path[1:].split("/"))


def is_decimal_between(text, low, high):
    return DECIMAL.fullmatch(text) is not None and low <= int(text) <= high


def decode(text):
    return ESCAPE.sub(lambda escape: chr(int(escape.group(1), 16)), text)


def decode_form(text):
    return decode(text.replace("+", " "))


def encode(text):
    return "".join(char if char in UNRESERVED else f"%{ord(char):02X}" for char in text)


def join_encoded(pairs):
    return "&".join(f"{encode(name)}={encode(value)}" for name, value in pairs)


def with_head(methods):
    return methods | {"HEAD"} if "GET" in methods else methods


class Piece:
    def __init__(self, kind, text):
        self.kind = kind
        self.text = text

    def fits(self, segment):
        if self.kind == LITERAL:
            return segment == self.text
        if self.kind == INT:
            return INT_VALUE.fullmatch(segment) is not None
        if self.kind == SLUG:
            return SLUG_VALUE.fullmatch(segment) is not None
        return True

    def accepts(self, value):
        if self.kind == UNTYPED:
            return value not in ("", ".", "..")
        if self.kind == WILDCARD:
            return value == "" or all(part not in ("", ".", "..") for part in value.split("/"))
        return self.fits(value)


def parse_piece(text):
    if is_segment(text):
        return Piece(LITERAL, text)
    wildcard = WILDCARD_PIECE.fullmatch(text)
    if wildcard is not None:
        return Piece(WILDCARD, wildcard.group(1))
    parameter = PARAMETER_PIECE.fullmatch(text)
    if parameter is not None:
        return Piece(PARAMETER_KINDS[parameter.group(2)], parameter.group(1))
    return None


def parse_pattern(pattern):
    if not pattern.startswith("/"):
        return None
    if pattern == "/":
        return []
    pieces = []
    for text in pattern[1:].split("/"):
        piece = parse_piece(text)
        if piece is None:
            return None
        pieces.append(piece)
    if any(piece.kind == WILDCARD for piece in pieces[:-1]):
        return None
    names = [piece.text for piece in pieces if piece.kind != LITERAL]
    if len(set(names)) != len(names):
        return None
    return pieces


class Route:
    def __init__(self, name, methods, pattern, pieces, role, number):
        self.name = name
        self.methods = methods
        self.pattern = pattern
        self.pieces = pieces
        self.role = role
        self.number = number
        self.types = None
        self.selections = 0
        self.fixed = [piece for piece in pieces if piece.kind != WILDCARD]
        self.has_wildcard = len(self.fixed) < len(pieces)

    def priority(self):
        literals = sum(piece.kind == LITERAL for piece in self.pieces)
        typed = sum(piece.kind in (INT, SLUG) for piece in self.pieces)
        return -literals, -typed, self.has_wildcard, self.number

    def matches(self, segments):
        count = len(self.fixed)
        if len(segments) < count or (len(segments) > count and not self.has_wildcard):
            return False
        return all(piece.fits(segment) for piece, segment in zip(self.fixed, segments))

    def parameters(self, segments):
        values = {}
        for piece, segment in zip(self.fixed, segments):
            if piece.kind == UNTYPED:
                values[piece.text] = decode(segment)
            elif piece.kind == INT:
                values[piece.text] = str(int(segment))
            elif piece.kind == SLUG:
                values[piece.text] = segment
        if self.has_wildcard:
            rest = segments[len(self.fixed):]
            values[self.pieces[-1].text] = "/".join(decode(segment) for segment in rest)
        return values

    def build_path(self, values):
        segments = []
        for piece in self.pieces:
            if piece.kind == LITERAL:
                segments.append(piece.text)
                continue
            value = values.get(piece.text)
            if value is None and piece.kind != WILDCARD:
                raise UrlError(f"missing parameter {piece.text}")
            if value is not None and not piece.accepts(value):
                raise UrlError(f"bad value for {piece.text}")
            if piece.kind != WILDCARD:
                segments.append(encode(value))
            elif value:
                segments.extend(encode(part) for part in value.split("/"))
        return "/" + "/".join(segments)


def parse_rule_path(path):
    if path.endswith("/*"):
        base = path[:-2]
        if base != "/" and is_canonical_path(base):
            return base, True
        return None
    if is_canonical_path(path):
        return path, False
    return None


class RedirectRule:
    def __init__(self, base, is_prefix, target_base, code):
        self.base = base
        self.is_prefix = is_prefix
        self.target_base = target_base
        self.code = code

    def destination(self, path):
        if path == self.base or (self.is_prefix and path.startswith(self.base + "/")):
            return self.target_base + path[len(self.base):]
        return None


class RateLimit:
    def __init__(self, capacity, period):
        self.capacity = capacity
        self.period = period
        self.buckets = {}

    def consume(self, client, time):
        # Levels are token counts multiplied by the period, so refills stay integral.
        full = self.capacity * self.period
        level, last = self.buckets.get(client, (full, time))
        level = min(full, level + (time - last) * self.capacity)
        if level < self.period:
            self.buckets[client] = (level, time)
            return (self.period - level + self.capacity - 1) // self.capacity
        self.buckets[client] = (level - self.period, time)
        return None


class Response:
    def __init__(self, status, body=None, headers=None, content_type="text/plain"):
        self.status = status
        self.body = body
        self.headers = headers or {}
        self.content_type = content_type

    def write(self, show_body):
        print(f"HTTP/1.1 {self.status} {REASONS[self.status]}")
        headers = dict(self.headers)
        if self.body is not None:
            headers["Content-Type"] = self.content_type
            headers["Content-Length"] = len(self.body)
        for name in HEADER_ORDER:
            if name in headers:
                print(f"{name}: {headers[name]}")
        if self.body is not None and show_body:
            print(self.body)


def redirect_response(code, location):
    return Response(code, f"redirect to {location}", {"Location": location})


def is_valid_request_line(method, target, version):
    return (
        REQUEST_METHOD.fullmatch(method) is not None
        and target.startswith("/")
        and "#" not in target
        and version == "HTTP/1.1"
    )


def has_valid_escapes(target):
    for index, char in enumerate(target):
        if char == "%":
            escape = ESCAPE.match(target, index)
            if escape is None or not 32 <= int(escape.group(1), 16) <= 126:
                return False
    return True


def normalize_escape(escape):
    char = chr(int(escape.group(1), 16))
    return char if char in UNRESERVED else escape.group(0).upper()


def normalize_path(path):
    segments = []
    for part in ESCAPE.sub(normalize_escape, path)[1:].split("/"):
        if part == "..":
            if segments:
                segments.pop()
        elif part not in ("", "."):
            segments.append(part)
    return "/" + "/".join(segments)


def parse_weight(q_value):
    if Q_VALUE.fullmatch(q_value) is None:
        return None
    whole, _, fraction = q_value.partition(".")
    return int(whole) * 1000 + int(fraction.ljust(3, "0"))


def range_specificity(media_range):
    if media_range == "*/*":
        return 1
    if MAIN_TYPE_RANGE.fullmatch(media_range):
        return 2
    if MEDIA_TYPE.fullmatch(media_range):
        return 3
    return 0


def parse_accept(value):
    elements = []
    for element in value.split(","):
        first, *parameters = [part.strip() for part in element.split(";")]
        media_range = first.lower()
        specificity = range_specificity(media_range)
        weight = 1000
        for parameter in parameters:
            name, equals, q_value = parameter.partition("=")
            if equals and name.strip().lower() == "q":
                weight = parse_weight(q_value.strip())
                break
        if specificity > 0 and weight is not None:
            elements.append((media_range, specificity, weight))
    return elements


def range_fits(media_range, media_type):
    main_type, _, subtype = media_range.partition("/")
    if subtype == "*":
        return main_type == "*" or media_type.startswith(main_type + "/")
    return media_range == media_type


def negotiate(types, accept):
    if accept is None:
        return types[0]
    elements = parse_accept(accept)
    selected, best_weight = None, 0
    for media_type in types:
        weight, best_specificity = 0, 0
        for media_range, specificity, element_weight in elements:
            if specificity > best_specificity and range_fits(media_range, media_type):
                weight, best_specificity = element_weight, specificity
        if weight > best_weight:
            selected, best_weight = media_type, weight
    return selected


def parse_query(query):
    pairs = []
    if query is None:
        return pairs
    for part in query.split("&"):
        if part:
            name, _, value = part.partition("=")
            pairs.append((decode_form(name), decode_form(value)))
    return pairs


def parse_cookies(header):
    cookies = {}
    if header is None:
        return []
    for part in header.split(";"):
        name, equals, value = part.strip().partition("=")
        if equals and name and name not in cookies:
            cookies[name] = value
    return sorted(cookies.items())


def json_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def json_object(pairs):
    members = ",".join(f"{json_string(name)}:{json_string(value)}" for name, value in pairs)
    return "{" + members + "}"


def json_body(route, params, query, cookies):
    query_items = ",".join(f"[{json_string(name)},{json_string(value)}]" for name, value in query)
    return (
        f'{{"route":{json_string(route)},"params":{json_object(params)},'
        f'"query":[{query_items}],"cookies":{json_object(cookies)}}}'
    )


def html_escape(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def html_body(route, params, query, cookies):
    entries = [("route", route)]
    entries += [(f"param {name}", value) for name, value in params]
    entries += [(f"query {name}", value) for name, value in query]
    entries += [(f"cookie {name}", value) for name, value in cookies]
    items = "".join(
        f"<dt>{html_escape(label)}</dt><dd>{html_escape(value)}</dd>" for label, value in entries
    )
    return f"<dl>{items}</dl>"


def text_body(route, params, query, cookies):
    lists = [join_encoded(pairs) or "-" for pairs in (params, query, cookies)]
    return f"route={route} params={lists[0]} query={lists[1]} cookies={lists[2]}"


def render_body(media_type, route, params, query, cookies):
    if media_type == "application/json":
        return json_body(route, params, query, cookies)
    if media_type == "text/html":
        return html_body(route, params, query, cookies)
    return text_body(route, params, query, cookies)


def etag_of(body):
    return f'"{zlib.adler32(body.encode()):08x}"'


def etag_matches(header, etag):
    candidates = (part.strip().removeprefix("W/") for part in header.split(","))
    return any(candidate in ("*", etag) for candidate in candidates)


class Router:
    def __init__(self):
        self.routes = {}
        self.ranked = []
        self.tokens = {}
        self.redirects = {}
        self.origins = set()
        self.limit = None
        self.config_errors = 0
        self.request_count = 0
        self.urlfor_ok = 0
        self.urlfor_errors = 0
        self.status_counts = Counter()
        self.clients = {}

    def configure(self, number, line):
        try:
            self.run_command(line)
        except ConfigError as error:
            self.config_errors += 1
            print(f"CONFIG ERROR {number}: {error}")

    def run_command(self, line):
        command, *arguments = line.split()
        count = len(arguments)
        commands = {
            "ROUTE": (self.add_route, count in (3, 5)),
            "TOKEN": (self.add_token, count == 2),
            "REDIRECT": (self.add_redirect, count == 3),
            "ORIGIN": (self.add_origin, count == 1),
            "LIMIT": (self.set_limit, count == 2),
            "TYPES": (self.set_types, count >= 2),
        }
        if command not in commands:
            raise ConfigError(f"unknown command {command}")
        handler, valid_count = commands[command]
        if not valid_count:
            raise ConfigError("wrong number of arguments")
        handler(*arguments)

    def add_route(self, name, methods_text, pattern, option=None, role=NO_ROLE):
        if VALID_NAME.fullmatch(name) is None:
            raise ConfigError(f"bad route name {name}")
        if name in self.routes:
            raise ConfigError(f"duplicate route {name}")
        methods = methods_text.split(",")
        if not set(methods) <= set(ROUTE_METHODS) or len(set(methods)) != len(methods):
            raise ConfigError(f"bad methods {methods_text}")
        pieces = parse_pattern(pattern)
        if pieces is None:
            raise ConfigError(f"bad pattern {pattern}")
        if option is not None:
            if option != "ROLE":
                raise ConfigError(f"unknown option {option}")
            if ROLE_NAME.fullmatch(role) is None:
                raise ConfigError(f"bad role {role}")
        self.routes[name] = Route(name, set(methods), pattern, pieces, role, len(self.routes))

    def add_token(self, value, role):
        if TOKEN_VALUE.fullmatch(value) is None:
            raise ConfigError(f"bad token {value}")
        if value in self.tokens:
            raise ConfigError(f"duplicate token {value}")
        if ROLE_NAME.fullmatch(role) is None:
            raise ConfigError(f"bad role {role}")
        self.tokens[value] = role

    def add_redirect(self, source, target, code):
        source_rule = parse_rule_path(source)
        if source_rule is None:
            raise ConfigError(f"bad path {source}")
        target_rule = parse_rule_path(target)
        if target_rule is None:
            raise ConfigError(f"bad path {target}")
        source_base, source_is_prefix = source_rule
        target_base, target_is_prefix = target_rule
        if source_is_prefix != target_is_prefix:
            raise ConfigError("wildcard mismatch")
        if code not in REDIRECT_CODES:
            raise ConfigError(f"bad redirect code {code}")
        if source in self.redirects:
            raise ConfigError(f"duplicate redirect {source}")
        self.redirects[source] = RedirectRule(source_base, source_is_prefix, target_base, int(code))

    def add_origin(self, origin):
        if ORIGIN.fullmatch(origin) is None:
            raise ConfigError(f"bad origin {origin}")
        if origin in self.origins:
            raise ConfigError(f"duplicate origin {origin}")
        self.origins.add(origin)

    def set_limit(self, capacity, period):
        if not (is_decimal_between(capacity, 1, 100) and is_decimal_between(period, 1, 3600)):
            raise ConfigError("bad limit")
        if self.limit is not None:
            raise ConfigError("duplicate limit")
        self.limit = RateLimit(int(capacity), int(period))

    def set_types(self, name, *types):
        route = self.routes.get(name)
        if route is None:
            raise ConfigError(f"unknown route {name}")
        if route.types is not None:
            raise ConfigError(f"duplicate types {name}")
        for index, media_type in enumerate(types):
            if MEDIA_TYPE.fullmatch(media_type) is None:
                raise ConfigError(f"bad media type {media_type}")
            if media_type in types[:index]:
                raise ConfigError(f"duplicate media type {media_type}")
        route.types = list(types)

    def finish_configuration(self):
        limit = f"{self.limit.capacity}/{self.limit.period}" if self.limit else "none"
        print(
            f"CONFIG routes={len(self.routes)} tokens={len(self.tokens)} "
            f"redirects={len(self.redirects)} origins={len(self.origins)} "
            f"limit={limit} errors={self.config_errors}"
        )
        for route in self.routes.values():
            if route.types is None:
                route.types = [DEFAULT_TYPE]
        self.ranked = sorted(self.routes.values(), key=Route.priority)
        for rank, route in enumerate(self.ranked, 1):
            methods = ",".join(sorted(with_head(route.methods)))
            role = "-" if route.role == NO_ROLE else route.role
            print(
                f"TABLE {rank} {route.name} {methods} {route.pattern} "
                f"role={role} types={','.join(route.types)}"
            )

    def handle_request(self, request_line, header_lines):
        self.request_count += 1
        parts = request_line.split(" ")
        if len(parts) == 3 and is_valid_request_line(*parts):
            method, target, _ = parts
            response = self.respond(method, target, header_lines)
            show_body = method != "HEAD"
        else:
            response = Response(400, "bad request: request line")
            show_body = True
        self.status_counts[response.status] += 1
        print(f"REQUEST {self.request_count}")
        response.write(show_body)

    def respond(self, method, target, header_lines):
        if not has_valid_escapes(target):
            return Response(400, "bad request: percent escape")
        headers = {}
        for number, line in enumerate(header_lines, 1):
            name, colon, value = line.partition(":")
            if not colon or HEADER_NAME.fullmatch(name) is None:
                return Response(400, f"bad request: header line {number}")
            name = name.lower()
            if name in headers:
                return Response(400, f"bad request: duplicate header {name}")
            headers[name] = value.strip()
        response = self.dispatch(method, target, headers)
        origin = headers.get("origin")
        if origin in self.origins:
            response.headers["Access-Control-Allow-Origin"] = origin
            if response.status == 204 and "access-control-request-method" in headers:
                response.headers["Access-Control-Allow-Methods"] = response.headers["Allow"]
        return response

    def dispatch(self, method, target, headers):
        if method not in KNOWN_METHODS:
            return Response(501, f"not implemented: {method}")
        if not headers.get("host"):
            return Response(400, "bad request: missing host")
        effective_method = method
        override = headers.get("x-http-method-override")
        if override is not None:
            if method != "POST" or override not in OVERRIDE_METHODS:
                return Response(400, "bad request: method override")
            effective_method = override
        client = headers.get("x-client")
        if client:
            wait = self.check_rate(client, int(headers["x-time"]))
            if wait is not None:
                return Response(429, f"too many requests: client {client}", {"Retry-After": wait})
        path, question, query = target.partition("?")
        query_suffix = question + query
        normalized = normalize_path(path)
        if normalized != path:
            return redirect_response(308, normalized + query_suffix)
        for rule in self.redirects.values():
            destination = rule.destination(path)
            if destination is not None:
                return redirect_response(rule.code, destination + query_suffix)
        return self.route_request(effective_method, path, query if question else None, headers)

    def check_rate(self, client, time):
        counts = self.clients.setdefault(client, Counter())
        wait = self.limit.consume(client, time) if self.limit else None
        if wait is None:
            counts["allowed"] += 1
        else:
            counts["limited"] += 1
        return wait

    def route_request(self, method, path, query, headers):
        segments = path[1:].split("/") if path != "/" else []
        matching = [route for route in self.ranked if route.matches(segments)]
        if not matching:
            return Response(404, f"not found: {path}")
        allowed = with_head({"OPTIONS"}.union(*(route.methods for route in matching)))
        allow = ", ".join(sorted(allowed))
        if method == "OPTIONS":
            return Response(204, headers={"Allow": allow})
        lookup = "GET" if method == "HEAD" else method
        route = next((route for route in matching if lookup in route.methods), None)
        if route is None:
            return Response(405, f"method not allowed: {method}", {"Allow": allow})
        route.selections += 1
        params = sorted(route.parameters(segments).items())
        denied = self.authorize(route.role, headers.get("authorization"))
        if denied is not None:
            return denied
        vary = {"Vary": "Accept"} if len(route.types) > 1 else {}
        media_type = negotiate(route.types, headers.get("accept"))
        if media_type is None:
            return Response(406, f"not acceptable: {', '.join(route.types)}", vary)
        cookies = parse_cookies(headers.get("cookie"))
        body = render_body(media_type, route.name, params, parse_query(query), cookies)
        etag = etag_of(body)
        if_none_match = headers.get("if-none-match")
        if if_none_match is not None and etag_matches(if_none_match, etag):
            if lookup == "GET":
                return Response(304, headers=vary | {"ETag": etag})
            return Response(412, f"precondition failed: {etag}", vary)
        return Response(200, body, vary | {"ETag": etag}, media_type)

    def authorize(self, role, authorization):
        if role == NO_ROLE:
            return None
        if authorization is None:
            challenge = 'Bearer realm="api"'
            return Response(401, "unauthorized: missing token", {"WWW-Authenticate": challenge})
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or token not in self.tokens:
            challenge = 'Bearer realm="api", error="invalid_token"'
            return Response(401, "unauthorized: invalid token", {"WWW-Authenticate": challenge})
        if self.tokens[token] not in (role, ADMIN_ROLE):
            return Response(403, f"forbidden: requires role {role}")
        return None

    def url_for(self, name, *arguments):
        try:
            url = self.build_url(name, arguments)
        except UrlError as error:
            self.urlfor_errors += 1
            print(f"URLFOR ERROR {error}")
        else:
            self.urlfor_ok += 1
            print(f"URLFOR {name} {url}")

    def build_url(self, name, arguments):
        route = self.routes.get(name)
        if route is None:
            raise UrlError(f"unknown route {name}")
        parameter_names = {piece.text for piece in route.pieces if piece.kind != LITERAL}
        values = {}
        query = []
        for argument in arguments:
            key, equals, value = argument.partition("=")
            if not equals or not key:
                raise UrlError(f"bad argument {argument}")
            if key not in parameter_names:
                query.append((key, value))
            elif key in values:
                raise UrlError(f"duplicate parameter {key}")
            else:
                values[key] = value
        url = route.build_path(values)
        if query:
            url += "?" + join_encoded(query)
        return url

    def print_summary(self):
        print(
            f"SUMMARY requests={self.request_count} "
            f"urlfor_ok={self.urlfor_ok} urlfor_error={self.urlfor_errors}"
        )
        for status in sorted(self.status_counts):
            print(f"STATUS {status} {self.status_counts[status]}")
        for route in self.routes.values():
            print(f"ROUTE {route.name} {route.selections}")
        for client in sorted(self.clients):
            counts = self.clients[client]
            print(f"CLIENT {client} allowed={counts['allowed']} limited={counts['limited']}")


def main():
    lines = sys.stdin.read().splitlines()
    router = Router()
    index = 0
    while lines[index] != "REQUESTS":
        router.configure(index + 1, lines[index])
        index += 1
    router.finish_configuration()
    index += 1
    while lines[index] != "END":
        command, space, rest = lines[index].partition(" ")
        if space and command == "URLFOR":
            router.url_for(*rest.split(" "))
            index += 1
        else:
            blank = lines.index("", index)
            router.handle_request(lines[index], lines[index + 1:blank])
            index = blank + 1
    router.print_summary()


if __name__ == "__main__":
    main()
