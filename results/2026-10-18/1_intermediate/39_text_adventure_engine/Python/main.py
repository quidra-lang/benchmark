import sys


DIRECTIONS = ("north", "south", "east", "west", "up", "down")
OPPOSITE = {
    "north": "south", "south": "north", "east": "west",
    "west": "east", "up": "down", "down": "up",
}
DIRECTION_WORDS = {
    "north": "north", "south": "south", "east": "east",
    "west": "west", "up": "up", "down": "down",
    "n": "north", "s": "south", "e": "east",
    "w": "west", "u": "up", "d": "down",
}
VERB_WORDS = {
    "go": ("go", "walk", "run"),
    "look": ("look", "l"),
    "examine": ("examine", "x", "inspect", "read"),
    "take": ("take", "get", "grab"),
    "drop": ("drop", "discard"),
    "put": ("put", "insert", "place"),
    "inventory": ("inventory", "inv", "i"),
    "open": ("open",),
    "close": ("close", "shut"),
    "unlock": ("unlock",),
    "lock": ("lock",),
    "use": ("use", "apply"),
    "light": ("light", "ignite"),
    "extinguish": ("extinguish", "douse", "snuff"),
    "wait": ("wait", "z"),
    "score": ("score",),
    "save": ("save",),
    "restore": ("restore", "load"),
    "verbose": ("verbose",),
    "brief": ("brief",),
}
VERBS = {word: verb for verb, words in VERB_WORDS.items() for word in words}
ARTICLES = ("the", "a", "an")
REPEAT_WORDS = ("again", "g")
BARE_VERBS = ("look", "inventory", "wait", "score", "save", "restore", "verbose", "brief")
ACTIONS = (
    "go", "take", "drop", "put", "open", "close",
    "unlock", "lock", "use", "light", "extinguish", "wait",
)
PREPOSITIONS = {
    "put": ("in", "into"),
    "use": ("on", "with"),
    "unlock": ("with",),
    "lock": ("with",),
    "take": ("from",),
}
SPLIT_REQUIRED = ("put", "use")
CONDITIONS = ("IF", "UNLESS")
UNCLEAR = "I don't understand that."
UNSEEN = "You can't see any such thing."
PLAYER = ("player", "")
NOWHERE = ("nowhere", "")


def on_floor(room):
    return "floor", room


def inside(item_id):
    return "inside", item_id


def command_words(line):
    return [word for word in line.lower().split() if word not in ARTICLES]


class CommandFailed(Exception):
    def __init__(self, message=None):
        super().__init__(message)
        self.message = message


class Command:
    def __init__(self, verb, first=None, second=None, direction=None):
        self.verb = verb
        self.first = first
        self.second = second
        self.direction = direction

    def is_all(self):
        return self.first == ["all"]


def split_phrases(verb, words):
    for index, word in enumerate(words):
        if word in PREPOSITIONS[verb]:
            first, second = words[:index], words[index + 1:]
            if not first or not second:
                raise CommandFailed(UNCLEAR)
            return first, second
    if verb in SPLIT_REQUIRED:
        raise CommandFailed(UNCLEAR)
    return words, None


def parse_command(words, game_over):
    if not words:
        raise CommandFailed("I beg your pardon?")
    if words[0] in DIRECTION_WORDS:
        words = ["go"] + words
    verb = VERBS.get(words[0])
    if verb is None:
        raise CommandFailed(f"I don't know the verb \"{words[0]}\".")
    rest = words[1:]
    if game_over and verb != "restore":
        raise CommandFailed("The game is over.")
    if verb == "look" and rest:
        if rest[0] != "at":
            raise CommandFailed(UNCLEAR)
        verb = "examine"
        rest = rest[1:]
    if verb in BARE_VERBS:
        if rest:
            raise CommandFailed(UNCLEAR)
        return Command(verb)
    if not rest:
        if verb == "go":
            raise CommandFailed("Which way do you want to go?")
        raise CommandFailed(f"What do you want to {verb}?")
    if verb == "go":
        if len(rest) != 1 or rest[0] not in DIRECTION_WORDS:
            raise CommandFailed(UNCLEAR)
        return Command(verb, direction=DIRECTION_WORDS[rest[0]])
    if verb in PREPOSITIONS:
        first, second = split_phrases(verb, rest)
        return Command(verb, first, second)
    return Command(verb, rest)


