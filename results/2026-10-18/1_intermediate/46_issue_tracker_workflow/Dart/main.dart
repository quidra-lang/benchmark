import 'dart:io';

const types = ['BUG', 'TASK', 'STORY'];
const priorities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
const workflows = {
  'BUG': ['OPEN', 'TRIAGED', 'IN_PROGRESS', 'REVIEW', 'RESOLVED', 'CLOSED', 'REOPENED'],
  'TASK': ['OPEN', 'IN_PROGRESS', 'DONE'],
  'STORY': ['BACKLOG', 'READY', 'IN_PROGRESS', 'REVIEW', 'DONE'],
};
const transitions = {
  'BUG': {'OPEN>TRIAGED', 'TRIAGED>IN_PROGRESS', 'IN_PROGRESS>REVIEW', 'REVIEW>IN_PROGRESS',
    'REVIEW>RESOLVED', 'RESOLVED>CLOSED', 'RESOLVED>REOPENED', 'CLOSED>REOPENED', 'REOPENED>IN_PROGRESS'},
  'TASK': {'OPEN>IN_PROGRESS', 'IN_PROGRESS>OPEN', 'IN_PROGRESS>DONE'},
  'STORY': {'BACKLOG>READY', 'READY>BACKLOG', 'READY>IN_PROGRESS', 'IN_PROGRESS>REVIEW',
    'REVIEW>IN_PROGRESS', 'REVIEW>DONE'},
};
const equalityOperators = {'=', '!='};
const orderedOperators = {'=', '!=', '<', '<=', '>', '>='};
const fieldOperators = {
  'id': orderedOperators, 'type': equalityOperators, 'status': equalityOperators,
  'priority': orderedOperators, 'assignee': equalityOperators, 'reviewer': equalityOperators,
  'estimate': orderedOperators, 'sprint': equalityOperators, 'comments': orderedOperators,
  'blocked': equalityOperators, 'done': equalityOperators, 'title': {'~'},
};

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

String display(Object? value) => value?.toString() ?? '-';
String yesNo(bool value) => value ? 'yes' : 'no';
String numberList(Iterable<int> numbers) {
  final ordered = numbers.toList()..sort();
  return ordered.isEmpty ? '-' : ordered.join(',');
}

class Issue {
  final int number;
  final String type;
  final String title;
  String priority;
  String state;
  String? assignee;
  String? reviewer;
  int? estimate;
  String? sprint;
  int comments = 0;
  final blocks = <int>{};
  final blockers = <int>{};
  int? duplicate;
  final duplicates = <int>{};
  final history = <String>[];

  Issue(this.number, this.type, this.priority, this.title)
      : state = workflows[type]!.first;

  bool get done => const {'RESOLVED', 'CLOSED', 'DONE'}.contains(state);
  int get points => estimate ?? 0;
  int get level => priorities.indexOf(priority);
}

class Sprint {
  final String name;
  String phase = 'PLANNED';
  int start = 0;
  int end = 0;
  int velocity = 0;
  final records = <int, int>{};
  Sprint(this.name);
}

typedef IssuePredicate = bool Function(Issue);

class QueryParser {
  final List<String> tokens;
  final List<IssuePredicate?> conditions;
  int position = 0;
  QueryParser(this.tokens, this.conditions);

  bool accept(String token) {
    if (position >= tokens.length || tokens[position] != token) return false;
    position++;
    return true;
  }

  IssuePredicate expression() {
    var node = term();
    while (accept('OR')) {
      final left = node;
      final right = term();
      node = (issue) => left(issue) || right(issue);
    }
    return node;
  }

  IssuePredicate term() {
    var node = factor();
    while (accept('AND')) {
      final left = node;
      final right = factor();
      node = (issue) => left(issue) && right(issue);
    }
    return node;
  }

  IssuePredicate factor() {
    if (accept('NOT')) {
      final operand = factor();
      return (issue) => !operand(issue);
    }
    if (accept('(')) {
      final node = expression();
      accept(')');
      return node;
    }
    return conditions[position++]!;
  }
}

