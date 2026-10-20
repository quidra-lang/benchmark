import 'dart:io';

enum PlaceKind { nowhere, room, player, inside }
typedef Place = (PlaceKind, int);
const player = (PlaceKind.player, 0);
enum ContainerState { open, closed, locked }
enum EndStatus { none, won, dead }
enum Verb { go, look, examine, take, drop, put, inventory, open, close, unlock, lock, use, light, extinguish, wait, score, save, restore, verbose, brief }
typedef Exit = ({int destination, int? key, bool locked});

sealed class Effect { const Effect(); }
final class MessageEffect extends Effect {
  final String text;
  const MessageEffect(this.text);
}
final class OpenEffect extends Effect {
  final int room, direction, destination;
  const OpenEffect(this.room, this.direction, this.destination);
}
final class MoveEffect extends Effect {
  final int item;
  final Place place;
  const MoveEffect(this.item, this.place);
}
final class FlagEffect extends Effect {
  final String flag;
  final bool on;
  const FlagEffect(this.flag, this.on);
}
final class PointsEffect extends Effect {
  final int amount;
  const PointsEffect(this.amount);
}
final class Rule {
  final String? flag;
  final bool whenOn;
  final Effect effect;
  const Rule(this.flag, this.whenOn, this.effect);
}
typedef UseRule = ({int first, int second, Rule rule});
final class CommandFailure implements Exception {
  final String message;
  const CommandFailure(this.message);
}
Never fail(String message) => throw CommandFailure(message);

final class Room {
  final String id;
  String name = '';
  bool dark = false;
  final descriptions = <String>[], enter = <Rule>[];
  Room(this.id);
}
final class Item {
  final String id;
  String name = '';
  int weight = 0;
  int? treasure, capacity, key;
  bool light = false, fixed = false;
  final Set<String> nouns;
  final nameWords = <String>{}, details = <String>[];
  Item(this.id) : nouns = {id};
}

final class GameState {
  int room = 0, bonus = 0, moves = 0, darkness = 0;
  EndStatus end = EndStatus.none;
  final List<Place> places;
  final List<ContainerState> containers;
  final List<int> fuel;
  final List<bool> lit, visited;
  final List<List<Exit?>> exits;
  final flags = <String>{};
  GameState(int rooms, int items)
      : places = List.filled(items, (PlaceKind.nowhere, 0)),
        containers = List.filled(items, ContainerState.open),
        fuel = List.filled(items, 0), lit = List.filled(items, false),
        visited = List.filled(rooms, false), exits = List.generate(rooms, (_) => List<Exit?>.filled(6, null));

  GameState copy() {
    final result = GameState(visited.length, places.length)
      ..room = room ..bonus = bonus ..moves = moves ..darkness = darkness ..end = end;
    result.places.setAll(0, places); result.containers.setAll(0, containers);
    result.fuel.setAll(0, fuel); result.lit.setAll(0, lit); result.visited.setAll(0, visited);
    for (var r = 0; r < exits.length; r++) { result.exits[r].setAll(0, exits[r]); }
    result.flags.addAll(flags);
    return result;
  }
}

const directions = ['north', 'south', 'east', 'west', 'up', 'down'];
final verbs = <String, Verb>{
  for (final (i, group) in [
    'go walk run', 'look l', 'examine x inspect read', 'take get grab', 'drop discard',
    'put insert place', 'inventory inv i', 'open', 'close shut', 'unlock', 'lock', 'use apply',
    'light ignite', 'extinguish douse snuff', 'wait z', 'score', 'save', 'restore load', 'verbose', 'brief',
  ].indexed)
    for (final word in group.split(' ')) word: Verb.values[i],
};
int? directionOf(String word) {
  for (var i = 0; i < directions.length; i++) {
    if (word == directions[i] || word == directions[i][0]) return i;
  }
  return null;
}
List<String> words(String line) => line.toLowerCase().split(' ')
    .where((word) => word.isNotEmpty && !const {'the', 'a', 'an'}.contains(word)).toList();