class Room:
    def __init__(self, name, dark):
        self.name = name
        self.dark = dark
        self.description = []


class Exit:
    def __init__(self, destination, key, locked):
        self.destination = destination
        self.key = key
        self.locked = locked

    def copy(self):
        return Exit(self.destination, self.key, self.locked)


class Item:
    def __init__(self, item_id, weight):
        self.id = item_id
        self.weight = weight
        self.name = ""
        self.words = []
        self.nouns = [item_id]
        self.details = []
        self.points = None
        self.light = False
        self.capacity = None
        self.key = None
        self.fixed = False

    def is_container(self):
        return self.capacity is not None

    def is_treasure(self):
        return self.points is not None

    def matches(self, phrase):
        if phrase[-1] not in self.nouns:
            return False
        return all(word in self.words for word in phrase[:-1])


class Rule:
    def __init__(self, condition, flag, effect, arguments):
        self.condition = condition
        self.flag = flag
        self.effect = effect
        self.arguments = arguments

    def applies(self, flags):
        if self.condition == "IF":
            return self.flag in flags
        if self.condition == "UNLESS":
            return self.flag not in flags
        return True


def parse_rule(words):
    condition = None
    flag = None
    if words[0] in CONDITIONS:
        condition, flag = words[0], words[1]
        words = words[2:]
    effect = words[0]
    if effect == "MESSAGE":
        return Rule(condition, flag, effect, [" ".join(words[1:])])
    return Rule(condition, flag, effect, words[1:])


class State:
    def __init__(self):
        self.room = None
        self.places = {}
        self.containers = {}
        self.exits = {}
        self.lit = {}
        self.fuel = {}
        self.flags = set()
        self.bonus = 0
        self.moves = 0
        self.visited = set()
        self.darkness = 0
        self.status = "none"

    def copy(self):
        state = State()
        state.room = self.room
        state.places = dict(self.places)
        state.containers = dict(self.containers)
        state.exits = {
            room: {direction: passage.copy() for direction, passage in exits.items()}
            for room, exits in self.exits.items()
        }
        state.lit = dict(self.lit)
        state.fuel = dict(self.fuel)
        state.flags = set(self.flags)
        state.bonus = self.bonus
        state.moves = self.moves
        state.visited = set(self.visited)
        state.darkness = self.darkness
        state.status = self.status
        return state


