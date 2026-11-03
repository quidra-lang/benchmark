import 'dart:io';

final class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
}

typedef Entry = ({int key, String value});
typedef SearchResult = ({int? page, int position, List<String> path});
String display(Entry entry) => '${entry.key}=${entry.value}';

bool sameItems<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final class Node {
  final List<Entry> entries;
  final List<int> children;
  Node([List<Entry>? entries, List<int>? children])
      : entries = entries ?? [], children = children ?? [];
  bool get leaf => children.isEmpty;
  String get notation => '[${entries.map((entry) => entry.key).join(' ')}]';
  int position(int key) {
    var index = 0;
    while (index < entries.length && key > entries[index].key) {
      index++;
    }
    return index;
  }
  Node copy() => Node(List.of(entries), List.of(children));
  bool sameContent(Node other) =>
      sameItems(entries, other.entries) && sameItems(children, other.children);
}

final class Trace {
  final bool enabled;
  final List<String> lines = [];
  Trace(this.enabled);
  void emit(String line) {
    if (enabled) lines.add(line);
  }
}

final class Tree {
  final int degree;
  int root = 0, splits = 0, merges = 0, borrows = 0;
  Map<int, Node> pages = {0: Node()};
  Tree(this.degree);

  Map<int, Node> copyPages() => pages.map((page, node) => MapEntry(page, node.copy()));
  Tree copy() => Tree(degree)
    ..root = root
    ..pages = copyPages()
    ..splits = splits
    ..merges = merges
    ..borrows = borrows;
  ({int writes, int frees}) changes(Map<int, Node> before) {
    var writes = 0, frees = 0;
    for (final entry in pages.entries) {
      final old = before[entry.key];
      if (old == null || !entry.value.sameContent(old)) writes++;
    }
    for (final page in before.keys) {
      if (!pages.containsKey(page)) frees++;
    }
    return (writes: writes, frees: frees);
  }
  int allocate(Node node) {
    var page = 0;
    while (pages.containsKey(page)) {
      page++;
    }
    pages[page] = node;
    return page;
  }
  int get height {
    var page = root, height = 0;
    while (!pages[page]!.leaf) {
      page = pages[page]!.children.first;
      height++;
    }
    return height;
  }
  List<Entry> entries() {
    final result = <Entry>[];
    void visit(int page) {
      final node = pages[page]!;
      if (!node.leaf) visit(node.children.first);
      for (var i = 0; i < node.entries.length; i++) {
        result.add(node.entries[i]);
        if (!node.leaf) visit(node.children[i + 1]);
      }
    }
    visit(root);
    return result;
  }
  SearchResult search(int key) {
    var page = root;
    final path = <String>[];
    while (true) {
      final node = pages[page]!, index = node.position(key);
      path.add(node.notation);
      if (index < node.entries.length && node.entries[index].key == key) {
        return (page: page, position: index, path: path);
      }
      if (node.leaf) return (page: null, position: -1, path: path);
      page = node.children[index];
    }
  }
  String? violation() {
    int? referenceDepth;
    String? visit(int page, String location, int depth, int? low, int? high) {
      final node = pages[page]!, count = node.entries.length;
      final minimum = page == root ? (node.leaf ? 0 : 1) : degree - 1;
      final maximum = 2 * degree - 1, at = 'at=$location node=${node.notation}';
      if (count < minimum || count > maximum) {
        return 'COUNT $at keys=$count allowed=$minimum..$maximum';
      }
      for (var i = 0; i + 1 < count; i++) {
        if (node.entries[i].key >= node.entries[i + 1].key) {
          return 'ORDER $at ${node.entries[i].key}>=${node.entries[i + 1].key}';
        }
      }
      for (final entry in node.entries) {
        if ((low != null && entry.key <= low) || (high != null && entry.key >= high)) {
          return 'RANGE $at key=${entry.key} low=${low ?? '-inf'} high=${high ?? '+inf'}';
        }
      }
      if (node.leaf) {
        final expected = referenceDepth;
        if (expected != null && depth != expected) {
          return 'DEPTH $at depth=$depth expected=$expected';
        }
        referenceDepth ??= depth;
      }
      for (var i = 0; i < node.children.length; i++) {
        final problem = visit(node.children[i], '$location.$i', depth + 1,
            i == 0 ? low : node.entries[i - 1].key,
            i == count ? high : node.entries[i].key);
        if (problem != null) return problem;
      }
      return null;
    }
    return visit(root, 'root', 0, null, null);
  }
  static Tree load(int degree, List<String> tokens) {
    final tree = Tree(degree);
    tree.pages.clear();
    var position = 0, nextPage = 0;
    CommandError syntax() => CommandError('SYNTAX ${position + 1}');
    Entry readEntry() {
      if (position == tokens.length || tokens[position] == '(' || tokens[position] == ')') {
        throw syntax();
      }
      final pair = tokens[position++].split('=');
      return (key: int.parse(pair[0]), value: pair[1]);
    }
    int readNode() {
      if (position == tokens.length || tokens[position] != '(') throw syntax();
      position++;
      final page = nextPage++, node = Node();
      tree.pages[page] = node;
      if (position < tokens.length && tokens[position] == '(') {
        node.children.add(readNode());
        while (position == tokens.length || tokens[position] != ')') {
          node.entries.add(readEntry());
          node.children.add(readNode());
        }
      } else {
        while (position == tokens.length || tokens[position] != ')') {
          node.entries.add(readEntry());
        }
      }
      position++;
      return page;
    }
    tree.root = readNode();
    if (position != tokens.length) throw syntax();
    return tree;
  }
  void split(int parentPage, int index, Trace trace) {
    final parent = pages[parentPage]!, childPage = parent.children[index];
    final child = pages[childPage]!, before = child.notation, middle = child.entries[degree - 1];
    final right = Node(child.entries.sublist(degree), child.children.skip(degree).toList());
    final newPage = allocate(right);
    child.entries.removeRange(degree - 1, child.entries.length);
    if (!child.leaf) child.children.removeRange(degree, child.children.length);
    parent.entries.insert(index, middle);
    parent.children.insert(index + 1, newPage);
    splits++;
    trace.emit('STEP split page=$childPage keys=$before up=${middle.key} new=$newPage');
  }
  String? upsert(int key, String value, Trace trace) {
    final found = search(key), existing = found.page;
    if (existing != null) {
      final old = pages[existing]!.entries[found.position];
      pages[existing]!.entries[found.position] = (key: key, value: value);
      return old.value;
    }
    if (pages[root]!.entries.length == 2 * degree - 1) {
      root = allocate(Node([], [root]));
      trace.emit('STEP grow page=$root');
      split(root, 0, trace);
    }
    var page = root;
    while (!pages[page]!.leaf) {
      final node = pages[page]!;
      var index = node.position(key);
      if (pages[node.children[index]]!.entries.length == 2 * degree - 1) {
        split(page, index, trace);
        if (key > node.entries[index].key) index++;
      }
      page = node.children[index];
    }
    final leaf = pages[page]!;
    leaf.entries.insert(leaf.position(key), (key: key, value: value));
    trace.emit('STEP place page=$page keys=${leaf.notation}');
    return null;
  }
  int merge(int parentPage, int index, String caseName, Trace trace) {
    final parent = pages[parentPage]!;
    final leftPage = parent.children[index], rightPage = parent.children[index + 1];
    final left = pages[leftPage]!, right = pages[rightPage]!;
    left.entries.add(parent.entries.removeAt(index));
    left.entries.addAll(right.entries);
    left.children.addAll(right.children);
    parent.children.removeAt(index + 1);
    pages.remove(rightPage);
    merges++;
    trace.emit('STEP $caseName page=$parentPage merge=$leftPage+$rightPage keys=${left.notation}');
    if (parentPage == root && parent.entries.isEmpty) {
      root = leftPage;
      pages.remove(parentPage);
      trace.emit('STEP shrink page=$root');
    }
    return leftPage;
  }
  void removeAt(int page, int key, List<String> cases, Trace trace) {
    final node = pages[page]!, index = node.position(key);
    if (index < node.entries.length && node.entries[index].key == key) {
      if (node.leaf) {
        cases.add('1');
        node.entries.removeAt(index);
        trace.emit('STEP 1 page=$page keys=${node.notation}');
        return;
      }
      final left = node.children[index], right = node.children[index + 1];
      if (pages[left]!.entries.length >= degree) {
        var last = left;
        while (!pages[last]!.leaf) {
          last = pages[last]!.children.last;
        }
        final predecessor = pages[last]!.entries.last;
        cases.add('2a');
        trace.emit('STEP 2a page=$page pred=${predecessor.key}');
        removeAt(left, predecessor.key, cases, trace);
        node.entries[index] = predecessor;
      } else if (pages[right]!.entries.length >= degree) {
        var first = right;
        while (!pages[first]!.leaf) {
          first = pages[first]!.children.first;
        }
        final successor = pages[first]!.entries.first;
        cases.add('2b');
        trace.emit('STEP 2b page=$page succ=${successor.key}');
        removeAt(right, successor.key, cases, trace);
        node.entries[index] = successor;
      } else {
        cases.add('2c');
        final child = merge(page, index, '2c', trace);
        removeAt(child, key, cases, trace);
      }
      return;
    }
    var childPage = node.children[index];
    final child = pages[childPage]!;
    if (child.entries.length == degree - 1) {
      final leftPage = index > 0 ? node.children[index - 1] : null;
      final rightPage = index < node.entries.length ? node.children[index + 1] : null;
      if (leftPage != null && pages[leftPage]!.entries.length >= degree) {
        final sibling = pages[leftPage]!;
        cases.add('3a-left');
        child.entries.insert(0, node.entries[index - 1]);
        node.entries[index - 1] = sibling.entries.removeLast();
        if (!sibling.leaf) child.children.insert(0, sibling.children.removeLast());
        borrows++;
        trace.emit('STEP 3a-left page=$page child=$childPage from=$leftPage keys=${child.notation}');
      } else if (rightPage != null && pages[rightPage]!.entries.length >= degree) {
        final sibling = pages[rightPage]!;
        cases.add('3a-right');
        child.entries.add(node.entries[index]);
        node.entries[index] = sibling.entries.removeAt(0);
        if (!sibling.leaf) child.children.add(sibling.children.removeAt(0));
        borrows++;
        trace.emit('STEP 3a-right page=$page child=$childPage from=$rightPage keys=${child.notation}');
      } else if (leftPage != null) {
        cases.add('3b-left');
        childPage = merge(page, index - 1, '3b-left', trace);
      } else {
        cases.add('3b-right');
        childPage = merge(page, index, '3b-right', trace);
      }
    }
    removeAt(childPage, key, cases, trace);
  }
  List<String> remove(int key, Trace trace) {
    final cases = <String>[];
    removeAt(root, key, cases, trace);
    return cases;
  }
  ({List<Entry> entries, int visited}) scan(int low, int high) {
    final result = <Entry>[];
    var visited = 0;
    void visit(int page) {
      visited++;
      final node = pages[page]!, count = node.entries.length;
      for (var i = 0; i <= count; i++) {
        if (!node.leaf && (i == 0 || node.entries[i - 1].key < high) &&
            (i == count || node.entries[i].key > low)) {
          visit(node.children[i]);
        }
        if (i < count && low <= node.entries[i].key && node.entries[i].key <= high) {
          result.add(node.entries[i]);
        }
      }
    }
    visit(root);
    return (entries: result, visited: visited);
  }
  String dump() {
    final tokens = <String>[];
    void visit(int page) {
      final node = pages[page]!;
      tokens.add('(');
      if (!node.leaf) visit(node.children.first);
      for (var i = 0; i < node.entries.length; i++) {
        tokens.add(display(node.entries[i]));
        if (!node.leaf) visit(node.children[i + 1]);
      }
      tokens.add(')');
    }
    visit(root);
    return tokens.join(' ');
  }
  void compact() {
    var source = entries(), children = <int>[];
    final built = <Node>[];
    int oldRoot;
    while (true) {
      final groups = (source.length + 2 * degree) ~/ (2 * degree);
      final keys = source.length - groups + 1, size = keys ~/ groups, extra = keys % groups;
      var entryIndex = 0, childIndex = 0;
      final nodes = <int>[], separators = <Entry>[];
      for (var group = 0; group < groups; group++) {
        final count = size + (group < extra ? 1 : 0);
        final node = Node(source.sublist(entryIndex, entryIndex + count),
            children.isEmpty ? [] : children.sublist(childIndex, childIndex + count + 1));
        nodes.add(built.length);
        built.add(node);
        entryIndex += count;
        childIndex += count + 1;
        if (group + 1 < groups) separators.add(source[entryIndex++]);
      }
      if (groups == 1) {
        oldRoot = nodes.first;
        break;
      }
      source = separators;
      children = nodes;
    }
    final replacement = <int, Node>{};
    var nextPage = 0;
    int renumber(int oldPage) {
      final page = nextPage++, old = built[oldPage];
      replacement[page] = Node(List.of(old.entries), old.children.map(renumber).toList());
      return page;
    }
    root = renumber(oldRoot);
    pages = replacement;
    splits = merges = borrows = 0;
  }
}