class Tracker {
  int day = 1;
  final users = <String>{};
  final issues = <int, Issue>{};
  final sprints = <String, Sprint>{};

  Issue requireIssue(String text) =>
      issues[int.parse(text)] ?? (throw CommandError('unknown issue'));
  Sprint requireSprint(String name) =>
      sprints[name] ?? (throw CommandError('unknown sprint'));
  String? requireUser(String spec) {
    if (spec == '-') return null;
    if (!users.contains(spec)) throw CommandError('unknown user');
    return spec;
  }
  void requireNotDone(Issue issue) {
    if (issue.done) throw CommandError('issue done');
  }
  List<Issue> orderedIssues() => issues.values.toList()
    ..sort((a, b) => a.number.compareTo(b.number));
  List<int> unfinished(Issue issue) => issue.blockers
      .where((number) => !issues[number]!.done).toList()..sort();
  bool blocked(Issue issue) => !issue.done && unfinished(issue).isNotEmpty;
  int wip(String? user) => issues.values
      .where((issue) => issue.assignee == user && issue.state == 'IN_PROGRESS').length;
  Sprint? activeSprint() {
    for (final sprint in sprints.values) {
      if (sprint.phase == 'ACTIVE') return sprint;
    }
    return null;
  }
  List<Issue> members(Sprint sprint) => orderedIssues()
      .where((issue) => issue.sprint == sprint.name).toList();
  int remaining(Sprint sprint) => members(sprint).where((issue) => !issue.done)
      .fold(0, (sum, issue) => sum + issue.points);
  String summary(Sprint sprint) {
    final current = members(sprint);
    final points = current.fold<int>(0, (sum, issue) => sum + issue.points);
    return 'issues ${current.length} points $points';
  }
  void record(Issue issue, String content) => issue.history.add('day $day $content');
  Map<int, bool> blockedBefore(Iterable<int> numbers) => {
    for (final number in numbers) number: blocked(issues[number]!),
  };
  void notify(Map<int, bool> before, List<String> output) {
    final numbers = before.keys.toList()..sort();
    for (final number in numbers) {
      final after = blocked(issues[number]!);
      if (after != before[number]) output.add('${after ? 'BLOCKED' : 'UNBLOCKED'} $number');
    }
  }
  void changeState(Issue issue, String target, List<String> output) {
    final before = blockedBefore(issue.blocks);
    output.add('MOVE ${issue.number} ${issue.state} $target');
    record(issue, 'MOVE ${issue.state} $target');
    issue.state = target;
    notify(before, output);
  }
  bool reaches(int start, int goal) {
    final pending = [start];
    final visited = <int>{};
    while (pending.isNotEmpty) {
      final number = pending.removeLast();
      if (number == goal) return true;
      if (visited.add(number)) pending.addAll(issues[number]!.blocks);
    }
    return false;
  }

  bool compare(int? actual, int? expected, String operation) {
    if (operation == '=') return actual == expected;
    if (operation == '!=') return actual != expected;
    if (actual == null) return false;
    return switch (operation) {
      '<' => actual < expected!,
      '<=' => actual <= expected!,
      '>' => actual > expected!,
      _ => actual >= expected!,
    };
  }