bool all(List<String> phrase) => phrase.length == 1 && phrase[0] == 'all';

final class Adventure {
  late final List<Room> rooms;
  late final List<Item> items;
  late final int trophy, maxWeight;
  final useRules = <UseRule>[], vocabulary = <String>{};
  late GameState state;
  GameState? saved;
  int? pronoun;
  String? previous;
  bool verbose = false;
  List<String> output = [];

  Adventure(List<List<String>> definitions) {
    rooms = [for (final row in definitions) if (row[0] == 'ROOM') Room(row[1])];
    items = [for (final row in definitions) if (row[0] == 'ITEM') Item(row[1])]
      ..sort((a, b) => a.id.compareTo(b.id));
    final roomIndex = {for (final (i, room) in rooms.indexed) room.id: i};
    final itemIndex = {for (final (i, item) in items.indexed) item.id: i};
    state = GameState(rooms.length, items.length);
    Place initialPlace(String text) => switch (text) {
      'PLAYER' => player, 'NOWHERE' => (PlaceKind.nowhere, 0), _ => (PlaceKind.room, roomIndex[text]!),
    };
    Rule parseRule(List<String> row, int index) {
      String? flag;
      var whenOn = true;
      if (row[index] == 'IF' || row[index] == 'UNLESS') {
        whenOn = row[index] == 'IF'; flag = row[index + 1]; index += 2;
      }
      final Effect effect = switch (row[index]) {
        'MESSAGE' => MessageEffect(row.skip(index + 1).join(' ')),
        'OPEN' => OpenEffect(roomIndex[row[index + 1]]!, directionOf(row[index + 2])!, roomIndex[row[index + 3]]!),
        'REMOVE' => MoveEffect(itemIndex[row[index + 1]]!, (PlaceKind.nowhere, 0)),
        'ADD' => MoveEffect(itemIndex[row[index + 1]]!, (PlaceKind.room, roomIndex[row[index + 2]]!)),
        'SET' => FlagEffect(row[index + 1], true), 'CLEAR' => FlagEffect(row[index + 1], false),
        'POINTS' => PointsEffect(int.parse(row[index + 1])), _ => throw StateError('Invalid definition'),
      };
      return Rule(flag, whenOn, effect);
    }
    for (final row in definitions) {
      switch (row[0]) {
        case 'ROOM':
          final room = rooms[roomIndex[row[1]]!];
          room.dark = row[2] == 'DARK'; room.name = row.skip(room.dark ? 3 : 2).join(' ');
        case 'DESC': rooms[roomIndex[row[1]]!].descriptions.add(row.skip(2).join(' '));
        case 'EXIT':
          state.exits[roomIndex[row[1]]!][directionOf(row[2])!] =
              (destination: roomIndex[row[3]]!, key: row.length > 4 ? itemIndex[row[5]]! : null, locked: row.length > 4);
        case 'ITEM':
          final x = itemIndex[row[1]]!, item = items[itemIndex[row[1]]!];
          var index = 4;
          state.places[x] = initialPlace(row[2]); item.weight = int.parse(row[3]);
          if (row[index] == 'TREASURE') { item.treasure = int.parse(row[index + 1]); index += 2; }
          if (row[index] == 'LIGHT') { item.light = true; state.fuel[x] = int.parse(row[index + 1]); index += 2; }
          if (row[index] == 'CONTAINER') {
            item.capacity = int.parse(row[index + 1]); index += 2;
            if (row[index] == 'CLOSED') { state.containers[x] = ContainerState.closed; index++; }
            if (row[index] == 'LOCKED') {
              item.key = itemIndex[row[index + 1]]!; state.containers[x] = ContainerState.locked; index += 2;
            }
          }
          if (row[index] == 'FIXED') { item.fixed = true; index++; }
          item.name = row.skip(index).join(' '); item.nameWords.addAll(row.skip(index));
        case 'INSIDE': state.places[itemIndex[row[1]]!] = (PlaceKind.inside, itemIndex[row[2]]!);
        case 'ALIAS': items[itemIndex[row[1]]!].nouns.add(row[2]);
        case 'DETAIL': items[itemIndex[row[1]]!].details.add(row.skip(2).join(' '));
        case 'RULE': useRules.add((first: itemIndex[row[1]]!, second: itemIndex[row[2]]!, rule: parseRule(row, 3)));
        case 'ENTER': rooms[roomIndex[row[1]]!].enter.add(parseRule(row, 2));
        case 'TROPHY': trophy = roomIndex[row[1]]!;
        case 'START': state.room = roomIndex[row[1]]!;
        case 'MAXWEIGHT': maxWeight = int.parse(row[1]);
      }
    }
    state.visited[state.room] = true;
    for (final item in items) { vocabulary.addAll(item.nouns); vocabulary.addAll(item.nameWords); }
  }

