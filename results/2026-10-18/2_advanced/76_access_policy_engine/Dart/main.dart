import 'dart:io';
part 'rbac.dart';
part 'policy_parser.dart';
part 'expressions.dart';
part 'combining.dart';
part 'analysis.dart';

class Value {
  final String kind, text;
  final int integer;
  final bool boolean;
  final List<String> bag;
  Value.integer(this.integer)
    : kind = 'integer',
      text = '',
      boolean = false,
      bag = const [];
  Value.string(this.text)
    : kind = 'string',
      integer = 0,
      boolean = false,
      bag = const [];
  Value.boolean(this.boolean)
    : kind = 'boolean',
      integer = 0,
      text = '',
      bag = const [];
  Value.bag(this.bag) : kind = 'bag', integer = 0, text = '', boolean = false;
  Value.error(this.text)
    : kind = 'error',
      integer = 0,
      boolean = false,
      bag = const [];
  String notation() => switch (kind) {
    'integer' => '$integer',
    'boolean' => '$boolean',
    'bag' => '[${bag.map((s) => '"$s"').join(',')}]',
    _ => '"$text"',
  };
}

Value parseValue(String s) {
  if (s == 'true' || s == 'false') return Value.boolean(s == 'true');
  if (s.startsWith('['))
    return Value.bag(
      s.length == 2 ? [] : s.substring(1, s.length - 1).split(','),
    );
  if (s.startsWith('-') || digit(s[0])) return Value.integer(number(s));
  return Value.string(s);
}

int number(String s) => int.parse(s);
List<String> readLines(String path) => File(path).readAsLinesSync();
Value evaluateExpr(Expr e, Map<String, Value> attributes, [String it = '']) {
  switch (e.op) {
    case 'literal':
      return e.value!;
    case 'it':
      return Value.string(it);
    case 'attribute':
      return attributes[e.name] ?? Value.error('missing ${e.name}');
    case 'present':
      return Value.boolean(attributes.containsKey(e.args[0].name));
    case 'any_of':
    case 'all_of':
      final x = evaluateExpr(e.args[0], attributes, it);
      if (x.kind == 'error') return x;
      if (x.kind != 'bag') return Value.error('type ${e.op}');
      var firstError = '', found = false;
      final any = e.op == 'any_of';
      for (final item in x.bag) {
        var v = evaluateExpr(e.args[1], attributes, item);
        if (v.kind != 'error' && v.kind != 'boolean')
          v = Value.error('type ${e.op}');
        if (v.kind == 'boolean' && v.boolean == any) found = true;
        if (v.kind == 'error' && firstError.isEmpty) firstError = v.text;
      }
      if (found) return Value.boolean(any);
      if (firstError.isNotEmpty) return Value.error(firstError);
      return Value.boolean(!any);
  }
  final values = [for (final arg in e.args) evaluateExpr(arg, attributes, it)];
  if (e.op == 'and' || e.op == 'or') {
    for (var i = 0; i < values.length; i++) {
      if (values[i].kind != 'boolean' && values[i].kind != 'error')
        values[i] = Value.error('type ${e.op}');
    }
    final winning = e.op == 'or';
    for (final v in values) {
      if (v.kind == 'boolean' && v.boolean == winning)
        return Value.boolean(winning);
    }
    for (final v in values) {
      if (v.kind == 'error') return v;
    }
    return Value.boolean(!winning);
  }
  for (final v in values) {
    if (v.kind == 'error') return v;
  }
  final a = values[0];
  if (values.length == 1) {
    switch (e.op) {
      case 'not':
        if (a.kind == 'boolean') return Value.boolean(!a.boolean);
        break;
      case '-':
        if (a.kind == 'integer') return Value.integer(-a.integer);
        break;
      case 'size':
        if (a.kind == 'bag') return Value.integer(a.bag.length);
        break;
    }
    return Value.error('type ${e.op}');
  }
  final b = values[1];
  switch (e.op) {
    case '+':
    case '-':
    case '*':
      if (a.kind == 'integer' && b.kind == 'integer') {
        return Value.integer(switch (e.op) {
          '+' => a.integer + b.integer,
          '-' => a.integer - b.integer,
          _ => a.integer * b.integer,
        });
      }
      break;
    case 'starts_with':
      if (a.kind == 'string' && b.kind == 'string')
        return Value.boolean(a.text.startsWith(b.text));
      break;
    case 'in':
      if (a.kind == 'string' && b.kind == 'bag')
        return Value.boolean(b.bag.contains(a.text));
      break;
    default:
      return compareValues(e.op, a, b);
  }
  return Value.error('type ${e.op}');
}