  IssuePredicate condition(String token) {
    var length = 0;
    while (length < token.length && token.codeUnitAt(length) >= 97 && token.codeUnitAt(length) <= 122) {
      length++;
    }
    final field = token.substring(0, length);
    final rest = token.substring(length);
    String? operation;
    for (final candidate in ['>=', '<=', '!=', '=', '<', '>', '~']) {
      if (rest.startsWith(candidate)) { operation = candidate; break; }
    }
    final text = operation == null ? '' : rest.substring(operation.length);
    if (field.isEmpty || operation == null || text.isEmpty) throw CommandError('syntax near $token');
    final operators = fieldOperators[field];
    if (operators == null) throw CommandError('unknown field $field');
    if (!operators.contains(operation)) throw CommandError('bad operator $token');
    final none = text == '-' && const {'assignee', 'reviewer', 'estimate', 'sprint'}.contains(field)
        && equalityOperators.contains(operation);
    int? numeric;
    String? string = none ? null : text;
    bool valid;
    switch (field) {
      case 'id':
      case 'estimate':
      case 'comments':
        valid = none || RegExp(r'^[0-9]{1,6}$').hasMatch(text);
        if (valid && !none) numeric = int.parse(text);
        break;
      case 'priority':
        valid = priorities.contains(text);
        if (valid) numeric = priorities.indexOf(text);
        break;
      case 'type': valid = types.contains(text); break;
      case 'status': valid = workflows.values.any((states) => states.contains(text)); break;
      case 'assignee':
      case 'reviewer': valid = none || users.contains(text); break;
      case 'sprint': valid = none || sprints.containsKey(text); break;
      case 'blocked':
      case 'done': valid = text == 'yes' || text == 'no'; break;
      case 'title': string = text.toLowerCase(); valid = true; break;
      default: valid = false;
    }
    if (!valid) throw CommandError('bad value $token');
    final expectedNumber = numeric;
    final expectedString = string;
    final comparison = operation;
    return (issue) {
      if (const {'id', 'estimate', 'comments', 'priority'}.contains(field)) {
        final int? actual = switch (field) {
          'id' => issue.number,
          'estimate' => issue.estimate,
          'comments' => issue.comments,
          _ => issue.level,
        };
        return compare(actual, expectedNumber, comparison);
      }
      final String? actual = switch (field) {
        'type' => issue.type,
        'status' => issue.state,
        'assignee' => issue.assignee,
        'reviewer' => issue.reviewer,
        'sprint' => issue.sprint,
        'blocked' => yesNo(blocked(issue)),
        'done' => yesNo(issue.done),
        _ => issue.title.toLowerCase(),
      };
      return switch (comparison) {
        '~' => actual!.contains(expectedString!),
        '=' => actual == expectedString,
        _ => actual != expectedString,
      };
    };
  }

  void query(String text, List<String> output) {
    final tokens = RegExp(r'[()]|[^ ()]+').allMatches(text).map((match) => match.group(0)!).toList();
    final conditions = <IssuePredicate?>[];
    var operand = true;
    var depth = 0;
    for (final token in tokens) {
      IssuePredicate? predicate;
      if (operand) {
        if (token == 'NOT') {
          // Another operand still follows.
        } else if (token == '(') {
          depth++;
        } else if (const {'AND', 'OR', ')'}.contains(token)) {
          throw CommandError('syntax near $token');
        } else {
          predicate = condition(token);
          operand = false;
        }
      } else if (token == 'AND' || token == 'OR') {
        operand = true;
      } else if (token == ')' && depth > 0) {
        depth--;
      } else {
        throw CommandError('syntax near $token');
      }
      conditions.add(predicate);
    }
    if (operand || depth != 0) throw CommandError('syntax at end');
    final predicate = QueryParser(tokens, conditions).expression();
    final matches = issues.values.where(predicate).toList()..sort((a, b) {
      final priority = b.level.compareTo(a.level);
      return priority != 0 ? priority : a.number.compareTo(b.number);
    });
    output.add('QUERY ${matches.length}');
    for (final issue in matches) {
      output.add('${issue.number} ${issue.type} ${issue.priority} ${issue.state} '
          '${display(issue.assignee)} ${display(issue.estimate)} ${issue.title}');
    }
  }

