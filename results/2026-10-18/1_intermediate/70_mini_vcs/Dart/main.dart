import 'dart:io';

typedef Tree = Map<String, String>;

class Commit {
  final String id;
  final int sequence;
  final List<Commit> parents;
  final Tree tree;
  final String message;
  Commit(this.id, this.sequence, List<Commit> parents, Tree tree, this.message)
      : parents = List.of(parents), tree = Map.of(tree);
}

class Operation {
  final String kind;
  final Commit target;
  Operation(this.kind, this.target);
}

class Stash {
  final String label;
  final Commit base;
  final Tree tree;
  Stash(this.label, this.base, this.tree);
}

class MergeResult {
  final Tree tree;
  final List<String> conflicts;
  final Map<String, String> contents;
  MergeResult(this.tree, this.conflicts, this.contents);
}

class VcsError implements Exception {
  final String message;
  VcsError(this.message);
}

List<String> paths(List<Tree> trees) =>
    (trees.expand((tree) => tree.keys).toSet().toList()..sort());
List<String> different(Tree a, Tree b) =>
    paths([a, b]).where((path) => a[path] != b[path]).toList();
bool equal(Tree a, Tree b) => different(a, b).isEmpty;
void match(Tree target, Tree source, String path) {
  if (source.containsKey(path)) {
    target[path] = source[path]!;
  } else {
    target.remove(path);
  }
}
Never fail(String message) => throw VcsError('error: $message');

class Vcs {
  final List<String> output = [];
  final Map<String, Commit> commits = {};
  final Map<String, Commit> branches = {};
  final Map<String, Commit> tags = {};
  final List<Stash> stashes = [];
  final List<String> patterns = [];
  int sequence = 0;
  Tree working = {};
  Tree index = {};
  Set<String> conflicts = {};
  Operation? operation;
  String? branch = 'main';
  late Commit detached;

  Vcs() {
    final root = create([], {}, 'init');
    branches['main'] = root;
    detached = root;
  }

  Commit get head => branch == null ? detached : branches[branch]!;

  Commit create(List<Commit> parents, Tree tree, String message) {
    final s = sequence++;
    final canonical = StringBuffer('commit $s\n');
    for (final parent in parents) {
      canonical.writeln('parent ${parent.id}');
    }
    for (final path in tree.keys.toList()..sort()) {
      canonical.writeln('file $path ${tree[path]}');
    }
    canonical.writeln('message $message');
    var hash = 0;
    for (final code in canonical.toString().codeUnits) {
      hash = (hash * 131 + code) % 2147483647;
    }
    final commit = Commit(hash.toRadixString(16).padLeft(8, '0'), s,
        parents, tree, message);
    commits[commit.id] = commit;
    return commit;
  }

  void move(Commit commit) {
    if (branch == null) {
      detached = commit;
    } else {
      branches[branch!] = commit;
    }
  }

  Commit record(List<Commit> parents, Tree tree, String message) {
    final commit = create(parents, tree, message);
    final old = parents.first.tree;
    var added = 0, modified = 0, deleted = 0;
    for (final path in different(old, tree)) {
      if (!old.containsKey(path)) {
        added++;
      } else if (!tree.containsKey(path)) {
        deleted++;
      } else {
        modified++;
      }
    }
    move(commit);
    output.add('[${branch ?? 'detached HEAD'} ${commit.id}] $message '
        '($added added, $modified modified, $deleted deleted)');
    return commit;
  }

  Commit resolve(String rev) {
    final parts = rev.split('~');
    final anchor = parts.first;
    Commit? commit = anchor == 'HEAD'
        ? head : branches[anchor] ?? tags[anchor] ?? commits[anchor];
    if (commit == null) fail("unknown revision '$rev'");
    final count = parts.length == 1 ? 0 : int.parse(parts[1]);
    for (var i = 0; i < count; i++) {
      if (commit!.parents.isEmpty) fail("unknown revision '$rev'");
      commit = commit.parents.first;
    }
    return commit!;
  }