Value compareValues(String op, Value a, Value b) {
  if (op == '==' || op == '!=') {
    if (a.kind != b.kind || a.kind == 'bag') return Value.error('type $op');
    final equal = switch (a.kind) {
      'integer' => a.integer == b.integer,
      'string' => a.text == b.text,
      'boolean' => a.boolean == b.boolean,
      _ => false,
    };
    return Value.boolean(op == '!=' ? !equal : equal);
  }
  if (op == '^=') {
    return a.kind == 'string' && b.kind == 'string'
        ? Value.boolean(a.text.startsWith(b.text))
        : Value.error('type $op');
  }
  if (a.kind != 'integer' || b.kind != 'integer')
    return Value.error('type $op');
  return Value.boolean(switch (op) {
    '<' => a.integer < b.integer,
    '<=' => a.integer <= b.integer,
    '>' => a.integer > b.integer,
    _ => a.integer >= b.integer,
  });
}

TargetResult mergeTargets(List<TargetResult> values, bool conjunction) {
  final winning = conjunction ? 'NO_MATCH' : 'MATCH',
      fallback = conjunction ? 'MATCH' : 'NO_MATCH';
  var reason = '', found = false;
  for (final v in values) {
    if (v.state == winning) found = true;
    if (v.state == 'INDETERMINATE' && reason.isEmpty) reason = v.reason;
  }
  if (found) return TargetResult(winning);
  if (reason.isNotEmpty) return TargetResult('INDETERMINATE', reason);
  return TargetResult(fallback);
}

TargetResult evaluateTarget(Element e, Map<String, Value> attributes) {
  final lines = <TargetResult>[];
  for (final line in e.targets) {
    final alternatives = <TargetResult>[];
    for (final alt in line) {
      final clauses = <TargetResult>[];
      for (final c in alt) {
        final v = attributes[c.attribute], items = <Value>[];
        if (v != null) {
          if (v.kind == 'bag') {
            items.addAll(v.bag.map(Value.string));
          } else {
            items.add(v);
          }
        }
        var matched = false, reason = '';
        for (final item in items) {
          final test = compareValues(c.operator, item, c.literal);
          if (test.kind == 'boolean' && test.boolean) matched = true;
          if (test.kind == 'error' && reason.isEmpty) reason = test.text;
        }
        var result = TargetResult('NO_MATCH');
        if (matched) {
          result = TargetResult('MATCH');
        } else if (reason.isNotEmpty) {
          result = TargetResult('INDETERMINATE', reason);
        } else if (v == null && c.mandatory) {
          result = TargetResult('INDETERMINATE', 'missing ${c.attribute}');
        }
        clauses.add(result);
      }
      alternatives.add(mergeTargets(clauses, true));
    }
    lines.add(mergeTargets(alternatives, false));
  }
  return mergeTargets(lines, true);
}

class Evaluation {
  final Element element;
  final TargetResult target;
  String condition = '', decision = na, reason = '', decisive = '';
  List<ChildState> children = [];
  final List<String> obligations = [], advice = [];
  Evaluation(this.element, this.target);
  String notation() =>
      indeterminate(decision) ? '$decision ($reason)' : decision;
}