  void sprintCommand(List<String> words, List<String> output) {
    final action = words[1];
    final name = words[2];
    if (action == 'NEW') {
      if (sprints.containsKey(name)) throw CommandError('sprint exists');
      sprints[name] = Sprint(name);
      output.add('SPRINT NEW $name');
      return;
    }
    final sprint = requireSprint(name);
    switch (action) {
      case 'ADD':
      case 'REMOVE':
        final issue = requireIssue(words[3]);
        if (sprint.phase == 'ENDED') throw CommandError('sprint ended');
        if (action == 'ADD') {
          requireNotDone(issue);
          if (issue.sprint != null && sprints[issue.sprint]!.phase != 'ENDED') {
            throw CommandError('in sprint ${issue.sprint}');
          }
          if (issue.state == 'BACKLOG') throw CommandError('not ready');
          issue.sprint = name;
        } else {
          if (issue.sprint != name) throw CommandError('not in sprint');
          requireNotDone(issue);
          issue.sprint = null;
        }
        record(issue, 'SPRINT $action $name');
        output.add('SPRINT $action $name ${issue.number} ${summary(sprint)}');
        break;
      case 'START':
        if (sprint.phase != 'PLANNED') throw CommandError('sprint not planned');
        final active = activeSprint();
        if (active != null) throw CommandError('sprint active ${active.name}');
        if (members(sprint).isEmpty) throw CommandError('sprint empty');
        sprint.phase = 'ACTIVE';
        sprint.start = day;
        sprint.records[day] = remaining(sprint);
        output.add('SPRINT START $name day $day ${summary(sprint)} remaining ${remaining(sprint)}');
        break;
      case 'END':
        if (sprint.phase != 'ACTIVE') throw CommandError('sprint not active');
        sprint.records[day] = remaining(sprint);
        final current = members(sprint);
        final finished = current.where((issue) => issue.done).toList();
        final returned = current.where((issue) => !issue.done).toList();
        sprint.velocity = finished.fold(0, (sum, issue) => sum + issue.points);
        sprint.phase = 'ENDED';
        sprint.end = day;
        output.add('SPRINT END $name day $day velocity ${sprint.velocity} done ${finished.length} returned ${returned.length}');
        for (final issue in returned) {
          issue.sprint = null;
          record(issue, 'SPRINT RETURN $name');
          output.add('RETURNED ${issue.number}');
        }
        break;
    }
  }