class World:
    def __init__(self):
        self.rooms = {}
        self.items = {}
        self.uses = {}
        self.entries = {}
        self.trophy = None
        self.start = None
        self.max_weight = 0
        self.initial = State()
        self.order = []
        self.treasures = []
        self.vocabulary = set()
        self.handlers = {
            "ROOM": self.define_room,
            "DESC": self.define_description,
            "EXIT": self.define_exit,
            "ITEM": self.define_item,
            "INSIDE": self.define_inside,
            "ALIAS": self.define_alias,
            "DETAIL": self.define_detail,
            "RULE": self.define_use_rule,
            "ENTER": self.define_enter_rule,
            "TROPHY": self.define_trophy,
            "START": self.define_start,
            "MAXWEIGHT": self.define_max_weight,
        }

    def define(self, line):
        words = line.split(" ")
        self.handlers[words[0]](words)

    def define_room(self, words):
        dark = words[2] == "DARK"
        name = " ".join(words[3:] if dark else words[2:])
        self.rooms[words[1]] = Room(name, dark)

    def define_description(self, words):
        self.rooms[words[1]].description.append(" ".join(words[2:]))

    def define_exit(self, words):
        room, direction, destination = words[1], words[2], words[3]
        key = words[5] if len(words) > 4 else None
        exits = self.initial.exits.setdefault(room, {})
        exits[direction] = Exit(destination, key, key is not None)

    def define_item(self, words):
        state = self.initial
        item = Item(words[1], int(words[3]))
        self.items[item.id] = item
        if words[2] == "PLAYER":
            state.places[item.id] = PLAYER
        elif words[2] == "NOWHERE":
            state.places[item.id] = NOWHERE
        else:
            state.places[item.id] = on_floor(words[2])
        position = 4
        if words[position] == "TREASURE":
            item.points = int(words[position + 1])
            position += 2
        if words[position] == "LIGHT":
            item.light = True
            state.lit[item.id] = False
            state.fuel[item.id] = int(words[position + 1])
            position += 2
        if words[position] == "CONTAINER":
            item.capacity = int(words[position + 1])
            position += 2
            status = "open"
            if words[position] == "CLOSED":
                status = "closed"
                position += 1
            if words[position] == "LOCKED":
                item.key = words[position + 1]
                status = "locked"
                position += 2
            state.containers[item.id] = status
        if words[position] == "FIXED":
            item.fixed = True
            position += 1
        item.words = words[position:]
        item.name = " ".join(item.words)

    def define_inside(self, words):
        self.initial.places[words[1]] = inside(words[2])

    def define_alias(self, words):
        self.items[words[1]].nouns.append(words[2])

    def define_detail(self, words):
        self.items[words[1]].details.append(" ".join(words[2:]))

    def define_use_rule(self, words):
        self.uses.setdefault((words[1], words[2]), []).append(parse_rule(words[3:]))

    def define_enter_rule(self, words):
        self.entries.setdefault(words[1], []).append(parse_rule(words[2:]))

    def define_trophy(self, words):
        self.trophy = words[1]

    def define_start(self, words):
        self.start = words[1]

    def define_max_weight(self, words):
        self.max_weight = int(words[1])

    def finish(self):
        self.order = [self.items[item_id] for item_id in sorted(self.items)]
        self.treasures = [item for item in self.order if item.is_treasure()]
        for item in self.order:
            self.vocabulary.update(item.nouns)
            self.vocabulary.update(item.words)
        for room in self.rooms:
            self.initial.exits.setdefault(room, {})
        self.initial.room = self.start
        self.initial.visited.add(self.start)