String effectError(String effect) => effect == 'DENY' ? id : ip;
Evaluation ruleResult(Element e, Map<String, Value> attributes) {
  final r = Evaluation(e, evaluateTarget(e, attributes));
  if (r.target.state == 'NO_MATCH') return r;
  if (r.target.state == 'INDETERMINATE') {
    r.decision = effectError(e.effect);
    r.reason = r.target.reason;
    return r;
  }
  var c = e.condition == null
      ? Value.boolean(true)
      : evaluateExpr(e.condition!, attributes);
  if (c.kind != 'boolean' && c.kind != 'error')
    c = Value.error('type condition');
  r.condition = 'FALSE';
  if (c.kind == 'error') {
    r.condition = 'INDETERMINATE';
    r.decision = effectError(e.effect);
    r.reason = c.text;
  } else if (c.boolean) {
    r.condition = 'TRUE';
    r.decision = e.effect;
    r.decisive = e.id;
  }
  return r;
}

void attachments(Evaluation r, Map<String, Value> attributes) {
  if (!definite(r.decision)) return;
  for (final kind in ['obligation', 'advice']) {
    for (final a in r.element.attachments) {
      if (a.kind != kind || a.effect != r.decision) continue;
      var text = a.id, reason = '';
      for (final arg in a.args) {
        final v = evaluateExpr(arg.expression, attributes);
        if (v.kind == 'error' && reason.isEmpty) reason = v.text;
        text += ' ${arg.name}=${v.notation()}';
      }
      if (reason.isNotEmpty) {
        if (kind == 'obligation') {
          r.decision = effectError(r.decision);
          r.reason = 'obligation ${a.id}: $reason';
          r.decisive = '';
          r.obligations.clear();
          r.advice.clear();
          return;
        }
        continue;
      }
      if (kind == 'obligation') {
        r.obligations.add(text);
      } else {
        r.advice.add(text);
      }
    }
  }
}

Evaluation evaluate(
  Element e,
  Map<String, Value> attributes, [
  Map<Element, String>? coverage,
]) {
  if (e.kind == 'rule') {
    final r = ruleResult(e, attributes);
    attachments(r, attributes);
    if (coverage != null)
      coverage[e] = switch (r.decision) {
        'PERMIT' => 'P',
        'DENY' => 'D',
        na => '-',
        _ => 'I',
      };
    return r;
  }
  final r = Evaluation(e, evaluateTarget(e, attributes));
  if (r.target.state == 'NO_MATCH') return r;
  final (d, reason, children) = combine(
    e.algorithm,
    e.children,
    (child) => evaluate(child, attributes, coverage),
    (child) => evaluateTarget(child, attributes),
  );
  r.decision = d;
  r.reason = reason;
  r.children = children;
  if (r.target.state == 'INDETERMINATE') {
    if (definite(r.decision)) r.decision = effectError(r.decision);
    if (indeterminate(r.decision)) r.reason = r.target.reason;
  }
  if (definite(r.decision)) {
    r.decisive = e.id;
    var first = true;
    for (final state in r.children) {
      final child = state.result;
      if (child != null && child.decision == r.decision) {
        if (first) {
          r.decisive = child.decisive;
          first = false;
        }
        r.obligations.addAll(child.obligations);
        r.advice.addAll(child.advice);
      }
    }
    attachments(r, attributes);
  }
  return r;
}

List<String> treeLines(Evaluation r, int depth) {
  final indent = ' ' * (2 + 2 * depth), e = r.element;
  var text = '$indent${e.kind} ${e.id} ';
  if (e.kind == 'rule') {
    text += '${e.effect} target ${r.target.state}';
    if (r.target.state == 'MATCH') text += ' condition ${r.condition}';
  } else {
    text += '${e.algorithm} target ${r.target.state}';
  }
  final out = ['$text -> ${r.notation()}'];
  if (e.kind != 'rule' && r.target.state != 'NO_MATCH') {
    for (var i = 0; i < e.children.length; i++) {
      final child = e.children[i], state = r.children[i], result = state.result;
      if (result != null) {
        out.addAll(treeLines(result, depth + 1));
      } else {
        var line = '$indent  ${child.kind} ${child.id}';
        final target = state.target;
        if (target != null) {
          line += ' ${child.algorithm} target ${target.state}';
          if (target.state == 'INDETERMINATE') line += ' (${target.reason})';
        } else {
          line += ' skipped';
        }
        out.add(line);
      }
    }
  }
  return out;
}