  Map<Commit, int> distances(Commit start) {
    final result = <Commit, int>{start: 0};
    final queue = <Commit>[start];
    for (var i = 0; i < queue.length; i++) {
      final commit = queue[i];
      for (final parent in commit.parents) {
        if (!result.containsKey(parent)) {
          result[parent] = result[commit]! + 1;
          queue.add(parent);
        }
      }
    }
    return result;
  }

  bool ancestor(Commit a, Commit b) => distances(b).containsKey(a);

  Commit mergeBase(Commit a, Commit b) {
    final da = distances(a), db = distances(b);
    final common = da.keys.where(db.containsKey).toList();
    final candidates = common.where((commit) => !common.any((other) =>
        other != commit && ancestor(commit, other))).toList();
    int rank(Commit commit) => da[commit]! > db[commit]!
        ? da[commit]! : db[commit]!;
    candidates.sort((x, y) {
      final order = rank(x).compareTo(rank(y));
      return order != 0 ? order : y.sequence.compareTo(x.sequence);
    });
    return candidates.first;
  }

  String summary(Commit commit) {
    final refs = <String>[];
    if (head == commit) refs.add(branch == null ? 'HEAD' : 'HEAD -> $branch');
    for (final name in branches.keys.toList()..sort()) {
      if (name != branch && branches[name] == commit) refs.add(name);
    }
    for (final name in tags.keys.toList()..sort()) {
      if (tags[name] == commit) refs.add('tag: $name');
    }
    return '${commit.id}${refs.isEmpty ? '' : ' (${refs.join(', ')})'} ${commit.message}';
  }

  void changes(Tree a, Tree b) {
    final changed = different(a, b);
    if (changed.isEmpty) output.add('(no changes)');
    for (final path in changed) {
      if (!a.containsKey(path)) {
        output.add('A $path: ${b[path]}');
      } else if (!b.containsKey(path)) {
        output.add('D $path: ${a[path]}');
      } else {
        output.add('M $path: ${a[path]} -> ${b[path]}');
      }
    }
  }

  void inProgress() {
    if (operation != null) fail('${operation!.kind} in progress');
  }
  bool get dirty => !equal(index, head.tree) ||
      index.keys.any((path) => working[path] != index[path]);
  void uncommitted() {
    if (dirty) fail('uncommitted changes');
  }
  void overwrite(Iterable<String> check) {
    final h = head.tree;
    for (final path in check.toSet().toList()..sort()) {
      if (index[path] != h[path] || working[path] != h[path]) {
        fail("local changes to '$path' would be overwritten");
      }
    }
  }
  void switchTree(Tree tree) {
    final changed = different(head.tree, tree);
    overwrite(changed);
    for (final path in changed) {
      match(index, tree, path);
      match(working, tree, path);
    }
  }

  MergeResult merge(Tree base, Tree ours, Tree theirs) {
    final tree = <String, String>{};
    final found = <String>[];
    final contents = <String, String>{};
    for (final path in paths([base, ours, theirs])) {
      final b = base[path], o = ours[path], t = theirs[path];
      if (t == b || o == t) {
        match(tree, ours, path);
      } else if (o == b) {
        match(tree, theirs, path);
      } else {
        found.add(path);
        match(tree, ours, path);
        contents[path] = '<<<<<<< ${o ?? '(deleted)'} ======= ${t ?? '(deleted)'} >>>>>>>';
      }
    }
    return MergeResult(tree, found, contents);
  }