  void say(String text) => output.add(text);
  Place get floor => (PlaceKind.room, state.room);
  List<int> direct(Place place) => [for (var x = 0; x < items.length; x++) if (state.places[x] == place) x];
  Set<int> reachable(Place place) {
    final result = <int>{};
    void visit(Place source) {
      for (final x in direct(source)) {
        result.add(x);
        if (items[x].capacity != null && state.containers[x] == ContainerState.open) visit((PlaceKind.inside, x));
      }
    }
    visit(place);
    return result;
  }
  Set<int> carried() => reachable(player);
  bool isLit() => !rooms[state.room].dark || {...carried(), ...reachable(floor)}.any((x) => state.lit[x]);
  Set<int> visible() => carried()..addAll(isLit() ? reachable(floor) : <int>{});
  int totalWeight(int x) => items[x].weight + contentWeight(x);
  int contentWeight(int x) => direct((PlaceKind.inside, x)).fold(0, (sum, item) => sum + totalWeight(item));
  int carriedWeight() => direct(player).fold(0, (sum, item) => sum + totalWeight(item));
  bool within(int x, int container) {
    while (state.places[x].$1 == PlaceKind.inside) {
      x = state.places[x].$2;
      if (x == container) return true;
    }
    return false;
  }
  bool stored(int x) {
    while (state.places[x].$1 == PlaceKind.inside) { x = state.places[x].$2; }
    return state.places[x] == (PlaceKind.room, trophy);
  }
  ({int points, int stored, int total}) treasures() {
    var points = 0, storedCount = 0, total = 0;
    for (var x = 0; x < items.length; x++) {
      final value = items[x].treasure;
      if (value == null) continue;
      total++;
      if (stored(x)) { points += value; storedCount++; }
    }
    return (points: points, stored: storedCount, total: total);
  }
  int get score => treasures().points + state.bonus;
  String displayName(int x) {
    final annotations = [
      if (items[x].capacity != null) state.containers[x].name,
      if (state.lit[x]) 'lit',
    ];
    return items[x].name + (annotations.isEmpty ? '' : ' (${annotations.join(', ')})');
  }
  void itemTree(Place place, int depth) {
    for (final x in direct(place)) {
      say('${'  ' * depth}${displayName(x)}');
      if (items[x].capacity != null && state.containers[x] == ContainerState.open) itemTree((PlaceKind.inside, x), depth + 1);
    }
  }
  void describe(bool full) {
    if (!isLit()) { say('It is pitch dark.'); return; }
    final room = rooms[state.room];
    say(room.name);
    if (full) output.addAll(room.descriptions);
    final exits = <String>[];
    for (var d = 0; d < 6; d++) {
      final exit = state.exits[state.room][d];
      if (exit != null) exits.add(directions[d] + (exit.locked ? ' (locked)' : ''));
    }
    say('Exits: ${exits.isEmpty ? 'none' : exits.join(', ')}');
    if (direct(floor).isNotEmpty) { say('You see:'); itemTree(floor, 1); }
  }
  int resolve(List<String> phrase) {
    final seen = visible();
    if (phrase.length == 1 && phrase[0] == 'it') {
      final item = pronoun;
      if (item == null) fail('I don\'t know what "it" refers to.');
      if (!seen.contains(item)) fail('You can\'t see any such thing.');
      return item;
    }
    for (final word in phrase) {
      if (!vocabulary.contains(word)) fail('I don\'t know the word "$word".');
    }
    final matches = [for (var x = 0; x < items.length; x++)
      if (seen.contains(x) && items[x].nouns.contains(phrase.last) && phrase.take(phrase.length - 1).every(items[x].nameWords.contains)) x];
    if (matches.isEmpty) fail('You can\'t see any such thing.');
    if (matches.length > 1) fail('Which do you mean: ${matches.map((x) => items[x].name).join(', ')}?');
    pronoun = matches.single;
    return matches.single;
  }
  void examine(int x) {
    final item = items[x];
    if (item.details.isEmpty) { say('You see nothing special about the ${item.name}.'); }
    else { output.addAll(item.details); }
    if (item.light) say('It is ${state.lit[x] ? 'lit' : 'unlit'} (fuel ${state.fuel[x]}).');
    if (item.capacity != null) {
      if (state.containers[x] == ContainerState.locked) { say('It is locked.'); }
      else if (state.containers[x] == ContainerState.closed) { say('It is closed.'); }
      else if (direct((PlaceKind.inside, x)).isEmpty) { say('It is empty.'); }
      else { say('It contains:'); itemTree((PlaceKind.inside, x), 1); }
    }
    if (item.treasure != null) say('It is a treasure worth ${item.treasure} points.');
    say('It weighs ${totalWeight(x)}.');
  }