class Game:
    def __init__(self, world):
        self.world = world
        self.state = world.initial
        self.it = None
        self.previous = None
        self.verbose = False
        self.saved = None
        self.baseline = False
        self.output = []
        self.handlers = {
            "go": self.go,
            "look": self.look,
            "examine": self.examine,
            "take": self.take,
            "drop": self.drop,
            "put": self.put,
            "inventory": self.inventory,
            "open": self.open_container,
            "close": self.close_container,
            "unlock": self.unlock,
            "lock": self.lock,
            "use": self.use,
            "light": self.light,
            "extinguish": self.extinguish,
            "wait": self.wait,
            "score": self.show_score,
            "save": self.save,
            "restore": self.restore,
            "verbose": self.set_verbose,
            "brief": self.set_brief,
        }

    def emit(self, line):
        self.output.append(line)

    def place_of(self, item):
        return self.state.places[item.id]

    def contents(self, place):
        return [item for item in self.world.order if self.state.places[item.id] == place]

    def is_open(self, item):
        return item.is_container() and self.state.containers[item.id] == "open"

    def is_burning(self, item):
        return item.light and self.state.lit[item.id]

    def reach(self, item):
        place = self.place_of(item)
        while place[0] == "inside":
            container = self.world.items[place[1]]
            if not self.is_open(container):
                return None
            place = self.place_of(container)
        return place

    def root(self, item):
        place = self.place_of(item)
        while place[0] == "inside":
            place = self.state.places[place[1]]
        return place

    def is_within(self, item, container):
        place = self.place_of(item)
        while place[0] == "inside":
            if place[1] == container.id:
                return True
            place = self.state.places[place[1]]
        return False

    def is_carried(self, item):
        return self.reach(item) == PLAYER

    def is_nearby(self, item):
        return self.reach(item) in (PLAYER, on_floor(self.state.room))

    def is_lit(self):
        if not self.world.rooms[self.state.room].dark:
            return True
        return any(self.is_burning(item) and self.is_nearby(item) for item in self.world.order)

    def visible_items(self):
        if self.is_lit():
            return [item for item in self.world.order if self.is_nearby(item)]
        return [item for item in self.world.order if self.is_carried(item)]

    def content_weight(self, container):
        return sum(item.weight for item in self.world.order if self.is_within(item, container))

    def total_weight(self, item):
        return item.weight + self.content_weight(item)

    def carried_weight(self):
        return sum(item.weight for item in self.world.order if self.root(item) == PLAYER)

    def too_heavy(self, item):
        if self.is_carried(item):
            return False
        return self.carried_weight() + self.total_weight(item) > self.world.max_weight

    def is_stored(self, item):
        return self.root(item) == on_floor(self.world.trophy)

    def stored_treasures(self):
        return [item for item in self.world.treasures if self.is_stored(item)]

    def treasure_points(self):
        return sum(item.points for item in self.stored_treasures())

    def total_score(self):
        return self.treasure_points() + self.state.bonus

    def display_name(self, item):
        notes = []
        if item.is_container():
            notes.append(self.state.containers[item.id])
        if self.is_burning(item):
            notes.append("lit")
        if not notes:
            return item.name
        return item.name + " (" + ", ".join(notes) + ")"

    def item_tree(self, place, depth):
        for item in self.contents(place):
            self.emit("  " * depth + self.display_name(item))
            if self.is_open(item):
                self.item_tree(inside(item.id), depth + 1)

    def describe(self, full):
        if not self.is_lit():
            self.emit("It is pitch dark.")
            return
        room = self.world.rooms[self.state.room]
        self.emit(room.name)
        if full:
            for line in room.description:
                self.emit(line)
        exits = self.state.exits[self.state.room]
        labels = []
        for direction in DIRECTIONS:
            if direction in exits:
                suffix = " (locked)" if exits[direction].locked else ""
                labels.append(direction + suffix)
        self.emit("Exits: " + (", ".join(labels) if labels else "none"))
        floor = on_floor(self.state.room)
        if self.contents(floor):
            self.emit("You see:")
            self.item_tree(floor, 1)

    def resolve(self, phrase):
        visible = self.visible_items()
        if phrase == ["it"]:
            if self.it is None:
                raise CommandFailed("I don't know what \"it\" refers to.")
            if self.it not in visible:
                raise CommandFailed(UNSEEN)
            return self.it
        for word in phrase:
            if word not in self.world.vocabulary:
                raise CommandFailed(f"I don't know the word \"{word}\".")
        matches = [item for item in visible if item.matches(phrase)]
        if not matches:
            raise CommandFailed(UNSEEN)
        if len(matches) > 1:
            names = ", ".join(item.name for item in matches)
            raise CommandFailed(f"Which do you mean: {names}?")
        self.it = matches[0]
        return self.it

    def require_open_container(self, item):
        if not item.is_container():
            raise CommandFailed(f"The {item.name} is not a container.")
        if not self.is_open(item):
            raise CommandFailed(f"The {item.name} is closed.")

    def require_carried(self, item):
        if not self.is_carried(item):
            raise CommandFailed(f"You aren't carrying the {item.name}.")

    def run_rules(self, rules):
        executed = 0
        messages = 0
        for rule in rules:
            if not rule.applies(self.state.flags):
                continue
            executed += 1
            if rule.effect == "MESSAGE":
                messages += 1
            self.apply_effect(rule)
        return executed, messages

    def apply_effect(self, rule):
        state = self.state
        values = rule.arguments
        if rule.effect == "MESSAGE":
            self.emit(values[0])
        elif rule.effect == "OPEN":
            state.exits[values[0]][values[1]] = Exit(values[2], None, False)
        elif rule.effect == "REMOVE":
            state.places[values[0]] = NOWHERE
        elif rule.effect == "ADD":
            state.places[values[0]] = on_floor(values[1])
        elif rule.effect == "SET":
            state.flags.add(values[0])
        elif rule.effect == "CLEAR":
            state.flags.discard(values[0])
        elif rule.effect == "POINTS":
            state.bonus += int(values[0])

    def go(self, command):
        direction = command.direction
        passage = self.state.exits[self.state.room].get(direction)
        if passage is None:
            raise CommandFailed("You can't go that way.")
        if passage.locked:
            raise CommandFailed(f"The way {direction} is locked.")
        destination = passage.destination
        self.state.room = destination
        self.baseline = self.is_lit()
        self.describe(self.verbose or destination not in self.state.visited)
        self.state.visited.add(destination)
        self.run_rules(self.world.entries.get(destination, []))

    def look(self, command):
        self.describe(True)

    def examine(self, command):
        item = self.resolve(command.first)
        if item.details:
            for line in item.details:
                self.emit(line)
        else:
            self.emit(f"You see nothing special about the {item.name}.")
        if item.light:
            condition = "lit" if self.state.lit[item.id] else "unlit"
            self.emit(f"It is {condition} (fuel {self.state.fuel[item.id]}).")
        if item.is_container():
            status = self.state.containers[item.id]
            if status == "locked":
                self.emit("It is locked.")
            elif status == "closed":
                self.emit("It is closed.")
            elif self.contents(inside(item.id)):
                self.emit("It contains:")
                self.item_tree(inside(item.id), 1)
            else:
                self.emit("It is empty.")
        if item.is_treasure():
            self.emit(f"It is a treasure worth {item.points} points.")
        self.emit(f"It weighs {self.total_weight(item)}.")

    def take(self, command):
        if not self.is_lit():
            raise CommandFailed("It is pitch dark.")
        container = None
        source = on_floor(self.state.room)
        if command.second is not None:
            container = self.resolve(command.second)
            self.require_open_container(container)
            source = inside(container.id)
        if command.is_all():
            self.take_all(source, container)
            return
        item = self.resolve(command.first)
        if container is not None and self.place_of(item) != source:
            raise CommandFailed(f"The {item.name} is not in the {container.name}.")
        if self.place_of(item) == PLAYER:
            raise CommandFailed(f"You already have the {item.name}.")
        if item.fixed:
            raise CommandFailed(f"The {item.name} is fixed in place.")
        if self.too_heavy(item):
            raise CommandFailed("You can't carry any more.")
        self.state.places[item.id] = PLAYER
        self.emit("Taken.")

    def take_all(self, source, container):
        candidates = [item for item in self.contents(source) if not item.fixed]
        if not candidates:
            if container is None:
                raise CommandFailed("There is nothing here to take.")
            raise CommandFailed(f"There is nothing in the {container.name} to take.")
        taken = 0
        for item in candidates:
            if self.too_heavy(item):
                self.emit(f"{item.name}: You can't carry any more.")
            else:
                self.state.places[item.id] = PLAYER
                self.emit(f"{item.name}: Taken.")
                taken += 1
        if taken == 0:
            raise CommandFailed()

    def drop(self, command):
        floor = on_floor(self.state.room)
        if command.is_all():
            held = self.contents(PLAYER)
            if not held:
                raise CommandFailed("You are empty-handed.")
            for item in held:
                self.state.places[item.id] = floor
                self.emit(f"{item.name}: Dropped.")
            return
        item = self.resolve(command.first)
        self.require_carried(item)
        self.state.places[item.id] = floor
        self.emit("Dropped.")

    def put_inside(self, item, container):
        if self.is_within(container, item):
            return f"The {container.name} is inside the {item.name}."
        destination = inside(container.id)
        previous = self.place_of(item)
        if previous == destination:
            return f"The {item.name} is already in the {container.name}."
        self.state.places[item.id] = destination
        if self.content_weight(container) > container.capacity:
            self.state.places[item.id] = previous
            return f"The {item.name} doesn't fit in the {container.name}."
        return None

    def put(self, command):
        if command.is_all():
            self.put_all(command.second)
            return
        item = self.resolve(command.first)
        container = self.resolve(command.second)
        self.require_carried(item)
        if item is container:
            raise CommandFailed(f"You can't put the {item.name} inside itself.")
        self.require_open_container(container)
        reason = self.put_inside(item, container)
        if reason is not None:
            raise CommandFailed(reason)
        self.emit(f"You put the {item.name} in the {container.name}.")

    def put_all(self, container_phrase):
        container = self.resolve(container_phrase)
        self.require_open_container(container)
        candidates = [item for item in self.contents(PLAYER) if item is not container]
        if not candidates:
            raise CommandFailed(f"You have nothing to put in the {container.name}.")
        done = 0
        for item in candidates:
            reason = self.put_inside(item, container)
            if reason is None:
                self.emit(f"{item.name}: Done.")
                done += 1
            else:
                self.emit(f"{item.name}: {reason}")
        if done == 0:
            raise CommandFailed()

    def inventory(self, command):
        if not self.contents(PLAYER):
            self.emit("You are empty-handed.")
            return
        self.emit("You are carrying:")
        self.item_tree(PLAYER, 1)
        self.emit(f"Total weight: {self.carried_weight()}/{self.world.max_weight}")

    def open_container(self, command):
        item = self.resolve(command.first)
        if not item.is_container():
            raise CommandFailed(f"You can't open the {item.name}.")
        status = self.state.containers[item.id]
        if status == "open":
            raise CommandFailed(f"The {item.name} is already open.")
        if status == "locked":
            raise CommandFailed(f"The {item.name} is locked.")
        self.state.containers[item.id] = "open"
        inner = self.contents(inside(item.id))
        if inner:
            names = ", ".join(content.name for content in inner)
            self.emit(f"Opening the {item.name} reveals {names}.")
        else:
            self.emit("Opened.")

    def close_container(self, command):
        item = self.resolve(command.first)
        if not item.is_container():
            raise CommandFailed(f"You can't close the {item.name}.")
        if not self.is_open(item):
            raise CommandFailed(f"The {item.name} is already closed.")
        self.state.containers[item.id] = "closed"
        self.emit("Closed.")

    def unlock(self, command):
        self.change_lock(command, False)

    def lock(self, command):
        self.change_lock(command, True)

    def change_lock(self, command, locking):
        target = command.first
        if len(target) == 1 and target[0] in DIRECTION_WORDS:
            self.change_exit_lock(DIRECTION_WORDS[target[0]], command.second, locking)
        else:
            self.change_container_lock(self.resolve(target), command.second, locking)
        self.emit("Locked." if locking else "Unlocked.")

    def change_exit_lock(self, direction, key_phrase, locking):
        room = self.state.room
        passage = self.state.exits[room].get(direction)
        if passage is None:
            raise CommandFailed(f"There is no exit {direction}.")
        if passage.key is None:
            raise CommandFailed(f"The way {direction} has no lock.")
        if not locking and not passage.locked:
            raise CommandFailed(f"The way {direction} is not locked.")
        if locking and passage.locked:
            raise CommandFailed(f"The way {direction} is already locked.")
        self.check_key(passage.key, key_phrase)
        passage.locked = locking
        back = self.state.exits[passage.destination].get(OPPOSITE[direction])
        if back is not None and back.destination == room and back.key == passage.key:
            back.locked = locking

    def change_container_lock(self, item, key_phrase, locking):
        if not item.is_container() or item.key is None:
            raise CommandFailed(f"The {item.name} has no lock.")
        status = self.state.containers[item.id]
        if not locking and status != "locked":
            raise CommandFailed(f"The {item.name} is not locked.")
        if locking and status == "locked":
            raise CommandFailed(f"The {item.name} is already locked.")
        if locking and status == "open":
            raise CommandFailed(f"You must close the {item.name} first.")
        self.check_key(item.key, key_phrase)
        self.state.containers[item.id] = "locked" if locking else "closed"

    def check_key(self, key, key_phrase):
        if key_phrase is None:
            item = self.world.items[key]
            if not self.is_carried(item):
                raise CommandFailed("You don't have the right key.")
            self.emit(f"(with the {item.name})")
            return
        item = self.resolve(key_phrase)
        self.require_carried(item)
        if item.id != key:
            raise CommandFailed(f"The {item.name} doesn't fit.")

    def use(self, command):
        item = self.resolve(command.first)
        other = self.resolve(command.second)
        self.require_carried(item)
        rules = self.world.uses.get((item.id, other.id), [])
        executed, messages = self.run_rules(rules)
        if executed == 0:
            raise CommandFailed("Nothing happens.")
        if messages == 0:
            self.emit("Done.")

    def light(self, command):
        item = self.resolve(command.first)
        if not item.light:
            raise CommandFailed(f"You can't light the {item.name}.")
        if self.state.lit[item.id]:
            raise CommandFailed(f"The {item.name} is already lit.")
        if self.state.fuel[item.id] == 0:
            raise CommandFailed(f"The {item.name} has no fuel.")
        self.state.lit[item.id] = True
        self.emit(f"The {item.name} is now lit.")

    def extinguish(self, command):
        item = self.resolve(command.first)
        if not item.light:
            raise CommandFailed(f"You can't extinguish the {item.name}.")
        if not self.state.lit[item.id]:
            raise CommandFailed(f"The {item.name} is not lit.")
        self.state.lit[item.id] = False
        self.emit(f"The {item.name} is now out.")

    def wait(self, command):
        self.emit("Time passes.")

    def show_score(self, command):
        treasure = self.treasure_points()
        bonus = self.state.bonus
        self.emit(
            f"You have scored {treasure + bonus} points (treasure {treasure}, "
            f"bonus {bonus}) in {self.state.moves} moves."
        )
        stored = len(self.stored_treasures())
        self.emit(f"Treasures stored: {stored} of {len(self.world.treasures)}.")

    def save(self, command):
        self.saved = self.state.copy()
        self.emit("Game saved.")

    def restore(self, command):
        if self.saved is None:
            raise CommandFailed("There is no saved game.")
        self.state = self.saved.copy()
        self.emit("Game restored.")
        self.describe(True)

    def set_verbose(self, command):
        self.verbose = True
        self.emit("Verbose mode.")

    def set_brief(self, command):
        self.verbose = False
        self.emit("Brief mode.")

    def burn_fuel(self):
        state = self.state
        nearby = [item for item in self.world.order if self.is_nearby(item)]
        for item in self.world.order:
            if not self.is_burning(item):
                continue
            state.fuel[item.id] -= 1
            if state.fuel[item.id] == 0:
                state.lit[item.id] = False
                if item in nearby:
                    self.emit(f"The {item.name} goes out.")

    def pass_turn(self):
        state = self.state
        state.moves += 1
        self.burn_fuel()
        lit = self.is_lit()
        if self.baseline and not lit:
            self.emit("It is now pitch dark.")
        elif not self.baseline and lit:
            self.describe(True)
        if lit:
            state.darkness = 0
        else:
            state.darkness += 1
            if state.darkness == 2:
                self.emit("You hear something moving in the dark.")
            elif state.darkness == 3:
                state.status = "dead"
        treasures = self.world.treasures
        if state.status == "none" and treasures and len(self.stored_treasures()) == len(treasures):
            state.status = "won"
        if state.status == "dead":
            self.emit("*** You have died ***")
        elif state.status == "won":
            self.emit("*** You have won ***")
        if state.status != "none":
            self.emit(f"You scored {self.total_score()} points in {state.moves} moves.")

    def perform(self, command):
        self.baseline = self.is_lit()
        self.handlers[command.verb](command)
        if command.verb in ACTIONS:
            self.pass_turn()

    def run(self, words):
        try:
            self.perform(parse_command(words, self.state.status != "none"))
        except CommandFailed as failure:
            if failure.message is not None:
                self.emit(failure.message)

    def execute(self, line):
        self.emit("> " + line)
        words = command_words(line)
        if words and words[0] in REPEAT_WORDS:
            if len(words) > 1:
                self.emit(UNCLEAR)
            elif self.previous is None:
                self.emit("There is nothing to repeat.")
            else:
                self.run(self.previous)
            return
        self.previous = words
        self.run(words)

    def start(self):
        self.describe(True)

    def finish(self):
        self.emit(f"Final score: {self.total_score()} points in {self.state.moves} moves.")


def main():
    lines = sys.stdin.read().splitlines()
    begin = lines.index("BEGIN")
    world = World()
    for line in lines[:begin]:
        world.define(line)
    world.finish()
    game = Game(world)
    game.start()
    for line in lines[begin + 1:]:
        if line == "QUIT":
            break
        game.execute(line)
    game.finish()
    sys.stdout.write("\n".join(game.output) + "\n")


if __name__ == "__main__":
    main()