  void apply(Tree base, Tree theirs, String kind, Commit target,
      String message, List<Commit> parents, [Commit? mergeCommit]) {
    final result = merge(base, head.tree, theirs);
    final changed = different(head.tree, result.tree);
    overwrite([...changed, ...result.conflicts]);
    if (kind == 'merge') output.add('Merge base ${mergeCommit!.id}');
    if (kind != 'merge' && result.conflicts.isEmpty && changed.isEmpty) {
      output.add('nothing to commit');
      return;
    }
    for (final path in changed) {
      match(index, result.tree, path);
      match(working, result.tree, path);
    }
    if (result.conflicts.isEmpty) {
      record(parents, result.tree, message);
      return;
    }
    for (final path in result.conflicts) {
      working[path] = result.contents[path]!;
      output.add('CONFLICT $path');
    }
    conflicts = result.conflicts.toSet();
    operation = Operation(kind, target);
    output.add(kind == 'merge'
        ? 'Automatic merge failed; fix conflicts and then commit the result.'
        : kind == 'revert' ? 'error: could not revert ${target.id}'
        : 'error: could not apply ${target.id}');
  }

  bool glob(String pattern, String path) {
    var row = List<bool>.filled(path.length + 1, false);
    row[0] = true;
    for (final code in pattern.codeUnits) {
      final next = List<bool>.filled(path.length + 1, false);
      if (code == 42) next[0] = row[0];
      for (var i = 1; i <= path.length; i++) {
        next[i] = code == 42 ? row[i] || next[i - 1]
            : row[i - 1] && (code == 63 || code == path.codeUnitAt(i - 1));
      }
      row = next;
    }
    return row[path.length];
  }
  bool ignored(String path) => !index.containsKey(path) &&
      !conflicts.contains(path) && patterns.any((pattern) => glob(pattern, path));
  Never pathspec(String path) => fail("pathspec '$path' did not match any files");
  String existingPath(Tree tree, String path, String rev) {
    if (!tree.containsKey(path)) fail("path '$path' does not exist in '$rev'");
    return tree[path]!;
  }
  Set<Commit> reachable(Iterable<Commit> roots) {
    final result = <Commit>{};
    for (final commit in roots) {
      result.addAll(distances(commit).keys);
    }
    return result;
  }

