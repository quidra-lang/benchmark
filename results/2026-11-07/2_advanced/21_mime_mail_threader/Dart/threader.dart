import 'main.dart' show Message;

class Container {
  final String id;
  Message? message;
  Container? parent;
  List<Container> children = [];
  String? subject;
  Container(this.id);

  bool ancestorOf(Container? other) {
    while (other != null) {
      if (identical(this, other)) return true;
      other = other.parent;
    }
    return false;
  }
}

void adopt(Container parent, Container child) {
  child.parent = parent;
  parent.children.add(child);
}

class Threader {
  final table = <String, Container>{};
  final containers = <Container>[];

  Container containerOf(String id) => table.putIfAbsent(id, () {
    final container = Container(id);
    containers.add(container);
    return container;
  });

  void add(Message message) {
    final container = message.id.isNotEmpty ? containerOf(message.id) : Container('');
    if (message.id.isEmpty) containers.add(container);
    container.message = message;
    final references = message.references.map(containerOf).toList();
    for (var i = 0; i + 1 < references.length; i++) {
      final current = references[i];
      final following = references[i + 1];
      if (following.parent == null && !following.ancestorOf(current)) {
        adopt(current, following);
      }
    }
    if (container.parent != null) {
      container.parent!.children.remove(container);
      container.parent = null;
    }
    if (references.isNotEmpty && !container.ancestorOf(references.last)) {
      adopt(references.last, container);
    }
  }
}

List<Container> prune(List<Container> containers, bool atRoot) {
  final result = <Container>[];
  for (final container in containers) {
    container.children = prune(container.children, false);
    if (container.message != null || atRoot && container.children.length >= 2) {
      result.add(container);
      continue;
    }
    for (final child in container.children) {
      child.parent = atRoot ? null : container.parent;
    }
    result.addAll(container.children);
  }
  return result;
}

int compareMessages(Message a, Message b) {
  if ((a.date == null) != (b.date == null)) return a.date == null ? 1 : -1;
  if (a.date != null && a.date != b.date) return a.date!.compareTo(b.date!);
  final idOrder = a.id.compareTo(b.id);
  return idOrder != 0 ? idOrder : a.number.compareTo(b.number);
}

Message containerKey(Container container) {
  if (container.message != null) return container.message!;
  var best = containerKey(container.children.first);
  for (final child in container.children.skip(1)) {
    final candidate = containerKey(child);
    if (compareMessages(candidate, best) < 0) best = candidate;
  }
  return best;
}

void sortContainers(List<Container> containers) {
  for (final container in containers) {
    sortContainers(container.children);
  }
  containers.sort((a, b) => compareMessages(containerKey(a), containerKey(b)));
}

String rootSubject(Container root) =>
    (root.message ?? root.children.first.message!).baseSubject;

List<Container> mergeBySubject(List<Container> roots) {
  final groups = <String, List<Container>>{};
  for (final root in roots) {
    final subject = rootSubject(root);
    if (subject.isNotEmpty) groups.putIfAbsent(subject, () => []).add(root);
  }
  final merged = roots.where((root) {
    final subject = rootSubject(root);
    return subject.isEmpty || groups[subject]!.length == 1;
  }).toList();
  for (final entry in groups.entries) {
    final group = entry.value;
    if (group.length < 2) continue;
    final missing = group.where((root) => root.message == null).toList();
    final originals = group.where((root) =>
        root.message != null && !root.message!.reply).toList();
    final Container target;
    if (missing.isNotEmpty) {
      target = missing.first;
    } else if (originals.length == 1) {
      target = originals.first;
    } else {
      target = Container('')..subject = entry.key;
    }
    for (final root in group) {
      if (identical(root, target)) continue;
      if (root.message != null) {
        adopt(target, root);
      } else {
        for (final child in root.children) {
          adopt(target, child);
        }
      }
    }
    merged.add(target);
  }
  return merged;
}

List<Container> buildThreads(List<Message> messages) {
  final threader = Threader();
  for (final message in messages) {
    threader.add(message);
  }
  var roots = prune(threader.containers.where((c) => c.parent == null).toList(), true);
  sortContainers(roots);
  roots = mergeBySubject(roots);
  sortContainers(roots);
  return roots;
}
