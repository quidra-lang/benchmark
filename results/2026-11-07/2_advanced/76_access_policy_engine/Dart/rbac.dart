part of 'main.dart';

class Constraint {
  final String name;
  final int cardinality;
  final List<String> roles;
  Constraint(this.name, this.cardinality, this.roles);
}

class Assignment {
  final String user, role;
  final int first, last;
  Assignment(this.user, this.role, this.first, this.last);
}

class Permission {
  final String role, action, kind;
  Permission(this.role, this.action, this.kind);
}

class Diagnostic {
  final int line;
  final String keyword, message;
  Diagnostic(this.line, this.keyword, this.message);
}

List<String> sortedSet(Set<String> a) => a.toList()..sort();
List<String> intersection(List<String> roles, Set<String> set) => [
  for (final r in roles)
    if (set.contains(r)) r,
]..sort();

class RBAC {
  final Set<String> roles = {};
  final Map<String, List<String>> edges = {};
  final Map<String, Set<String>> permissions = {};
  final List<Permission> permits = [];
  final List<Constraint> ssd = [], dsd = [];
  final List<Assignment> assignments = [];
  final List<Diagnostic> diagnostics = [];
  Set<String> closure(List<String> roles) {
    final out = <String>{};
    void visit(String role) {
      if (!out.add(role)) return;
      for (final child in edges[role] ?? <String>[]) {
        visit(child);
      }
    }

    for (final role in roles) {
      visit(role);
    }
    return out;
  }

  List<String>? path(String from, String to) {
    final failed = <String>{};
    List<String>? search(String current) {
      if (current == to) return [current];
      if (failed.contains(current)) return null;
      final children = List<String>.of(edges[current] ?? [])..sort();
      for (final child in children) {
        final tail = search(child);
        if (tail != null) return [current, ...tail];
      }
      failed.add(current);
      return null;
    }

    return search(from);
  }

  List<String> assigned(String user, int day) => sortedSet({
    for (final a in assignments)
      if (a.user == user && a.first <= day && day <= a.last) a.role,
  });
  Set<String> authorized(String user, int day) => closure(assigned(user, day));
}

RBAC readRBAC() {
  final r = RBAC(), lines = readLines('input/rbac.txt');
  for (final keyword in [
    'ROLE',
    'INHERITS',
    'PERMIT',
    'SSD',
    'DSD',
    'ASSIGN',
  ]) {
    for (var i = 0; i < lines.length; i++) {
      final a = lines[i].split(' ');
      if (a[0] != keyword) continue;
      var message = '';
      switch (keyword) {
        case 'ROLE':
          if (!r.roles.add(a[1])) {
            message = 'duplicate role ${a[1]}';
          } else {
            r.permissions[a[1]] = {};
          }
          break;
        case 'INHERITS':
          {
            final senior = a[1], junior = a[2];
            if (!r.roles.contains(senior)) {
              message = 'unknown role $senior';
            } else if (!r.roles.contains(junior)) {
              message = 'unknown role $junior';
            } else if ((r.edges[senior] ?? []).contains(junior)) {
              message = 'duplicate inheritance $senior $junior';
            } else {
              final path = r.path(junior, senior);
              if (path != null) {
                message = 'cycle ${[senior, ...path].join(' > ')}';
              } else {
                r.edges.putIfAbsent(senior, () => []).add(junior);
              }
            }
            break;
          }
        case 'PERMIT':
          {
            final key = '${a[2]} ${a[3]}';
            if (!r.roles.contains(a[1])) {
              message = 'unknown role ${a[1]}';
            } else if (!r.permissions[a[1]]!.add(key)) {
              message = 'duplicate permission ${a.skip(1).join(' ')}';
            } else {
              r.permits.add(Permission(a[1], a[2], a[3]));
            }
            break;
          }
        case 'SSD':
        case 'DSD':
          {
            final constraints = keyword == 'SSD' ? r.ssd : r.dsd,
                roles = a[3].split(','),
                cardinality = number(a[2]);
            if (constraints.any((c) => c.name == a[1]))
              message = 'duplicate constraint ${a[1]}';
            if (message.isEmpty) {
              for (final role in roles) {
                if (!r.roles.contains(role)) {
                  message = 'unknown role $role';
                  break;
                }
              }
            }
            if (message.isEmpty &&
                (cardinality < 2 || cardinality > roles.length))
              message = 'bad cardinality ${a[1]} $cardinality';
            if (message.isEmpty)
              constraints.add(Constraint(a[1], cardinality, roles));
            break;
          }
        case 'ASSIGN':
          {
            final user = a[1],
                role = a[2],
                first = number(a[3]),
                last = number(a[4]);
            if (!r.roles.contains(role)) {
              message = 'unknown role $role';
            } else if (!(1 <= first && first <= last && last <= 365)) {
              message = 'bad range $first $last';
            } else {
              for (final c in r.ssd) {
                for (var day = first; day <= last; day++) {
                  final common = intersection(
                    c.roles,
                    r.closure([...r.assigned(user, day), role]),
                  );
                  if (common.length >= c.cardinality) {
                    message =
                        'ssd ${c.name} day $day roles ${common.join(',')}';
                    break;
                  }
                }
                if (message.isNotEmpty) break;
              }
            }
            if (message.isEmpty)
              r.assignments.add(Assignment(user, role, first, last));
            break;
          }
      }
      if (message.isNotEmpty)
        r.diagnostics.add(Diagnostic(i + 1, keyword, message));
    }
  }
  r.diagnostics.sort((a, b) => a.line.compareTo(b.line));
  return r;
}