  void requireContainer(int x) {
    if (items[x].capacity == null) fail('The ${items[x].name} is not a container.');
    if (state.containers[x] != ContainerState.open) fail('The ${items[x].name} is closed.');
  }
  bool take(List<String> target, List<String>? from) {
    if (!isLit()) fail('It is pitch dark.');
    int? container;
    var source = floor;
    if (from != null) {
      container = resolve(from); requireContainer(container);
      source = (PlaceKind.inside, container);
    }
    if (all(target)) {
      final candidates = direct(source).where((x) => !items[x].fixed).toList();
      if (candidates.isEmpty) fail(container == null ? 'There is nothing here to take.' : 'There is nothing in the ${items[container].name} to take.');
      var taken = false;
      for (final x in candidates) {
        if (!carried().contains(x) && carriedWeight() + totalWeight(x) > maxWeight) {
          say('${items[x].name}: You can\'t carry any more.');
        } else { state.places[x] = player; taken = true; say('${items[x].name}: Taken.'); }
      }
      return taken;
    }
    final x = resolve(target);
    if (container != null && state.places[x] != source) fail('The ${items[x].name} is not in the ${items[container].name}.');
    if (state.places[x] == player) fail('You already have the ${items[x].name}.');
    if (items[x].fixed) fail('The ${items[x].name} is fixed in place.');
    if (!carried().contains(x) && carriedWeight() + totalWeight(x) > maxWeight) fail('You can\'t carry any more.');
    state.places[x] = player; say('Taken.');
    return true;
  }
  void drop(List<String> target) {
    if (all(target)) {
      final held = direct(player);
      if (held.isEmpty) fail('You are empty-handed.');
      for (final x in held) { state.places[x] = floor; say('${items[x].name}: Dropped.'); }
      return;
    }
    final x = resolve(target);
    if (!carried().contains(x)) fail('You aren\'t carrying the ${items[x].name}.');
    state.places[x] = floor; say('Dropped.');
  }
  String? putItem(int x, int y) {
    if (within(y, x)) return 'The ${items[y].name} is inside the ${items[x].name}.';
    if (state.places[x] == (PlaceKind.inside, y)) return 'The ${items[x].name} is already in the ${items[y].name}.';
    final weight = contentWeight(y) + (within(x, y) ? 0 : totalWeight(x));
    if (weight > items[y].capacity!) return 'The ${items[x].name} doesn\'t fit in the ${items[y].name}.';
    state.places[x] = (PlaceKind.inside, y);
    return null;
  }
  bool put(List<String> first, List<String> second) {
    if (all(first)) {
      final y = resolve(second); requireContainer(y);
      final candidates = direct(player).where((x) => x != y).toList();
      if (candidates.isEmpty) fail('You have nothing to put in the ${items[y].name}.');
      var moved = false;
      for (final x in candidates) {
        final reason = putItem(x, y);
        if (reason == null) moved = true;
        say('${items[x].name}: ${reason ?? 'Done.'}');
      }
      return moved;
    }
    final x = resolve(first), y = resolve(second);
    if (!carried().contains(x)) fail('You aren\'t carrying the ${items[x].name}.');
    if (x == y) fail('You can\'t put the ${items[x].name} inside itself.');
    requireContainer(y);
    final reason = putItem(x, y);
    if (reason != null) fail(reason);
    say('You put the ${items[x].name} in the ${items[y].name}.');
    return true;
  }
  void open(int x) {
    final name = items[x].name;
    if (items[x].capacity == null) fail('You can\'t open the $name.');
    if (state.containers[x] == ContainerState.open) fail('The $name is already open.');
    if (state.containers[x] == ContainerState.locked) fail('The $name is locked.');
    state.containers[x] = ContainerState.open;
    final children = direct((PlaceKind.inside, x));
    say(children.isEmpty ? 'Opened.' : 'Opening the $name reveals ${children.map((y) => items[y].name).join(', ')}.');
  }
  void close(int x) {
    if (items[x].capacity == null) fail('You can\'t close the ${items[x].name}.');
    if (state.containers[x] != ContainerState.open) fail('The ${items[x].name} is already closed.');
    state.containers[x] = ContainerState.closed; say('Closed.');
  }
  void checkKey(int key, List<String>? phrase) {
    if (phrase != null) {
      final x = resolve(phrase);
      if (!carried().contains(x)) fail('You aren\'t carrying the ${items[x].name}.');
      if (x != key) fail('The ${items[x].name} doesn\'t fit.');
    } else {
      if (!carried().contains(key)) fail('You don\'t have the right key.');
      say('(with the ${items[key].name})');
    }
  }
  void lock(List<String> target, List<String>? keyPhrase, bool locking) {
    final d = target.length == 1 ? directionOf(target[0]) : null;
    if (d != null) {
      final exit = state.exits[state.room][d];
      if (exit == null) fail('There is no exit ${directions[d]}.');
      if (exit.key == null) fail('The way ${directions[d]} has no lock.');
      if (exit.locked == locking) fail('The way ${directions[d]} is ${locking ? 'already locked' : 'not locked'}.');
      checkKey(exit.key!, keyPhrase);
      state.exits[state.room][d] = (destination: exit.destination, key: exit.key, locked: locking);
      final opposite = state.exits[exit.destination][d ^ 1];
      if (opposite != null && opposite.destination == state.room && opposite.key == exit.key) {
        state.exits[exit.destination][d ^ 1] = (destination: opposite.destination, key: opposite.key, locked: locking);
      }
    } else {
      final x = resolve(target), item = items[x];
      if (item.capacity == null || item.key == null) fail('The ${item.name} has no lock.');
      if ((state.containers[x] == ContainerState.locked) == locking) fail('The ${item.name} is ${locking ? 'already locked' : 'not locked'}.');
      if (locking && state.containers[x] == ContainerState.open) fail('You must close the ${item.name} first.');
      checkKey(item.key!, keyPhrase);
      state.containers[x] = locking ? ContainerState.locked : ContainerState.closed;
    }
    say(locking ? 'Locked.' : 'Unlocked.');
  }
  ({int executed, bool message}) runRules(Iterable<Rule> rules) {
    var executed = 0, message = false;
    for (final rule in rules) {
      if (rule.flag != null && state.flags.contains(rule.flag) != rule.whenOn) continue;
      executed++;
      switch (rule.effect) {
        case MessageEffect(:final text): say(text); message = true;
        case OpenEffect(:final room, :final direction, :final destination):
          state.exits[room][direction] = (destination: destination, key: null, locked: false);
        case MoveEffect(:final item, :final place): state.places[item] = place;
        case FlagEffect(:final flag, :final on):
          if (on) { state.flags.add(flag); } else { state.flags.remove(flag); }
        case PointsEffect(:final amount): state.bonus += amount;
      }
    }
    return (executed: executed, message: message);
  }
  void use(List<String> first, List<String> second) {
    final x = resolve(first), y = resolve(second);
    if (!carried().contains(x)) fail('You aren\'t carrying the ${items[x].name}.');
    final result = runRules(useRules.where((rule) => rule.first == x && rule.second == y).map((rule) => rule.rule));
    if (result.executed == 0) fail('Nothing happens.');
    if (!result.message) say('Done.');
  }
  void light(int x, bool lighting) {
    final verb = lighting ? 'light' : 'extinguish', name = items[x].name;
    if (!items[x].light) fail('You can\'t $verb the $name.');
    if (state.lit[x] == lighting) fail('The $name is ${lighting ? 'already lit' : 'not lit'}.');
    if (lighting && state.fuel[x] == 0) fail('The $name has no fuel.');
    state.lit[x] = lighting;
    say('The $name is now ${lighting ? 'lit' : 'out'}.');
  }
  bool move(int direction) {
    final exit = state.exits[state.room][direction];
    if (exit == null) fail('You can\'t go that way.');
    if (exit.locked) fail('The way ${directions[direction]} is locked.');
    state.room = exit.destination;
    final baseline = isLit();
    describe(verbose || !state.visited[state.room]); state.visited[state.room] = true;
    runRules(rooms[state.room].enter);
    return baseline;
  }
  void turn(bool baseline) {
    state.moves++;
    final reachable = carried()..addAll(this.reachable(floor));
    for (var x = 0; x < items.length; x++) {
      if (!state.lit[x]) continue;
      state.fuel[x]--;
      if (state.fuel[x] == 0) {
        state.lit[x] = false;
        if (reachable.contains(x)) say('The ${items[x].name} goes out.');
      }
    }
    final lit = isLit();
    if (baseline && !lit) { say('It is now pitch dark.'); }
    else if (!baseline && lit) { describe(true); }
    state.darkness = lit ? 0 : state.darkness + 1;
    if (state.darkness == 2) say('You hear something moving in the dark.');
    if (state.darkness == 3) state.end = EndStatus.dead;
    final treasure = treasures();
    if (state.end == EndStatus.none && treasure.total > 0 && treasure.stored == treasure.total) state.end = EndStatus.won;
    if (state.end != EndStatus.none) {
      say(state.end == EndStatus.dead ? '*** You have died ***' : '*** You have won ***');
      say('You scored ${treasure.points + state.bonus} points in ${state.moves} moves.');
    }
  }
  void run(Verb verb, List<String> first, {List<String>? second, int direction = 0}) {
    var baseline = isLit(), success = true;
    switch (verb) {
      case Verb.go: baseline = move(direction);
      case Verb.look: describe(true);
      case Verb.examine: examine(resolve(first));
      case Verb.take: success = take(first, second);
      case Verb.drop: drop(first);
      case Verb.put: success = put(first, second!);
      case Verb.open: open(resolve(first));
      case Verb.close: close(resolve(first));
      case Verb.unlock: lock(first, second, false);
      case Verb.lock: lock(first, second, true);
      case Verb.use: use(first, second!);
      case Verb.light: light(resolve(first), true);
      case Verb.extinguish: light(resolve(first), false);
      case Verb.wait: say('Time passes.');
      case Verb.inventory:
        if (direct(player).isEmpty) { say('You are empty-handed.'); }
        else { say('You are carrying:'); itemTree(player, 1); say('Total weight: ${carriedWeight()}/$maxWeight'); }
      case Verb.score:
        final treasure = treasures();
        say('You have scored ${treasure.points + state.bonus} points (treasure ${treasure.points}, bonus ${state.bonus}) in ${state.moves} moves.');
        say('Treasures stored: ${treasure.stored} of ${treasure.total}.');
      case Verb.save: saved = state.copy(); say('Game saved.');
      case Verb.restore:
        final snapshot = saved;
        if (snapshot == null) fail('There is no saved game.');
        state = snapshot.copy(); say('Game restored.'); describe(true);
      case Verb.verbose: verbose = true; say('Verbose mode.');
      case Verb.brief: verbose = false; say('Brief mode.');
    }
    if (success && const {Verb.go, Verb.take, Verb.drop, Verb.put, Verb.open, Verb.close, Verb.unlock, Verb.lock,
        Verb.use, Verb.light, Verb.extinguish, Verb.wait}.contains(verb)) turn(baseline);
  }
  void interpret(List<String> input) {
    if (input.isEmpty) fail('I beg your pardon?');
    final tokens = directionOf(input[0]) != null ? ['go', ...input] : input;
    var verb = verbs[tokens[0]];
    if (verb == null) fail('I don\'t know the verb "${tokens[0]}".');
    var rest = tokens.sublist(1);
    if (state.end != EndStatus.none && verb != Verb.restore) fail('The game is over.');
    if (verb == Verb.look && rest.isNotEmpty) {
      if (rest[0] != 'at') fail('I don\'t understand that.');
      verb = Verb.examine; rest = rest.sublist(1);
    }
    if (const {Verb.look, Verb.inventory, Verb.wait, Verb.score, Verb.save, Verb.restore, Verb.verbose, Verb.brief}.contains(verb)) {
      if (rest.isNotEmpty) fail('I don\'t understand that.');
      run(verb, rest); return;
    }
    if (rest.isEmpty) fail(verb == Verb.go ? 'Which way do you want to go?' : 'What do you want to ${verb.name}?');
    if (verb == Verb.go) {
      final direction = rest.length == 1 ? directionOf(rest[0]) : null;
      if (direction == null) fail('I don\'t understand that.');
      run(verb, rest, direction: direction); return;
    }
    final prepositions = switch (verb) {
      Verb.put => const {'in', 'into'}, Verb.use => const {'on', 'with'},
      Verb.lock || Verb.unlock when rest.contains('with') => const {'with'},
      Verb.take when rest.contains('from') => const {'from'}, _ => const <String>{},
    };
    if (prepositions.isEmpty) { run(verb, rest); return; }
    final split = rest.indexWhere(prepositions.contains);
    if (split <= 0 || split == rest.length - 1) fail('I don\'t understand that.');
    run(verb, rest.sublist(0, split), second: rest.sublist(split + 1));
  }
  List<String> start() {
    output = []; describe(true); return output;
  }
  List<String> process(String line) {
    output = ['> $line'];
    try {
      var tokens = words(line);
      if (tokens.isNotEmpty && (tokens[0] == 'again' || tokens[0] == 'g')) {
        if (tokens.length != 1) fail('I don\'t understand that.');
        final old = previous;
        if (old == null) fail('There is nothing to repeat.');
        tokens = words(old);
      } else { previous = line; }
      interpret(tokens);
    } on CommandFailure catch (failure) { say(failure.message); }
    return output;
  }
  String finalScore() => 'Final score: $score points in ${state.moves} moves.';
}

void main() {
  final definitions = <List<String>>[];
  for (var line = stdin.readLineSync()!; line != 'BEGIN'; line = stdin.readLineSync()!) {
    definitions.add(line.split(' '));
  }
  final adventure = Adventure(definitions);
  for (final row in adventure.start()) { stdout.writeln(row); }
  for (var line = stdin.readLineSync()!; line != 'QUIT'; line = stdin.readLineSync()!) {
    for (final row in adventure.process(line)) { stdout.writeln(row); }
  }
  stdout.writeln(adventure.finalScore());
}