enum CursorKind { unset, key, begin, end }
final class Cursor {
  final CursorKind kind;
  final int key;
  const Cursor(this.kind, [this.key = 0]);
}

final class Workbench {
  Tree? index, saved;
  Cursor cursor = const Cursor(CursorKind.unset);
  bool trace = false;
  static const needsValid = {'INSERT', 'BULKLOAD', 'DELETE', 'DELRANGE', 'RANGE', 'COUNT',
    'MIN', 'MAX', 'FLOOR', 'CEIL', 'RANK', 'SELECT', 'SEEK', 'NEXT', 'PREV', 'HEIGHT', 'COMPACT'};

  static Entry? find(List<Entry> entries, bool Function(Entry) predicate, {bool last = false}) {
    Entry? result;
    for (final entry in entries) {
      if (!predicate(entry)) continue;
      result = entry;
      if (!last) break;
    }
    return result;
  }
  static String summary(String prefix, Tree tree) =>
      '$prefix nodes=${tree.pages.length} keys=${tree.entries().length} ${tree.violation() == null ? 'OK' : 'DAMAGED'}';
  List<String> process(String line) {
    final words = line.split(' '), command = words[0];
    if (command == 'TRACE') {
      trace = words[1] == 'ON';
      return ['TRACE ${words[1]}'];
    }
    final first = words.length > 1 ? int.parse(words[1]) : 0;
    final ranged = const {'DELRANGE', 'RANGE', 'COUNT'}.contains(command);
    final second = ranged ? int.parse(words[2]) : 0;
    if (command == 'CREATE' || command == 'LOAD') {
      if (first < 2 || first > 5) throw CommandError('BAD DEGREE $first');
      final replacement = command == 'CREATE' ? Tree(first) : Tree.load(first, words.sublist(2));
      index = replacement;
      cursor = const Cursor(CursorKind.unset);
      return [command == 'CREATE' ? 'CREATE t=$first' : summary('LOAD t=$first', replacement)];
    }
    var tree = index;
    if (tree == null) throw const CommandError('NO INDEX');
    if (needsValid.contains(command) && tree.violation() != null) {
      throw const CommandError('DAMAGED');
    }
    final entries = tree.entries();
    if (ranged && first > second) throw CommandError('BAD RANGE $first $second');
    if (command == 'SELECT' && (first < 1 || first > entries.length)) {
      throw CommandError('BAD POSITION $first');
    }
    if ((command == 'NEXT' || command == 'PREV') && cursor.kind == CursorKind.unset) {
      throw const CommandError('NO CURSOR');
    }
    if (command == 'RESTORE' && saved == null) throw const CommandError('NO SAVE');
    final output = <String>[], steps = Trace(trace && (command == 'INSERT' || command == 'DELETE'));
    switch (command) {
      case 'INSERT':
        final before = tree.copyPages(), splits = tree.splits;
        final old = tree.upsert(first, words[2], steps), writes = tree.changes(before).writes;
        output.addAll(steps.lines);
        output.add(old == null
            ? 'INSERT $first NEW splits=${tree.splits - splits} height=${tree.height} writes=$writes'
            : 'INSERT $first UPDATED old=$old writes=$writes');
      case 'BULKLOAD':
        final before = tree.copyPages(), splits = tree.splits;
        var inserted = 0, updated = 0;
        for (var i = 1; i < words.length; i += 2) {
          if (tree.upsert(int.parse(words[i]), words[i + 1], steps) == null) {
            inserted++;
          } else {
            updated++;
          }
        }
        output.add('BULKLOAD pairs=${(words.length - 1) ~/ 2} new=$inserted updated=$updated splits=${tree.splits - splits} height=${tree.height} writes=${tree.changes(before).writes}');
      case 'DELETE':
        final found = tree.search(first), page = found.page;
        if (page == null) {
          output.add('DELETE $first NOT FOUND');
        } else {
          final value = tree.pages[page]!.entries[found.position].value, before = tree.copyPages();
          final cases = tree.remove(first, steps), changes = tree.changes(before);
          output.addAll(steps.lines);
          output.add('DELETE $first REMOVED value=$value cases=${cases.join(',')} height=${tree.height} writes=${changes.writes} frees=${changes.frees}');
        }
      case 'DELRANGE':
        final before = tree.copyPages(), merges = tree.merges, borrows = tree.borrows;
        var removed = 0;
        for (final entry in entries) {
          if (first <= entry.key && entry.key <= second) {
            tree.remove(entry.key, steps);
            removed++;
          }
        }
        final changes = tree.changes(before);
        output.add('DELRANGE $first $second removed=$removed merges=${tree.merges - merges} borrows=${tree.borrows - borrows} height=${tree.height} writes=${changes.writes} frees=${changes.frees}');
      case 'GET':
        final found = tree.search(first), page = found.page;
        final result = page == null ? 'NOT FOUND' : 'FOUND value=${tree.pages[page]!.entries[found.position].value}';
        output.add('GET $first $result path=${found.path.join(' -> ')}');
      case 'RANGE':
      case 'COUNT':
        final result = tree.scan(first, second);
        final suffix = command == 'RANGE' ? result.entries.map((entry) => ' ${display(entry)}').join() : '';
        output.add('$command $first $second count=${result.entries.length} visited=${result.visited}$suffix');
      case 'MIN':
      case 'MAX':
        final result = entries.isEmpty ? 'EMPTY' : display(command == 'MIN' ? entries.first : entries.last);
        output.add('$command $result');
      case 'FLOOR':
      case 'CEIL':
        final entry = command == 'FLOOR'
            ? find(entries, (value) => value.key <= first, last: true)
            : find(entries, (value) => value.key >= first);
        output.add('$command $first ${entry == null ? 'NONE' : display(entry)}');
      case 'RANK':
        output.add('RANK $first ${entries.where((entry) => entry.key < first).length}');
      case 'SELECT':
        output.add('SELECT $first ${display(entries[first - 1])}');
      case 'SEEK':
        final entry = find(entries, (value) => value.key >= first);
        cursor = entry == null ? const Cursor(CursorKind.end) : Cursor(CursorKind.key, entry.key);
        output.add('SEEK $first ${entry == null ? 'END' : display(entry)}');
      case 'NEXT':
      case 'PREV':
        Entry? entry;
        if (command == 'NEXT') {
          if (cursor.kind == CursorKind.begin) {
            entry = find(entries, (_) => true);
          } else if (cursor.kind == CursorKind.key) {
            entry = find(entries, (value) => value.key > cursor.key);
          }
        } else {
          if (cursor.kind == CursorKind.end) {
            entry = find(entries, (_) => true, last: true);
          } else if (cursor.kind == CursorKind.key) {
            entry = find(entries, (value) => value.key < cursor.key, last: true);
          }
        }
        cursor = entry == null
            ? Cursor(command == 'NEXT' ? CursorKind.end : CursorKind.begin)
            : Cursor(CursorKind.key, entry.key);
        output.add('$command ${entry == null ? (command == 'NEXT' ? 'END' : 'BEGIN') : display(entry)}');
      case 'PRINT':
        var level = [tree.root], depth = 0;
        while (level.isNotEmpty) {
          output.add('LEVEL $depth ${level.map((page) => tree!.pages[page]!.notation).join(' ')}');
          level = level.expand((page) => tree!.pages[page]!.children).toList();
          depth++;
        }
      case 'PAGES':
        for (final page in tree.pages.keys.toList()..sort()) {
          final node = tree.pages[page]!;
          output.add('PAGE $page ${node.notation} kids=${node.leaf ? '-' : node.children.join(',')}');
        }
      case 'DUMP':
        output.add('DUMP ${tree.degree} ${tree.dump()}');
      case 'HEIGHT':
        output.add('HEIGHT ${tree.height}');
      case 'STATS':
        final leaves = tree.pages.values.where((node) => node.leaf).length;
        final fill = 100 * entries.length ~/ ((2 * tree.degree - 1) * tree.pages.length);
        output.add('STATS t=${tree.degree} nodes=${tree.pages.length} leaves=$leaves keys=${entries.length} fill=$fill% splits=${tree.splits} merges=${tree.merges} borrows=${tree.borrows}');
      case 'VERIFY':
        final problem = tree.violation();
        output.add(problem == null ? 'VERIFY OK' : 'VERIFY FAIL $problem');
      case 'REBUILD':
        tree = Tree(tree.degree);
        for (final entry in entries) {
          tree.upsert(entry.key, entry.value, steps);
        }
        output.add('REBUILD entries=${entries.length} keys=${tree.entries().length} nodes=${tree.pages.length} splits=${tree.splits} height=${tree.height}');
      case 'COMPACT':
        final nodes = tree.pages.length;
        tree.compact();
        output.add('COMPACT nodes=$nodes->${tree.pages.length} height=${tree.height}');
      case 'SAVE':
        saved = tree.copy();
        output.add(summary('SAVE', tree));
      case 'RESTORE':
        tree = saved!.copy();
        output.add(summary('RESTORE', tree));
    }
    index = tree;
    return output;
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!), workbench = Workbench();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      for (final output in workbench.process(line)) {
        stdout.writeln(output);
      }
    } on CommandError catch (error) {
      stdout.writeln('ERROR ${error.message}');
    }
  }
}