class Resource {
  final String kind;
  final Map<String, Value> attributes;
  Resource(this.kind, this.attributes);
}

class Request {
  final String id, user, roles, action, resource;
  final Map<String, Value> environment;
  final bool explain;
  Request(
    this.id,
    this.user,
    this.roles,
    this.action,
    this.resource,
    this.environment, [
    this.explain = false,
  ]);
}

class Activation {
  final String role, reason;
  Activation(this.role, this.reason);
}

class Answer {
  final Request request;
  String error = '', kind = '', grant = '';
  int day = 0;
  final List<Activation> activations = [];
  List<String> roles = [];
  Evaluation? result;
  final Map<Element, String> coverage = {};
  Answer(this.request);
  String decisionText() {
    final r = result!;
    return definite(r.decision)
        ? '${r.notation()} by ${r.decisive}'
        : r.notation();
  }
}

Map<String, Value> parseAttributes(List<String> parts) => {
  for (final part in parts)
    part.substring(0, part.indexOf('=')): parseValue(
      part.substring(part.indexOf('=') + 1),
    ),
};
List<String> stringKeys<T>(Map<String, T> a) => a.keys.toList()..sort();

class Conflict {
  final Element policy, a, b, winner;
  int count = 0;
  Conflict(this.policy, this.a, this.b, this.winner);
}

class Engine {
  final RBAC rbac;
  final Element root;
  final List<Element> elements, rules;
  final Map<String, Map<String, Value>> subjects = {};
  final Map<String, Resource> resources = {};
  final List<Domain> domains = [];
  Map<String, Value> reference = {};
  final List<Request> requests = [];
  final List<Answer> answers = [];
  Engine(this.rbac, this.root, this.elements, this.rules);
  void readInputs() {
    for (final line in readLines('input/attributes.txt')) {
      final a = line.split(' ');
      switch (a[0]) {
        case 'SUBJECT':
          subjects[a[1]] = parseAttributes(a.sublist(2));
          break;
        case 'RESOURCE':
          resources[a[1]] = Resource(a[2], parseAttributes(a.sublist(3)));
          break;
        case 'DOMAIN':
          domains.add(Domain(a[1], [for (final s in a.skip(2)) parseValue(s)]));
          break;
        case 'REFERENCE':
          reference = parseAttributes(a.sublist(1));
          break;
      }
    }
    for (final line in readLines('input/requests.txt')) {
      final a = line.split(' '), explain = a.last == 'EXPLAIN';
      if (explain) a.removeLast();
      requests.add(
        Request(
          a[0],
          a[1],
          a[2],
          a[3],
          a[4],
          parseAttributes(a.sublist(5)),
          explain,
        ),
      );
    }
  }