  void execute(String line) {
    final words = line.split(' '), command = words.first;
    final arg = words.length > 1 ? words[1] : '';
    switch (command) {
      case 'WRITE':
        working[arg] = line.substring(line.indexOf(' ', 6) + 1);
      case 'REMOVE':
        if (!working.containsKey(arg)) fail("no such file '$arg'");
        working.remove(arg);
      case 'ADD':
        if (arg == 'ALL') {
          final selected = paths([working, index]).where((path) => !ignored(path)).toList();
          for (final path in selected) {
            match(index, working, path);
          }
          conflicts.clear();
        } else {
          if (working.containsKey(arg) && ignored(arg)) fail("path '$arg' is ignored");
          if (!working.containsKey(arg) && !index.containsKey(arg) && !conflicts.contains(arg)) pathspec(arg);
          match(index, working, arg);
          conflicts.remove(arg);
        }
      case 'RM':
        if (!index.containsKey(arg)) pathspec(arg);
        index.remove(arg);
        working.remove(arg);
        conflicts.remove(arg);
      case 'UNSTAGE':
        if (!index.containsKey(arg) && !head.tree.containsKey(arg)) pathspec(arg);
        match(index, head.tree, arg);
      case 'RESTORE':
        if (words.length == 2) {
          if (!index.containsKey(arg)) pathspec(arg);
          working[arg] = index[arg]!;
        } else {
          final tree = resolve(words[2]).tree;
          final value = existingPath(tree, arg, words[2]);
          index[arg] = value;
          working[arg] = value;
          conflicts.remove(arg);
        }
      case 'IGNORE':
        patterns.add(arg);
      case 'COMMIT':
        if (conflicts.isNotEmpty) fail('unresolved conflicts');
        final parents = operation?.kind == 'merge' ? [head, operation!.target] : [head];
        if (parents.length == 1 && equal(index, head.tree)) {
          output.add('nothing to commit');
        } else {
          record(parents, index, line.substring(7));
          operation = null;
        }
      case 'AMEND':
        inProgress();
        if (head.parents.isEmpty) fail('cannot amend the root commit');
        record(head.parents, index, line.substring(6));
      case 'STATUS':
        output.add(branch == null ? 'HEAD detached at ${head.id}' : 'On branch $branch');
        if (operation != null) {
          final verb = operation!.kind == 'merge' ? 'Merging'
              : operation!.kind == 'revert' ? 'Reverting' : 'Cherry-picking';
          output.add('$verb ${operation!.target.id}');
        }
        final before = output.length;
        final all = {...paths([head.tree, index, working]), ...conflicts}.toList()..sort();
        for (final path in all) {
          if (conflicts.contains(path)) {
            output.add('UU $path');
          } else if (index.containsKey(path)) {
            final x = !head.tree.containsKey(path) ? 'A'
                : head.tree[path] != index[path] ? 'M' : '.';
            final y = !working.containsKey(path) ? 'D'
                : working[path] != index[path] ? 'M' : '.';
            if (x != '.' || y != '.') output.add('$x$y $path');
          } else {
            if (head.tree.containsKey(path)) output.add('D. $path');
            if (working.containsKey(path) && !ignored(path)) output.add('?? $path');
          }
        }
        if (output.length == before) output.add('nothing to commit, working tree clean');
      case 'LS':
        final tree = arg.isEmpty ? working : resolve(arg).tree;
        if (tree.isEmpty) output.add('(empty)');
        for (final path in tree.keys.toList()..sort()) {
          output.add('$path ${tree[path]}');
        }
      case 'CAT':
        if (words.length == 3) {
          output.add(existingPath(resolve(words[2]).tree, arg, words[2]));
        } else {
          if (!working.containsKey(arg)) fail("no such file '$arg'");
          output.add(working[arg]!);
        }
      case 'DIFF':
        if (arg == 'STAGED') {
          changes(head.tree, index);
        } else if (arg.isNotEmpty) {
          final a = resolve(arg), b = resolve(words[2]);
          changes(a.tree, b.tree);
        } else {
          changes(index, Map.fromEntries(working.entries.where((entry) => index.containsKey(entry.key))));
        }
      case 'LOG':
        var current = head, i = 0;
        while (true) {
          output.add(summary(current));
          i++;
          if (current.parents.isEmpty || (arg.isNotEmpty && i == int.parse(arg))) break;
          current = current.parents.first;
        }
      case 'SHOW':
        final commit = resolve(arg.isEmpty ? 'HEAD' : arg);
        output.add('commit ${summary(commit)}');
        output.add('parents: ${commit.parents.isEmpty ? 'none' : commit.parents.map((parent) => parent.id).join(' ')}');
        changes(commit.parents.isEmpty ? {} : commit.parents.first.tree, commit.tree);
      case 'BLAME':
        final value = existingPath(head.tree, arg, 'HEAD');
        var commit = head;
        while (commit.parents.isNotEmpty && commit.parents.first.tree[arg] == value) {
          commit = commit.parents.first;
        }
        output.add('${commit.id} (${commit.message}) $value');
      case 'BRANCH':
      case 'TAG':
        final refs = command == 'BRANCH' ? branches : tags;
        final noun = command == 'BRANCH' ? 'branch' : 'tag';
        if (arg == '-d') {
          final name = words[2], commit = refs[words[2]];
          if (commit == null) fail("no such $noun '$name'");
          if (command == 'BRANCH') {
            if (branch == name) fail("cannot delete current branch '$name'");
            if (!ancestor(commit, head)) fail("branch '$name' is not fully merged");
          }
          refs.remove(name);
          output.add('Deleted $noun $name (was ${commit.id})');
        } else {
          if (refs.containsKey(arg)) fail("$noun '$arg' already exists");
          final commit = resolve(words.length > 2 ? words[2] : 'HEAD');
          refs[arg] = commit;
          output.add('Created $noun $arg at ${commit.id}');
        }
      case 'BRANCHES':
        if (branch == null) output.add('* (HEAD detached at ${head.id})');
        for (final name in branches.keys.toList()..sort()) {
          final commit = branches[name]!;
          output.add('${branch == name ? '*' : ' '} $name ${commit.id} ${commit.message}');
        }
      case 'TAGS':
        if (tags.isEmpty) output.add('(no tags)');
        for (final name in tags.keys.toList()..sort()) {
          final commit = tags[name]!;
          output.add('$name ${commit.id} ${commit.message}');
        }
      case 'SWITCH':
        final commit = branches[arg];
        if (commit == null) fail("no such branch '$arg'");
        if (branch == arg) {
          output.add("Already on '$arg'");
        } else {
          inProgress();
          switchTree(commit.tree);
          branch = arg;
          output.add("Switched to branch '$arg'");
        }
      case 'DETACH':
        final commit = resolve(arg);
        inProgress();
        switchTree(commit.tree);
        branch = null;
        detached = commit;
        output.add('HEAD is now at ${commit.id} ${commit.message}');
      case 'MERGE':
        final target = resolve(arg);
        inProgress();
        final old = head;
        if (ancestor(target, old)) {
          output.add('Already up to date');
        } else if (ancestor(old, target)) {
          switchTree(target.tree);
          move(target);
          output.add('Fast-forward ${old.id}..${target.id}');
        } else {
          uncommitted();
          final base = mergeBase(old, target);
          apply(base.tree, target.tree, 'merge', target, 'Merge $arg', [old, target], base);
        }
      case 'MERGEBASE':
        final a = resolve(arg), b = resolve(words[2]);
        output.add(mergeBase(a, b).id);
      case 'REBASE':
        final onto = resolve(arg);
        inProgress();
        if (ancestor(onto, head)) {
          output.add('Already up to date');
        } else {
          uncommitted();
          final list = <Commit>[];
          var current = head;
          while (!ancestor(current, onto)) {
            list.add(current);
            current = current.parents.first;
          }
          final ordered = list.reversed.toList();
          final picks = <Commit, Tree>{};
          var tree = onto.tree;
          for (final commit in ordered) {
            final result = merge(commit.parents.first.tree, tree, commit.tree);
            if (result.conflicts.isNotEmpty) {
              fail("could not rebase ${commit.id}: conflict in '${result.conflicts.first}'");
            }
            if (!equal(result.tree, tree)) {
              picks[commit] = result.tree;
              tree = result.tree;
            }
          }
          switchTree(tree);
          var target = onto;
          for (final commit in ordered) {
            if (picks.containsKey(commit)) {
              final next = create([target], picks[commit]!, commit.message);
              output.add('pick ${commit.id} -> ${next.id} ${commit.message}');
              target = next;
            } else {
              output.add('skip ${commit.id} ${commit.message}');
            }
          }
          move(target);
          output.add('HEAD is now at ${target.id} ${target.message}');
        }
      case 'RESET':
        final target = resolve(words[2]), tree = target.tree;
        if (arg == 'HARD') {
          final all = {...paths([index, tree]), ...conflicts};
          for (final path in all) {
            match(working, tree, path);
          }
        }
        if (arg != 'SOFT') index = Map.of(tree);
        move(target);
        conflicts.clear();
        operation = null;
        output.add('HEAD is now at ${target.id} ${target.message}');
      case 'REVERT':
      case 'CHERRYPICK':
        final target = resolve(arg);
        inProgress();
        uncommitted();
        final parentTree = target.parents.isEmpty ? <String, String>{} : target.parents.first.tree;
        if (command == 'REVERT') {
          apply(target.tree, parentTree, 'revert', target, 'Revert "${target.message}"', [head]);
        } else {
          apply(parentTree, target.tree, 'cherry-pick', target, target.message, [head]);
        }
      case 'STASH':
        if (arg == 'LIST') {
          if (stashes.isEmpty) output.add('(no stash entries)');
          for (var i = 0; i < stashes.length; i++) {
            output.add('stash@{$i}: ${stashes[i].label}');
          }
        } else if (arg == 'DROP') {
          if (stashes.isEmpty) fail('no stash entries');
          output.add('Dropped stash@{0}: ${stashes.removeAt(0).label}');
        } else if (arg == 'POP') {
          if (stashes.isEmpty) fail('no stash entries');
          inProgress();
          uncommitted();
          final stash = stashes.first;
          final result = merge(stash.base.tree, head.tree, stash.tree);
          if (result.conflicts.isNotEmpty) fail("stash conflict in '${result.conflicts.first}'");
          final changed = different(head.tree, result.tree);
          overwrite(changed);
          for (final path in changed) {
            match(working, result.tree, path);
          }
          stashes.removeAt(0);
          output.add('Restored stash@{0}: ${stash.label}');
          changes(head.tree, result.tree);
        } else {
          inProgress();
          if (!dirty) {
            output.add('No local changes to save');
          } else {
            final tree = <String, String>{}, h = head;
            for (final path in paths([index, h.tree])) {
              if (working.containsKey(path)) tree[path] = working[path]!;
              match(working, h.tree, path);
            }
            index = Map.of(h.tree);
            final label = 'WIP on ${branch ?? '(no branch)'}: ${h.id} ${h.message}';
            stashes.insert(0, Stash(label, h, tree));
            output.add('Saved stash@{0}: $label');
          }
        }
      case 'GRAPH':
        final all = reachable([head, ...branches.values, ...tags.values]).toList()
          ..sort((a, b) => b.sequence.compareTo(a.sequence));
        var lanes = <Commit>[];
        for (final commit in all) {
          if (!lanes.contains(commit)) lanes.add(commit);
          final k = lanes.indexOf(commit);
          final symbols = <String>[];
          for (var i = 0; i < lanes.length; i++) {
            symbols.add(i == k ? '*' : lanes[i] == commit ? '/' : '|');
          }
          output.add('${symbols.join(' ')} ${summary(commit)}');
          lanes = [for (var i = 0; i < lanes.length; i++) if (lanes[i] != commit || i == k) lanes[i]];
          if (commit.parents.isEmpty) {
            lanes.removeAt(k);
          } else {
            lanes[k] = commit.parents.first;
            if (commit.parents.length == 2 && !lanes.contains(commit.parents[1])) {
              lanes.insert(k + 1, commit.parents[1]);
            }
          }
        }
      case 'DESCRIBE':
        final target = resolve(arg.isEmpty ? 'HEAD' : arg), distance = distances(target);
        final names = tags.keys.where((name) => distance.containsKey(tags[name])).toList();
        names.sort((a, b) {
          final order = distance[tags[a]]!.compareTo(distance[tags[b]]!);
          return order == 0 ? a.compareTo(b) : order;
        });
        if (names.isEmpty) fail("no tag can describe '${target.id}'");
        final name = names.first, d = distance[tags[name]]!;
        output.add(d == 0 ? name : '$name-$d-g${target.id}');
      case 'GC':
        final roots = [head, ...branches.values, ...tags.values, ...stashes.map((stash) => stash.base)];
        if (operation != null) roots.add(operation!.target);
        final keep = reachable(roots);
        final before = commits.length;
        commits.removeWhere((id, commit) => !keep.contains(commit));
        output.add('Removed unreachable commits: ${before - commits.length}');
    }
  }
}

void main() {
  final vcs = Vcs();
  String? line;
  while ((line = stdin.readLineSync()) != null && line != 'EXIT') {
    try {
      vcs.execute(line!);
    } on VcsError catch (error) {
      vcs.output.add(error.message);
    }
  }
  if (vcs.output.isNotEmpty) stdout.write('${vcs.output.join('\n')}\n');
}
