import re
import sys


MAX_INTEGER = 999999999
INFINITE_SCORE = MAX_INTEGER + 1
INTEGER_NOTATION = re.compile(r"0|-?[1-9][0-9]{0,8}")
TYPE_NAMES = ("string", "list", "hash", "set", "zset")
SET_OPTIONS = ("NX", "XX", "EX", "KEEPTTL", "GET")
EXPIRE_CONDITIONS = ("NX", "XX", "GT", "LT")
STAR = "*"
ANY_CHARACTER = "?"
CHARACTER_SET = "["

WRONGTYPE = "WRONGTYPE Operation against a key holding the wrong kind of value"
NOTINT = "ERR value is not an integer or out of range"
OVERFLOW = "ERR increment or decrement would overflow"
SYNTAX = "ERR syntax error"
POSITIVE = "ERR value is out of range, must be positive"
NOKEY = "ERR no such key"
NO_TRANSACTION = "ERR no transaction"
OK = "OK"
NIL = "(nil)"
INVALID_LINE = "Invalid argument(s)"

ARITY_GROUPS = (
    ((0, 0, 1), ("TIME", "DBSIZE", "FLUSH", "INFO", "BEGIN", "COMMIT", "ROLLBACK")),
    ((1, 1, 1), (
        "GET", "INCR", "DECR", "STRLEN", "LLEN", "HGETALL", "HLEN", "HKEYS", "HVALS", "SMEMBERS",
        "SCARD", "ZCARD", "TYPE", "KEYS", "TTL", "PERSIST", "TICK", "SNAPSHOT", "RESTORE",
    )),
    ((2, 2, 1), (
        "INCRBY", "DECRBY", "APPEND", "LINDEX", "HGET", "HEXISTS", "SISMEMBER", "ZSCORE", "ZRANK",
        "RENAME", "RENAMENX",
    )),
    ((3, 3, 1), ("GETRANGE", "LRANGE", "LSET", "LREM", "LTRIM", "HINCRBY", "ZINCRBY")),
    ((4, 4, 1), ("LINSERT",)),
    ((1, 2, 1), ("LPOP", "RPOP")),
    ((2, 3, 1), ("EXPIRE",)),
    ((3, 4, 1), ("ZRANGE", "ZRANGEBYSCORE")),
    ((1, None, 1), ("MGET", "SINTER", "SUNION", "SDIFF", "DEL", "EXISTS")),
    ((2, None, 1), (
        "SET", "LPUSH", "RPUSH", "HDEL", "SADD", "SREM", "ZREM", "SINTERSTORE", "SUNIONSTORE",
        "SDIFFSTORE",
    )),
    ((2, None, 2), ("MSET",)),
    ((3, None, 2), ("HSET", "ZADD")),
)
ARITIES = {name: arity for arity, names in ARITY_GROUPS for name in names}


class CommandError(Exception):
    pass


def arity_matches(arity, count):
    minimum, maximum, step = arity
    if count < minimum or (maximum is not None and count > maximum):
        return False
    return (count - minimum) % step == 0


def read_quoted(line, position):
    content = []
    while position < len(line):
        character = line[position]
        if character == '"':
            return "".join(content), position + 1
        if character == "\\":
            if position + 1 == len(line) or line[position + 1] not in ('"', "\\"):
                return None
            position += 1
            character = line[position]
        content.append(character)
        position += 1
    return None


def split_line(line):
    arguments = []
    position = 0
    while position < len(line):
        if line[position] == " ":
            position += 1
        elif line[position] == '"':
            quoted = read_quoted(line, position + 1)
            if quoted is None:
                return None
            argument, position = quoted
            if position < len(line) and line[position] != " ":
                return None
            arguments.append(argument)
        else:
            end = line.find(" ", position)
            if end < 0:
                end = len(line)
            arguments.append(line[position:end])
            position = end
    return arguments


def is_integer(text):
    return INTEGER_NOTATION.fullmatch(text) is not None


def integer_argument(text):
    if not is_integer(text):
        raise CommandError(NOTINT)
    return int(text)


def checked_sum(value, delta):
    result = value + delta
    if not -MAX_INTEGER <= result <= MAX_INTEGER:
        raise CommandError(OVERFLOW)
    return result