  Answer answer(Request request, bool record) {
    final a = Answer(request);
    if (record) {
      for (final rule in rules) {
        a.coverage[rule] = '.';
      }
    }
    final subject = subjects[request.user];
    if (subject == null) {
      a.error = 'unknown user ${request.user}';
      return a;
    }
    final resource = resources[request.resource];
    if (resource == null) {
      a.error = 'unknown resource ${request.resource}';
      return a;
    }
    final day = request.environment['day'];
    if (day == null ||
        day.kind != 'integer' ||
        day.integer < 1 ||
        day.integer > 365) {
      a.error = 'bad day';
      return a;
    }
    a.day = day.integer;
    a.kind = resource.kind;
    final authorized = rbac.authorized(request.user, a.day),
        candidates = switch (request.roles) {
          '-' => <String>[],
          '*' => sortedSet(authorized),
          _ => request.roles.split(','),
        },
        seen = <String>{},
        active = <String>[];
    for (final candidate in candidates) {
      var reason = '';
      if (!rbac.roles.contains(candidate)) {
        reason = 'unknown';
      } else if (seen.contains(candidate)) {
        reason = 'duplicate';
      } else if (!authorized.contains(candidate)) {
        reason = 'unauthorized';
      } else {
        final set = rbac.closure([...active, candidate]);
        for (final constraint in rbac.dsd) {
          if (intersection(constraint.roles, set).length >=
              constraint.cardinality) {
            reason = 'dsd ${constraint.name}';
            break;
          }
        }
      }
      seen.add(candidate);
      a.activations.add(Activation(candidate, reason));
      if (reason.isEmpty) active.add(candidate);
    }
    a.roles = sortedSet(rbac.closure(active));
    for (final role in a.roles) {
      if (rbac.permissions[role]!.contains(
        '${request.action} ${resource.kind}',
      )) {
        a.grant = role;
        break;
      }
    }
    final attributes = <String, Value>{
      for (final v in subject.entries) 'subject.${v.key}': v.value,
      'subject.id': Value.string(request.user),
      'subject.role': Value.bag(a.roles),
      'subject.rbac': Value.boolean(a.grant.isNotEmpty),
      for (final v in resource.attributes.entries) 'resource.${v.key}': v.value,
      'resource.id': Value.string(request.resource),
      'resource.type': Value.string(resource.kind),
      'action.id': Value.string(request.action),
      for (final v in request.environment.entries)
        'environment.${v.key}': v.value,
    };
    a.result = evaluate(root, attributes, record ? a.coverage : null);
    return a;
  }

  List<String> decisionLines() {
    final out = <String>[];
    for (final a in answers) {
      if (a.error.isNotEmpty) {
        out.add('${a.request.id} ERROR ${a.error}');
        continue;
      }
      out.add('${a.request.id} ${a.decisionText()}');
      for (final v in a.activations) {
        if (v.reason.isNotEmpty) out.add('  refused ${v.role} ${v.reason}');
      }
      for (final item in a.result!.obligations) {
        out.add('  obligation $item');
      }
      for (final item in a.result!.advice) {
        out.add('  advice $item');
      }
    }
    return out;
  }

  List<String> traceLines() {
    final out = <String>[];
    for (final a in answers) {
      final r = a.request;
      if (!r.explain) continue;
      if (out.isNotEmpty) out.add('');
      out.add('request ${r.id}');
      if (a.error.isNotEmpty) {
        out.add('  error ${a.error}');
        continue;
      }
      out.add(
        '  user ${r.user} resource ${r.resource} type ${a.kind} action ${r.action} day ${a.day}',
      );
      for (final v in a.activations) {
        out.add(
          '  activate ${v.role} ${v.reason.isEmpty ? 'ok' : 'refused ${v.reason}'}',
        );
      }
      out.add('  roles ${a.roles.isEmpty ? '-' : a.roles.join(',')}');
      out.add(a.grant.isNotEmpty ? '  rbac yes ${a.grant}' : '  rbac no');
      out.addAll(treeLines(a.result!, 0));
      out.add('  decision ${a.decisionText()}');
    }
    return out;
  }