  void process(String line, List<String> output) {
    final words = line.split(' ');
    final command = words[0];
    switch (command) {
      case 'DAY': {
        final next = int.parse(words[1]);
        if (next < day) throw CommandError('day backwards');
        day = next;
        output.add('DAY $day');
        break;
      }
      case 'USER':
        if (!users.add(words[1])) throw CommandError('user exists');
        output.add('USER ${words[1]}');
        break;
      case 'CREATE': {
        final number = int.parse(words[1]);
        if (issues.containsKey(number)) throw CommandError('issue exists');
        if (!types.contains(words[2])) throw CommandError('bad type');
        if (!priorities.contains(words[3])) throw CommandError('bad priority');
        final issue = Issue(number, words[2], words[3], words.sublist(4).join(' '));
        issues[number] = issue;
        record(issue, 'CREATE ${issue.type} ${issue.priority}');
        output.add('CREATE $number ${issue.type} ${issue.priority} ${issue.state}');
        break;
      }
      case 'PRIORITY': {
        final issue = requireIssue(words[1]);
        final priority = words[2];
        if (!priorities.contains(priority)) throw CommandError('bad priority');
        requireNotDone(issue);
        if (priority == issue.priority) throw CommandError('no change');
        final old = issue.priority;
        issue.priority = priority;
        record(issue, 'PRIORITY $old $priority');
        output.add('PRIORITY ${issue.number} $old $priority');
        break;
      }
      case 'ASSIGN':
      case 'REVIEWER': {
        final issue = requireIssue(words[1]);
        final spec = words[2];
        final user = requireUser(spec);
        requireNotDone(issue);
        final old = command == 'ASSIGN' ? issue.assignee : issue.reviewer;
        if (old == user) throw CommandError('no change');
        if (command == 'ASSIGN') {
          if (user == null && const {'IN_PROGRESS', 'REVIEW'}.contains(issue.state)) throw CommandError('assignee required');
          if (issue.state == 'IN_PROGRESS' && wip(user) >= 3) throw CommandError('wip limit $spec');
          if (issue.state == 'REVIEW' && user == issue.reviewer) throw CommandError('reviewer is assignee');
          issue.assignee = user;
        } else {
          if (user == null && issue.state == 'REVIEW') throw CommandError('reviewer required');
          if (issue.state == 'REVIEW' && user == issue.assignee) throw CommandError('reviewer is assignee');
          issue.reviewer = user;
        }
        record(issue, '$command $spec');
        output.add('$command ${issue.number} $spec');
        break;
      }
      case 'ESTIMATE': {
        final issue = requireIssue(words[1]);
        final points = int.parse(words[2]);
        if (!const {0, 1, 2, 3, 5, 8, 13, 21}.contains(points)) throw CommandError('bad estimate');
        requireNotDone(issue);
        if (issue.estimate == points) throw CommandError('no change');
        final old = display(issue.estimate);
        issue.estimate = points;
        record(issue, 'ESTIMATE $old $points');
        output.add('ESTIMATE ${issue.number} $old $points');
        break;
      }
      case 'COMMENT': {
        final issue = requireIssue(words[1]);
        requireUser(words[2]);
        issue.comments++;
        record(issue, 'COMMENT ${words[2]} ${words.sublist(3).join(' ')}');
        output.add('COMMENT ${issue.number} ${issue.comments}');
        break;
      }
      case 'MOVE': {
        final issue = requireIssue(words[1]);
        final target = words[2];
        if (issue.duplicate != null) throw CommandError('duplicate of ${issue.duplicate}');
        if (!workflows[issue.type]!.contains(target)) throw CommandError('bad state');
        if (!transitions[issue.type]!.contains('${issue.state}>$target')) {
          throw CommandError('cannot move ${issue.state} to $target');
        }
        if (target == 'IN_PROGRESS') {
          final active = activeSprint();
          if (issue.type == 'STORY' && (active == null || issue.sprint != active.name)) throw CommandError('not in active sprint');
          if (issue.assignee == null) throw CommandError('no assignee');
          if (wip(issue.assignee) >= 3) throw CommandError('wip limit ${issue.assignee}');
        }
        if (target == 'REVIEW') {
          if (issue.reviewer == null) throw CommandError('no reviewer');
          if (issue.reviewer == issue.assignee) throw CommandError('reviewer is assignee');
        }
        final blockers = unfinished(issue);
        if (const {'DONE', 'RESOLVED'}.contains(target) && blockers.isNotEmpty) throw CommandError('blocked by ${blockers.first}');
        if (target == 'READY' && issue.estimate == null) throw CommandError('no estimate');
        changeState(issue, target, output);
        break;
      }
      case 'LINK':
      case 'UNLINK': {
        final relation = words[2];
        if (!(command == 'LINK' ? {'BLOCKS', 'DUPLICATES'} : {'BLOCKS'}).contains(relation)) throw CommandError('bad link');
        final source = requireIssue(words[1]);
        final target = requireIssue(words[3]);
        if (command == 'UNLINK') {
          if (!source.blocks.contains(target.number)) throw CommandError('no link');
          final before = blockedBefore([target.number]);
          source.blocks.remove(target.number);
          target.blockers.remove(source.number);
          record(source, 'UNLINK BLOCKS ${target.number}');
          record(target, 'UNLINK BLOCKED_BY ${source.number}');
          output.add('UNLINK ${source.number} BLOCKS ${target.number}');
          notify(before, output);
        } else {
          if (identical(source, target)) throw CommandError('self link');
          if (relation == 'BLOCKS') {
            if (source.blocks.contains(target.number)) throw CommandError('link exists');
            if (reaches(target.number, source.number)) throw CommandError('cycle');
            requireNotDone(target);
            final before = blockedBefore([target.number]);
            source.blocks.add(target.number);
            target.blockers.add(source.number);
            record(source, 'LINK BLOCKS ${target.number}');
            record(target, 'LINK BLOCKED_BY ${source.number}');
            output.add('LINK ${source.number} BLOCKS ${target.number}');
            notify(before, output);
          } else {
            if (source.type != target.type) throw CommandError('type mismatch');
            requireNotDone(source);
            if (target.duplicate != null) throw CommandError('target is duplicate');
            source.duplicate = target.number;
            target.duplicates.add(source.number);
            record(source, 'LINK DUPLICATES ${target.number}');
            record(target, 'LINK DUPLICATED_BY ${source.number}');
            output.add('LINK ${source.number} DUPLICATES ${target.number}');
            changeState(source, source.type == 'BUG' ? 'CLOSED' : 'DONE', output);
            if (source.sprint != null && sprints[source.sprint]!.phase != 'ENDED') {
              record(source, 'SPRINT REMOVE ${source.sprint}');
              source.sprint = null;
            }
          }
        }
        break;
      }
      case 'SPRINT': sprintCommand(words, output); break;
      case 'QUERY': query(words.sublist(1).join(' '), output); break;
      case 'SHOW': {
        final issue = requireIssue(words[1]);
        output.add('ISSUE ${issue.number} ${issue.type} ${issue.priority} ${issue.state} blocked ${yesNo(blocked(issue))}');
        output.add('TITLE ${issue.title}');
        output.add('PEOPLE assignee ${display(issue.assignee)} reviewer ${display(issue.reviewer)}');
        output.add('PLAN estimate ${display(issue.estimate)} sprint ${display(issue.sprint)} comments ${issue.comments}');
        output.add('LINKS blocks ${numberList(issue.blocks)} blocked_by ${numberList(issue.blockers)} '
            'duplicate_of ${display(issue.duplicate)} duplicated_by ${numberList(issue.duplicates)}');
        break;
      }
      case 'HISTORY': {
        final issue = requireIssue(words[1]);
        output.add('HISTORY ${issue.number} ${issue.history.length}');
        output.addAll(issue.history);
        break;
      }
      case 'BOARD': {
        output.add('BOARD');
        for (final type in types) {
          final row = StringBuffer(type);
          for (final state in workflows[type]!) {
            row.write(' $state ${issues.values.where((issue) => issue.type == type && issue.state == state).length}');
          }
          output.add(row.toString());
        }
        final done = issues.values.where((issue) => issue.done).length;
        output.add('TOTAL ${issues.length} open ${issues.length - done} done $done');
        break;
      }
      case 'WORKLOAD': {
        output.add('WORKLOAD ${users.length}');
        final orderedUsers = users.toList()..sort();
        for (final user in orderedUsers) {
          final assigned = issues.values.where((issue) => issue.assignee == user && !issue.done).toList();
          final inProgress = assigned.where((issue) => issue.state == 'IN_PROGRESS').length;
          final review = assigned.where((issue) => issue.state == 'REVIEW').length;
          final reviewing = issues.values.where((issue) => issue.reviewer == user && issue.state == 'REVIEW').length;
          final points = assigned.fold<int>(0, (sum, issue) => sum + issue.points);
          output.add('$user assigned ${assigned.length} in_progress $inProgress review $review reviewing $reviewing points $points');
        }
        break;
      }
      case 'SPRINTS':
        output.add('SPRINTS ${sprints.length}');
        for (final sprint in sprints.values) {
          output.add(switch (sprint.phase) {
            'PLANNED' => '${sprint.name} PLANNED ${summary(sprint)}',
            'ACTIVE' => '${sprint.name} ACTIVE start ${sprint.start} ${summary(sprint)} remaining ${remaining(sprint)}',
            _ => '${sprint.name} ENDED start ${sprint.start} end ${sprint.end} velocity ${sprint.velocity}',
          });
        }
        break;
      case 'BURNDOWN': {
        final sprint = requireSprint(words[1]);
        if (sprint.phase == 'PLANNED') throw CommandError('sprint not started');
        final last = sprint.phase == 'ACTIVE' ? day : sprint.end;
        output.add('BURNDOWN ${sprint.name} ${sprint.phase} days ${last - sprint.start + 1}');
        var value = 0;
        for (var recordDay = sprint.start; recordDay <= last; recordDay++) {
          value = sprint.records[recordDay] ?? value;
          output.add('day $recordDay $value');
        }
        break;
      }
    }
  }

  List<String> execute(String line) {
    final output = <String>[];
    try {
      process(line, output);
    } on CommandError catch (error) {
      output.add('ERROR ${error.message}');
    }
    final active = activeSprint();
    if (active != null) active.records[day] = remaining(active);
    return output;
  }
}

void main() {
  final tracker = Tracker();
  final count = int.parse(stdin.readLineSync()!);
  for (var index = 0; index < count; index++) {
    for (final line in tracker.execute(stdin.readLineSync()!)) {
      stdout.writeln(line);
    }
  }
}