def normalize_range(length, start, stop):
    if start < 0:
        start += length
    if stop < 0:
        stop += length
    start = max(start, 0)
    stop = min(stop, length - 1)
    if start > stop:
        return 0, 0
    return start, stop + 1


def integer_reply(value):
    return f"(integer) {value}"


def string_reply(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def array_reply(items):
    if not items:
        return "(empty array)"
    width = len(str(len(items)))
    lines = []
    for number, item in enumerate(items, 1):
        text = NIL if item is None else string_reply(item)
        lines.append(f"{number:>{width}}) {text}")
    return "\n".join(lines)


def error_reply(message):
    return "(error) " + message


class PatternPart:
    def __init__(self, kind, characters=frozenset(), negated=False):
        self.kind = kind
        self.characters = characters
        self.negated = negated

    def accepts(self, character):
        if self.kind == ANY_CHARACTER:
            return True
        return (character in self.characters) != self.negated


def character_set(body):
    characters = set()
    index = 0
    while index < len(body):
        if index + 2 < len(body) and body[index + 1] == "-":
            low, high = sorted((ord(body[index]), ord(body[index + 2])))
            for code in range(low, high + 1):
                characters.add(chr(code))
            index += 3
        else:
            characters.add(body[index])
            index += 1
    return characters


def parse_pattern(pattern):
    parts = []
    index = 0
    while index < len(pattern):
        character = pattern[index]
        if character == "\\":
            if index + 1 == len(pattern):
                return None
            parts.append(PatternPart(CHARACTER_SET, {pattern[index + 1]}))
            index += 2
        elif character == "[":
            close = pattern.find("]", index + 1)
            if close < 0:
                return None
            body = pattern[index + 1:close]
            negated = body.startswith("^")
            if negated:
                body = body[1:]
            if not body:
                return None
            parts.append(PatternPart(CHARACTER_SET, character_set(body), negated))
            index = close + 1
        elif character in (STAR, ANY_CHARACTER):
            parts.append(PatternPart(character))
            index += 1
        else:
            parts.append(PatternPart(CHARACTER_SET, {character}))
            index += 1
    return parts


def pattern_matches(parts, text):
    part_index = 0
    position = 0
    star_index = -1
    star_position = 0
    while position < len(text):
        if part_index < len(parts) and parts[part_index].kind == STAR:
            star_index = part_index
            star_position = position
            part_index += 1
        elif part_index < len(parts) and parts[part_index].accepts(text[position]):
            part_index += 1
            position += 1
        elif star_index >= 0:
            star_position += 1
            position = star_position
            part_index = star_index + 1
        else:
            return False
    while part_index < len(parts) and parts[part_index].kind == STAR:
        part_index += 1
    return part_index == len(parts)


def score_bound(text):
    if text == "-inf":
        return -INFINITE_SCORE, True
    if text == "+inf":
        return INFINITE_SCORE, True
    inclusive = not text.startswith("(")
    number = text if inclusive else text[1:]
    if not is_integer(number):
        raise CommandError("ERR min or max is not a float")
    return int(number), inclusive


def above_minimum(score, bound):
    value, inclusive = bound
    return score >= value if inclusive else score > value


def below_maximum(score, bound):
    value, inclusive = bound
    return score <= value if inclusive else score < value


def parse_set_options(options):
    seen = set()
    seconds = None
    index = 0
    while index < len(options):
        option = options[index].upper()
        if option not in SET_OPTIONS or option in seen:
            raise CommandError(SYNTAX)
        seen.add(option)
        if option == "EX":
            if index + 1 == len(options):
                raise CommandError(SYNTAX)
            index += 1
            seconds = options[index]
        index += 1
    if {"NX", "XX"} <= seen or {"EX", "KEEPTTL"} <= seen:
        raise CommandError(SYNTAX)
    return seen, seconds


def with_scores_requested(arguments):
    if len(arguments) == 4 and arguments[3].upper() != "WITHSCORES":
        raise CommandError(SYNTAX)
    return len(arguments) == 4


def sorted_members(scores):
    return sorted(scores, key=lambda member: (scores[member], member))


def scored_reply(members, scores, with_scores):
    items = []
    for member in members:
        items.append(member)
        if with_scores:
            items.append(str(scores[member]))
    return array_reply(items)


def combine_sets(operation, sets):
    result = set(sets[0])
    for members in sets[1:]:
        if operation == "SINTER":
            result &= members
        elif operation == "SUNION":
            result |= members
        else:
            result -= members
    return result


def expire_blocked(condition, expiry, deadline):
    if condition == "NX":
        return expiry is not None
    if condition == "XX":
        return expiry is None
    if condition == "GT":
        return expiry is None or deadline <= expiry
    return expiry is not None and deadline >= expiry


def empty_value(kind):
    if kind == "string":
        return ""
    if kind == "list":
        return []
    if kind == "set":
        return set()
    return {}


class Entry:
    def __init__(self, kind, value, expiry=None):
        self.kind = kind
        self.value = value
        self.expiry = expiry

    def copy(self):
        value = self.value if self.kind == "string" else self.value.copy()
        return Entry(self.kind, value, self.expiry)


def copy_database(database):
    return {key: entry.copy() for key, entry in database.items()}


class KeyValueStore:
    def __init__(self):
        self.database = {}
        self.now = 0
        self.saved = []
        self.snapshots = {}
        self.handlers = {
            "SET": self.set_value,
            "GET": self.get_value,
            "MSET": self.set_many,
            "MGET": self.get_many,
            "INCR": lambda arguments: self.increment(arguments, 1),
            "DECR": lambda arguments: self.increment(arguments, -1),
            "INCRBY": lambda arguments: self.increment(arguments, 1),
            "DECRBY": lambda arguments: self.increment(arguments, -1),
            "APPEND": self.append,
            "STRLEN": self.string_length,
            "GETRANGE": self.get_range,
            "LPUSH": lambda arguments: self.push(arguments, True),
            "RPUSH": lambda arguments: self.push(arguments, False),
            "LPOP": lambda arguments: self.pop(arguments, True),
            "RPOP": lambda arguments: self.pop(arguments, False),
            "LRANGE": self.list_range,
            "LLEN": self.list_length,
            "LINDEX": self.list_index,
            "LSET": self.list_set,
            "LREM": self.list_remove,
            "LTRIM": self.list_trim,
            "LINSERT": self.list_insert,
            "HSET": self.hash_set,
            "HGET": self.hash_get,
            "HDEL": self.hash_delete,
            "HGETALL": self.hash_get_all,
            "HLEN": self.hash_length,
            "HEXISTS": self.hash_exists,
            "HKEYS": self.hash_keys,
            "HVALS": self.hash_values,
            "HINCRBY": self.hash_increment,
            "SADD": self.set_add,
            "SREM": self.set_remove,
            "SISMEMBER": self.set_is_member,
            "SMEMBERS": self.set_members,
            "SCARD": self.set_cardinality,
            "SINTER": lambda arguments: self.set_operation(arguments, "SINTER"),
            "SUNION": lambda arguments: self.set_operation(arguments, "SUNION"),
            "SDIFF": lambda arguments: self.set_operation(arguments, "SDIFF"),
            "SINTERSTORE": lambda arguments: self.store_set_operation(arguments, "SINTER"),
            "SUNIONSTORE": lambda arguments: self.store_set_operation(arguments, "SUNION"),
            "SDIFFSTORE": lambda arguments: self.store_set_operation(arguments, "SDIFF"),
            "ZADD": self.zset_add,
            "ZSCORE": self.zset_score,
            "ZINCRBY": self.zset_increment,
            "ZREM": self.zset_remove,
            "ZCARD": self.zset_cardinality,
            "ZRANK": self.zset_rank,
            "ZRANGE": self.zset_range,
            "ZRANGEBYSCORE": self.zset_range_by_score,
            "DEL": self.delete,
            "EXISTS": self.exists,
            "TYPE": self.key_type,
            "RENAME": self.rename,
            "RENAMENX": self.rename_if_absent,
            "KEYS": self.keys,
            "EXPIRE": self.expire,
            "TTL": self.time_to_live,
            "PERSIST": self.persist,
            "TICK": self.tick,
            "TIME": self.time,
            "DBSIZE": self.database_size,
            "FLUSH": self.flush,
            "INFO": self.info,
            "BEGIN": self.begin,
            "COMMIT": self.commit,
            "ROLLBACK": self.rollback,
            "SNAPSHOT": self.snapshot,
            "RESTORE": self.restore,
        }

    def execute(self, line):
        arguments = split_line(line)
        if arguments is None:
            return INVALID_LINE
        name = arguments[0].upper()
        if name not in ARITIES:
            return error_reply(f"ERR unknown command '{arguments[0]}'")
        if not arity_matches(ARITIES[name], len(arguments) - 1):
            return error_reply(f"ERR wrong number of arguments for '{name.lower()}' command")
        try:
            return self.handlers[name](arguments[1:])
        except CommandError as error:
            return error_reply(str(error))

    def lookup(self, key, kind):
        entry = self.database.get(key)
        if entry is not None and entry.kind != kind:
            raise CommandError(WRONGTYPE)
        return entry

    def contents(self, key, kind):
        entry = self.lookup(key, kind)
        return empty_value(kind) if entry is None else entry.value

    def create(self, key, kind):
        entry = Entry(kind, empty_value(kind))
        self.database[key] = entry
        return entry

    def fetch_or_create(self, key, kind):
        entry = self.lookup(key, kind)
        return self.create(key, kind) if entry is None else entry

    def discard_if_empty(self, key):
        if not self.database[key].value:
            del self.database[key]

    def remove_expired(self):
        expired = [
            key for key, entry in self.database.items()
            if entry.expiry is not None and entry.expiry <= self.now
        ]
        for key in expired:
            del self.database[key]
        return len(expired)

    def set_value(self, arguments):
        key, value = arguments[0], arguments[1]
        options, seconds_text = parse_set_options(arguments[2:])
        expiry = None
        if "EX" in options:
            seconds = integer_argument(seconds_text)
            if seconds <= 0:
                raise CommandError("ERR invalid expire time in 'set' command")
            expiry = self.now + seconds
        if "GET" in options:
            previous = self.lookup(key, "string")
        else:
            previous = self.database.get(key)
        exists = previous is not None
        skipped = ("NX" in options and exists) or ("XX" in options and not exists)
        if not skipped:
            if "KEEPTTL" in options and exists:
                expiry = previous.expiry
            self.database[key] = Entry("string", value, expiry)
        if "GET" in options:
            return string_reply(previous.value) if exists else NIL
        return NIL if skipped else OK

    def get_value(self, arguments):
        entry = self.lookup(arguments[0], "string")
        return NIL if entry is None else string_reply(entry.value)

    def set_many(self, arguments):
        for index in range(0, len(arguments), 2):
            self.database[arguments[index]] = Entry("string", arguments[index + 1])
        return OK

    def get_many(self, arguments):
        values = []
        for key in arguments:
            entry = self.database.get(key)
            values.append(entry.value if entry is not None and entry.kind == "string" else None)
        return array_reply(values)

    def increment(self, arguments, sign):
        key = arguments[0]
        delta = sign
        if len(arguments) == 2:
            delta = sign * integer_argument(arguments[1])
        entry = self.lookup(key, "string")
        current = 0
        if entry is not None:
            if not is_integer(entry.value):
                raise CommandError(NOTINT)
            current = int(entry.value)
        result = checked_sum(current, delta)
        if entry is None:
            entry = self.create(key, "string")
        entry.value = str(result)
        return integer_reply(result)

    def append(self, arguments):
        key, value = arguments
        entry = self.fetch_or_create(key, "string")
        entry.value += value
        return integer_reply(len(entry.value))

    def string_length(self, arguments):
        return integer_reply(len(self.contents(arguments[0], "string")))

    def get_range(self, arguments):
        key, start_text, end_text = arguments
        start = integer_argument(start_text)
        end = integer_argument(end_text)
        text = self.contents(key, "string")
        begin, finish = normalize_range(len(text), start, end)
        return string_reply(text[begin:finish])

    def push(self, arguments, at_head):
        entry = self.fetch_or_create(arguments[0], "list")
        for element in arguments[1:]:
            if at_head:
                entry.value.insert(0, element)
            else:
                entry.value.append(element)
        return integer_reply(len(entry.value))

    def pop(self, arguments, from_head):
        key = arguments[0]
        count = None
        if len(arguments) == 2:
            if not is_integer(arguments[1]) or int(arguments[1]) < 0:
                raise CommandError(POSITIVE)
            count = int(arguments[1])
        entry = self.lookup(key, "list")
        if entry is None:
            return NIL
        index = 0 if from_head else -1
        if count is None:
            element = entry.value.pop(index)
            self.discard_if_empty(key)
            return string_reply(element)
        removed = []
        while len(removed) < count and entry.value:
            removed.append(entry.value.pop(index))
        self.discard_if_empty(key)
        return array_reply(removed)

    def list_range(self, arguments):
        key, start_text, stop_text = arguments
        start = integer_argument(start_text)
        stop = integer_argument(stop_text)
        elements = self.contents(key, "list")
        begin, end = normalize_range(len(elements), start, stop)
        return array_reply(elements[begin:end])

    def list_length(self, arguments):
        return integer_reply(len(self.contents(arguments[0], "list")))

    def list_index(self, arguments):
        index = integer_argument(arguments[1])
        elements = self.contents(arguments[0], "list")
        if index < 0:
            index += len(elements)
        if 0 <= index < len(elements):
            return string_reply(elements[index])
        return NIL

    def list_set(self, arguments):
        key, index_text, element = arguments
        index = integer_argument(index_text)
        entry = self.lookup(key, "list")
        if entry is None:
            raise CommandError(NOKEY)
        if index < 0:
            index += len(entry.value)
        if not 0 <= index < len(entry.value):
            raise CommandError("ERR index out of range")
        entry.value[index] = element
        return OK

    def list_remove(self, arguments):
        key, count_text, element = arguments
        count = integer_argument(count_text)
        entry = self.lookup(key, "list")
        if entry is None:
            return integer_reply(0)
        scanned = entry.value if count >= 0 else reversed(entry.value)
        kept = []
        removed = 0
        for value in scanned:
            if value == element and (count == 0 or removed < abs(count)):
                removed += 1
            else:
                kept.append(value)
        if count < 0:
            kept.reverse()
        entry.value = kept
        self.discard_if_empty(key)
        return integer_reply(removed)

    def list_trim(self, arguments):
        key, start_text, stop_text = arguments
        start = integer_argument(start_text)
        stop = integer_argument(stop_text)
        entry = self.lookup(key, "list")
        if entry is not None:
            begin, end = normalize_range(len(entry.value), start, stop)
            entry.value = entry.value[begin:end]
            self.discard_if_empty(key)
        return OK

    def list_insert(self, arguments):
        key, where, pivot, element = arguments
        position = where.upper()
        if position not in ("BEFORE", "AFTER"):
            raise CommandError(SYNTAX)
        entry = self.lookup(key, "list")
        if entry is None:
            return integer_reply(0)
        if pivot not in entry.value:
            return integer_reply(-1)
        index = entry.value.index(pivot)
        entry.value.insert(index if position == "BEFORE" else index + 1, element)
        return integer_reply(len(entry.value))

    def hash_set(self, arguments):
        entry = self.fetch_or_create(arguments[0], "hash")
        added = 0
        for index in range(1, len(arguments), 2):
            field = arguments[index]
            if field not in entry.value:
                added += 1
            entry.value[field] = arguments[index + 1]
        return integer_reply(added)

    def hash_get(self, arguments):
        key, field = arguments
        fields = self.contents(key, "hash")
        return string_reply(fields[field]) if field in fields else NIL

    def hash_delete(self, arguments):
        key = arguments[0]
        entry = self.lookup(key, "hash")
        if entry is None:
            return integer_reply(0)
        removed = 0
        for field in arguments[1:]:
            if field in entry.value:
                del entry.value[field]
                removed += 1
        self.discard_if_empty(key)
        return integer_reply(removed)

    def hash_get_all(self, arguments):
        fields = self.contents(arguments[0], "hash")
        items = []
        for field in sorted(fields):
            items.append(field)
            items.append(fields[field])
        return array_reply(items)

    def hash_length(self, arguments):
        return integer_reply(len(self.contents(arguments[0], "hash")))

    def hash_exists(self, arguments):
        key, field = arguments
        return integer_reply(1 if field in self.contents(key, "hash") else 0)

    def hash_keys(self, arguments):
        return array_reply(sorted(self.contents(arguments[0], "hash")))

    def hash_values(self, arguments):
        fields = self.contents(arguments[0], "hash")
        return array_reply([fields[field] for field in sorted(fields)])

    def hash_increment(self, arguments):
        key, field, increment_text = arguments
        increment = integer_argument(increment_text)
        entry = self.lookup(key, "hash")
        current = 0
        if entry is not None and field in entry.value:
            if not is_integer(entry.value[field]):
                raise CommandError("ERR hash value is not an integer")
            current = int(entry.value[field])
        result = checked_sum(current, increment)
        if entry is None:
            entry = self.create(key, "hash")
        entry.value[field] = str(result)
        return integer_reply(result)

    def set_add(self, arguments):
        entry = self.fetch_or_create(arguments[0], "set")
        added = 0
        for member in arguments[1:]:
            if member not in entry.value:
                entry.value.add(member)
                added += 1
        return integer_reply(added)

    def set_remove(self, arguments):
        key = arguments[0]
        entry = self.lookup(key, "set")
        if entry is None:
            return integer_reply(0)
        removed = 0
        for member in arguments[1:]:
            if member in entry.value:
                entry.value.remove(member)
                removed += 1
        self.discard_if_empty(key)
        return integer_reply(removed)

    def set_is_member(self, arguments):
        key, member = arguments
        return integer_reply(1 if member in self.contents(key, "set") else 0)

    def set_members(self, arguments):
        return array_reply(sorted(self.contents(arguments[0], "set")))

    def set_cardinality(self, arguments):
        return integer_reply(len(self.contents(arguments[0], "set")))

    def member_sets(self, keys):
        return [self.contents(key, "set") for key in keys]

    def set_operation(self, arguments, operation):
        return array_reply(sorted(combine_sets(operation, self.member_sets(arguments))))

    def store_set_operation(self, arguments, operation):
        destination = arguments[0]
        members = combine_sets(operation, self.member_sets(arguments[1:]))
        if members:
            self.database[destination] = Entry("set", members)
        elif destination in self.database:
            del self.database[destination]
        return integer_reply(len(members))

    def zset_add(self, arguments):
        scores = [integer_argument(arguments[index]) for index in range(1, len(arguments), 2)]
        entry = self.fetch_or_create(arguments[0], "zset")
        added = 0
        for score, member in zip(scores, arguments[2::2]):
            if member not in entry.value:
                added += 1
            entry.value[member] = score
        return integer_reply(added)

    def zset_score(self, arguments):
        key, member = arguments
        scores = self.contents(key, "zset")
        return string_reply(str(scores[member])) if member in scores else NIL

    def zset_increment(self, arguments):
        key, increment_text, member = arguments
        increment = integer_argument(increment_text)
        entry = self.lookup(key, "zset")
        current = 0
        if entry is not None and member in entry.value:
            current = entry.value[member]
        result = checked_sum(current, increment)
        if entry is None:
            entry = self.create(key, "zset")
        entry.value[member] = result
        return string_reply(str(result))

    def zset_remove(self, arguments):
        key = arguments[0]
        entry = self.lookup(key, "zset")
        if entry is None:
            return integer_reply(0)
        removed = 0
        for member in arguments[1:]:
            if member in entry.value:
                del entry.value[member]
                removed += 1
        self.discard_if_empty(key)
        return integer_reply(removed)

    def zset_cardinality(self, arguments):
        return integer_reply(len(self.contents(arguments[0], "zset")))

    def zset_rank(self, arguments):
        key, member = arguments
        scores = self.contents(key, "zset")
        if member not in scores:
            return NIL
        return integer_reply(sorted_members(scores).index(member))

    def zset_range(self, arguments):
        with_scores = with_scores_requested(arguments)
        start = integer_argument(arguments[1])
        stop = integer_argument(arguments[2])
        scores = self.contents(arguments[0], "zset")
        members = sorted_members(scores)
        begin, end = normalize_range(len(members), start, stop)
        return scored_reply(members[begin:end], scores, with_scores)

    def zset_range_by_score(self, arguments):
        with_scores = with_scores_requested(arguments)
        minimum = score_bound(arguments[1])
        maximum = score_bound(arguments[2])
        scores = self.contents(arguments[0], "zset")
        members = [
            member for member in sorted_members(scores)
            if above_minimum(scores[member], minimum) and below_maximum(scores[member], maximum)
        ]
        return scored_reply(members, scores, with_scores)

    def delete(self, arguments):
        deleted = 0
        for key in arguments:
            if key in self.database:
                del self.database[key]
                deleted += 1
        return integer_reply(deleted)

    def exists(self, arguments):
        return integer_reply(sum(1 for key in arguments if key in self.database))

    def key_type(self, arguments):
        entry = self.database.get(arguments[0])
        return "none" if entry is None else entry.kind

    def rename(self, arguments):
        key, new_key = arguments
        if key not in self.database:
            raise CommandError(NOKEY)
        if key != new_key:
            self.database[new_key] = self.database.pop(key)
        return OK

    def rename_if_absent(self, arguments):
        key, new_key = arguments
        if key not in self.database:
            raise CommandError(NOKEY)
        if new_key in self.database:
            return integer_reply(0)
        self.database[new_key] = self.database.pop(key)
        return integer_reply(1)

    def keys(self, arguments):
        parts = parse_pattern(arguments[0])
        if parts is None:
            raise CommandError("ERR invalid pattern")
        return array_reply(sorted(key for key in self.database if pattern_matches(parts, key)))

    def expire(self, arguments):
        key = arguments[0]
        condition = None
        if len(arguments) == 3:
            condition = arguments[2].upper()
            if condition not in EXPIRE_CONDITIONS:
                raise CommandError(f"ERR Unsupported option {arguments[2]}")
        seconds = integer_argument(arguments[1])
        entry = self.database.get(key)
        if entry is None:
            return integer_reply(0)
        deadline = self.now + seconds
        if condition is not None and expire_blocked(condition, entry.expiry, deadline):
            return integer_reply(0)
        if seconds <= 0:
            del self.database[key]
        else:
            entry.expiry = deadline
        return integer_reply(1)

    def time_to_live(self, arguments):
        entry = self.database.get(arguments[0])
        if entry is None:
            return integer_reply(-2)
        if entry.expiry is None:
            return integer_reply(-1)
        return integer_reply(entry.expiry - self.now)

    def persist(self, arguments):
        entry = self.database.get(arguments[0])
        if entry is None or entry.expiry is None:
            return integer_reply(0)
        entry.expiry = None
        return integer_reply(1)

    def tick(self, arguments):
        ticks = integer_argument(arguments[0])
        if ticks <= 0:
            raise CommandError(POSITIVE)
        self.now += ticks
        return integer_reply(self.remove_expired())

    def time(self, arguments):
        return integer_reply(self.now)

    def database_size(self, arguments):
        return integer_reply(len(self.database))

    def flush(self, arguments):
        self.database = {}
        return OK

    def info(self, arguments):
        counts = {kind: 0 for kind in TYPE_NAMES}
        expires = 0
        for entry in self.database.values():
            counts[entry.kind] += 1
            if entry.expiry is not None:
                expires += 1
        fields = [f"keys={len(self.database)}", f"expires={expires}"]
        fields.extend(f"{kind}={counts[kind]}" for kind in TYPE_NAMES)
        fields.append(f"time={self.now}")
        fields.append(f"depth={len(self.saved)}")
        fields.append(f"snapshots={len(self.snapshots)}")
        return ",".join(fields)

    def begin(self, arguments):
        self.saved.append(copy_database(self.database))
        return OK

    def commit(self, arguments):
        if not self.saved:
            raise CommandError(NO_TRANSACTION)
        self.saved.pop()
        return OK

    def rollback(self, arguments):
        if not self.saved:
            raise CommandError(NO_TRANSACTION)
        self.database = self.saved.pop()
        self.remove_expired()
        return OK

    def snapshot(self, arguments):
        self.snapshots[arguments[0]] = copy_database(self.database)
        return OK

    def restore(self, arguments):
        name = arguments[0]
        if name not in self.snapshots:
            raise CommandError("ERR no such snapshot")
        self.database = copy_database(self.snapshots[name])
        self.remove_expired()
        return OK


def main():
    store = KeyValueStore()
    count = int(sys.stdin.readline())
    for _ in range(count):
        print(store.execute(sys.stdin.readline().rstrip("\n")))


if __name__ == "__main__":
    main()