  List<String> permissionLines() {
    final assigned = <String, Map<String, Set<int>>>{};
    for (final a in rbac.assignments) {
      final days = assigned
          .putIfAbsent(a.user, () => {})
          .putIfAbsent(a.role, () => {});
      for (var d = a.first; d <= a.last; d++) {
        days.add(d);
      }
    }
    final out = <String>[];
    for (final user in stringKeys(assigned)) {
      if (out.isNotEmpty) out.add('');
      out.add('user $user');
      final authorization = <String, Set<int>>{};
      for (final role in stringKeys(assigned[user]!)) {
        final days = assigned[user]![role]!;
        out.add('  assigned $role ${dayNotation(days)}');
        for (final child in rbac.closure([role])) {
          authorization.putIfAbsent(child, () => {}).addAll(days);
        }
      }
      final permissions = <String, Set<int>>{}, via = <String, List<String>>{};
      for (final role in stringKeys(authorization)) {
        final days = authorization[role]!;
        out.add('  authorized $role ${dayNotation(days)}');
        for (final permission in rbac.permissions[role]!) {
          permissions.putIfAbsent(permission, () => {}).addAll(days);
          via.putIfAbsent(permission, () => []).add(role);
        }
      }
      for (final permission in stringKeys(permissions)) {
        var effective = '-';
        if (subjects.containsKey(user)) {
          final pair = permission.split(' ');
          var n = 0, k = 0;
          for (final resourceID in stringKeys(resources)) {
            if (resources[resourceID]!.kind != pair[1]) continue;
            n++;
            final result = answer(
              Request('', user, '*', pair[0], resourceID, reference),
              false,
            );
            if (result.result!.decision == 'PERMIT') k++;
          }
          effective = '$k/$n';
        }
        out.add(
          '  permission $permission ${dayNotation(permissions[permission]!)} via ${via[permission]!.join(',')} effective $effective',
        );
      }
    }
    return out;
  }

  List<String> analysisLines() {
    final out = ['rbac ${rbac.diagnostics.length}'];
    for (final d in rbac.diagnostics) {
      out.add('  line ${d.line} ${d.keyword} ${d.message}');
    }
    final permits = List<Permission>.of(rbac.permits)
      ..sort((a, b) {
        var c = a.role.compareTo(b.role);
        if (c != 0) return c;
        c = a.action.compareTo(b.action);
        return c != 0 ? c : a.kind.compareTo(b.kind);
      });
    out.add('grants ${permits.length}');
    for (final p in permits) {
      final count = answers
          .where(
            (a) =>
                a.error.isEmpty &&
                a.grant == p.role &&
                a.request.action == p.action &&
                a.kind == p.kind,
          )
          .length;
      out.add('  ${p.role} ${p.action} ${p.kind} $count');
    }
    final conflicts = <Conflict>[];
    for (final policy in elements) {
      if (policy.kind != 'policy') continue;
      for (var i = 0; i < policy.children.length; i++) {
        final a = policy.children[i];
        for (final b in policy.children.skip(i + 1)) {
          if (a.effect != b.effect)
            conflicts.add(Conflict(policy, a, b, conflictWinner(policy, a, b)));
        }
      }
    }
    var points = 1;
    for (final d in domains) {
      points *= d.values.length;
    }
    final counts = <Element, int>{},
        examples = <Element, String>{},
        unblocked = <Element>{},
        blockers = <Element, Set<Element>>{};
    enumeratePoints(domains, (point) {
      final targets = {
            for (final element in elements)
              element: evaluateTarget(element, point),
          },
          standalone = <Element, String>{},
          applies = <Element, bool>{};
      for (final rule in rules) {
        standalone[rule] = ruleResult(rule, point).decision;
        applies[rule] = definite(standalone[rule]!);
        for (var parent = rule.parent; parent != null; parent = parent.parent) {
          if (targets[parent]!.state != 'MATCH') applies[rule] = false;
        }
      }
      for (final rule in rules) {
        if (applies[rule] != true) continue;
        counts[rule] = (counts[rule] ?? 0) + 1;
        if (counts[rule] == 1)
          examples[rule] = [
            for (final domain in domains)
              if (domain.values.length > 1)
                '${domain.attribute}=${point[domain.attribute]!.notation()}',
          ].join(' ');
        if (rule.parent!.algorithm == 'first-applicable') {
          final b = blocker(rule, standalone);
          if (b == null) {
            unblocked.add(rule);
          } else {
            blockers.putIfAbsent(rule, () => {}).add(b);
          }
        }
      }
      for (final c in conflicts) {
        if (applies[c.a] == true && applies[c.b] == true) c.count++;
      }
    });
    out.add('applicability $points');
    final dead = <Element>[], shadowed = <Element>[], uncovered = <Element>[];
    for (final rule in rules) {
      final count = counts[rule] ?? 0;
      if (count == 0) dead.add(rule);
      out.add('  ${rule.id} $count ${count == 0 ? '-' : examples[rule]}');
      if (count > 0 &&
          rule.parent!.algorithm == 'first-applicable' &&
          !unblocked.contains(rule))
        shadowed.add(rule);
    }
    out.add('dead ${dead.length}');
    out.addAll(dead.map((r) => '  ${r.id}'));
    out.add('shadowed ${shadowed.length}');
    for (final rule in shadowed) {
      final ids = [
        for (final earlier in rule.parent!.children)
          if (blockers[rule]!.contains(earlier)) earlier.id,
      ];
      out.add('  ${rule.id} by ${ids.join(',')}');
    }
    out.add('conflicts ${conflicts.where((c) => c.count > 0).length}');
    for (final c in conflicts) {
      if (c.count > 0)
        out.add(
          '  ${c.policy.id} ${c.a.id} ${c.b.id} ${c.count} ${c.winner.id}',
        );
    }
    out.add('coverage ${answers.length}');
    for (final rule in rules) {
      final symbols = [for (final a in answers) a.coverage[rule]!].join(),
          count = symbols.codeUnits.where((c) => c == 80 || c == 68).length;
      out.add('  ${rule.id} $symbols $count');
      if (count == 0) uncovered.add(rule);
    }
    out.add('uncovered ${uncovered.length}');
    out.addAll(uncovered.map((r) => '  ${r.id}'));
    final decisionCounts = <String, int>{},
        decisive = <String, int>{},
        obligationCounts = <String, int>{},
        adviceCounts = <String, int>{};
    var refused = 0;
    void increment(Map<String, int> counts, String key) {
      counts[key] = (counts[key] ?? 0) + 1;
    }

    for (final a in answers) {
      if (a.error.isNotEmpty) {
        increment(decisionCounts, 'ERROR');
        continue;
      }
      final r = a.result!;
      increment(
        decisionCounts,
        indeterminate(r.decision) ? 'INDETERMINATE' : r.decision,
      );
      refused += a.activations.where((v) => v.reason.isNotEmpty).length;
      if (definite(r.decision)) increment(decisive, r.decisive);
      for (final item in r.obligations) {
        increment(obligationCounts, item.split(' ')[0]);
      }
      for (final item in r.advice) {
        increment(adviceCounts, item.split(' ')[0]);
      }
    }
    out.add('summary');
    for (final name in ['PERMIT', 'DENY', na, 'INDETERMINATE', 'ERROR']) {
      out.add('  decision $name ${decisionCounts[name] ?? 0}');
    }
    out.add('  refused $refused');
    for (final element in elements) {
      if ((decisive[element.id] ?? 0) > 0)
        out.add('  decisive ${element.id} ${decisive[element.id]}');
    }
    for (final name in stringKeys(obligationCounts)) {
      out.add('  obligation $name ${obligationCounts[name]}');
    }
    for (final name in stringKeys(adviceCounts)) {
      out.add('  advice $name ${adviceCounts[name]}');
    }
    return out;
  }
}

void main() {
  final (root, elements, rules) = readPolicies();
  final engine = Engine(readRBAC(), root, elements, rules);
  engine.readInputs();
  for (final request in engine.requests) {
    engine.answers.add(engine.answer(request, true));
  }
  final reports = {
    'decisions.txt': engine.decisionLines(),
    'traces.txt': engine.traceLines(),
    'permissions.txt': engine.permissionLines(),
    'analysis.txt': engine.analysisLines(),
  };
  Directory('output').createSync(recursive: true);
  for (final e in reports.entries) {
    File(
      'output/${e.key}',
    ).writeAsStringSync(e.value.isEmpty ? '' : '${e.value.join('\n')}\n');
  }
}
