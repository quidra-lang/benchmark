import 'dart:collection';
import 'dart:io';

class EvaluationError implements Exception {}
class Reference {
  final String kind, name;
  Reference(this.kind, this.name);
}
sealed class Node {}
class NumberNode extends Node {
  final int value;
  NumberNode(this.value);
}
class NameNode extends Node {
  final String kind, name;
  NameNode(this.kind, this.name);
}
class UnaryNode extends Node {
  final String operator;
  final Node value;
  UnaryNode(this.operator, this.value);
}
class BinaryNode extends Node {
  final String operator;
  final Node left, right;
  BinaryNode(this.operator, this.left, this.right);
}
class Expression {
  final Node node;
  final List<Reference> references;
  Expression(this.node, this.references);
}
class ExpressionParser {
  final List<String> tokens;
  final references = <Reference>[];
  int at = 0;
  ExpressionParser(String text) : tokens = RegExp(r'[0-9]+|[A-Za-z_][A-Za-z0-9_]*|\|\||&&|==|!=|<=|>=|[<>+*/%!()-]')
      .allMatches(text).map((match) => match[0]!).toList();
  Node primary() {
    final token = tokens[at++];
    if (token == '-' || token == '!') return UnaryNode(token, primary());
    if (token == '(') {
      final value = binary(0);
      at++;
      return value;
    }
    if (token.codeUnitAt(0) >= 48 && token.codeUnitAt(0) <= 57) return NumberNode(int.parse(token));
    if (token == 'in') {
      at++;
      final name = tokens[at++];
      at++;
      references.add(Reference('state', name));
      return NameNode('state', name);
    }
    if (token != '_data') references.add(Reference('variable', token));
    return NameNode('variable', token);
  }
  Node binary(int level) {
    if (level == 5) return primary();
    final operators = [['||'], ['&&'], ['==', '!=', '<', '<=', '>', '>='], ['+', '-'], ['*', '/', '%']][level];
    Node left = binary(level + 1);
    while (at < tokens.length && operators.contains(tokens[at])) {
      final operator = tokens[at++], right = binary(level + 1);
      left = BinaryNode(operator, left, right);
    }
    return left;
  }
  Expression parse() => Expression(binary(0), references);
}
Expression expression(String text) => ExpressionParser(text).parse();

class Action {
  final String kind, name, event, text;
  final int delay;
  final Expression? expression;
  Action(this.kind, {this.name = '', this.event = '', this.text = '', this.delay = 0, this.expression});
}
List<Action> actions(String text) {
  if (text.isEmpty) return [];
  return text.split('; ').map((part) {
    final space = part.indexOf(' '), first = part.substring(0, space), rest = part.substring(space + 1);
    if (first == 'log') {
      if (rest.startsWith('"')) {
        final close = rest.indexOf('"', 1);
        return Action('log', text: rest.substring(1, close),
            expression: close + 1 == rest.length ? null : expression(rest.substring(close + 2)));
      }
      return Action('log', expression: expression(rest));
    }
    if (first == 'cancel') return Action('cancel', event: rest);
    if (first == 'raise' || first == 'send') {
      final words = rest.split(' '), event = words.removeAt(0);
      final delay = first == 'send' ? int.parse(words.removeAt(0)) : 0;
      return Action(first, event: event, delay: delay,
          expression: words.isEmpty ? null : expression(words.join(' ')));
    }
    return Action('assign', name: first, expression: expression(rest.substring(2)));
  }).toList();
}
List<Reference> actionReferences(List<Action> list) {
  final references = <Reference>[];
  for (final action in list) {
    if (action.kind == 'assign') references.add(Reference('variable', action.name));
    references.addAll(action.expression?.references ?? []);
  }
  return references;
}
class TransitionParts {
  final String trigger, kind;
  final Expression? guard;
  final String? target;
  final List<Action> actions;
  TransitionParts(this.trigger, this.guard, this.target, this.kind, this.actions);
}
TransitionParts transitionParts(String text) {
  final first = text.indexOf(' ');
  String trigger, rest;
  if (text.startsWith('after ')) {
    final end = text.indexOf(' ', 6);
    trigger = end < 0 ? text : text.substring(0, end);
    rest = end < 0 ? '' : text.substring(end);
  } else {
    trigger = first < 0 ? text : text.substring(0, first);
    rest = first < 0 ? '' : text.substring(first);
  }
  Expression? guard;
  String? target;
  String kind = 'internal';
  if (rest.startsWith(' [')) {
    final end = rest.indexOf(']');
    guard = expression(rest.substring(2, end));
    rest = rest.substring(end + 1);
  }
  if (rest.startsWith(' -> ') || rest.startsWith(' ~> ')) {
    kind = rest[1] == '-' ? 'external' : 'local';
    rest = rest.substring(4);
    final end = rest.indexOf(' ');
    target = end < 0 ? rest : rest.substring(0, end);
    rest = end < 0 ? '' : rest.substring(end);
  }
  return TransitionParts(trigger, guard, target, kind, actions(rest.isEmpty ? '' : rest.substring(3)));
}

class State {
  final String name, kind, mode;
  final State? parent;
  final int line, depth;
  final String? initial, fallback;
  final children = <State>[];
  final entries = <List<Action>>[], exits = <List<Action>>[];
  final transitions = <Transition>[];
  int entered = 0, taken = 0, dwell = 0, enteredAt = 0;
  List<State>? history;
  State(this.name, this.kind, this.parent, this.line, this.initial, this.mode, this.fallback)
      : depth = parent == null ? 0 : parent.depth + 1;
}
class Transition {
  final State source;
  final String kind, type;
  final State? target;
  final Expression? guard;
  final int delay;
  final List<String> descriptors;
  final List<Action> actions;
  Transition(this.source, this.kind, this.target, this.guard, this.type, this.delay, this.descriptors, this.actions);
}
class Definition {
  final String text, kind, name;
  final int line;
  State? state;
  Definition(this.text, this.line) : kind = text.split(' ')[0], name = text.split(' ')[1];
}
class Chart {
  final root = State('', 'state', null, 0, null, '', null);
  final states = <String, State>{}, variables = <String, int>{}, errors = <int, String>{};
  List<State> order = [];
  String? checkReferences(List<Reference> references) {
    for (final reference in references) {
      if (!(reference.kind == 'state' ? states.containsKey(reference.name) : variables.containsKey(reference.name))) {
        return 'unknown ${reference.kind} ${reference.name}';
      }
    }
    return null;
  }
}
List<State> childStates(State state) => state.children.where((child) => child.kind != 'history').toList();
bool compound(State state) => state.parent == null || state.kind == 'state' && childStates(state).isNotEmpty;
bool parallel(State state) => state.kind == 'parallel' && childStates(state).isNotEmpty;
bool atomic(State state) => state.kind != 'history' && childStates(state).isEmpty;
bool descendant(State state, State ancestor) {
  for (State? parent = state.parent; parent != null; parent = parent.parent) {
    if (identical(parent, ancestor)) return true;
  }
  return false;
}
State initial(State state, Chart chart) => state.initial == null ? childStates(state).first : chart.states[state.initial]!;
State fallback(State state, Chart chart) => state.fallback == null ? initial(state.parent!, chart) : chart.states[state.fallback]!;
List<State> document(State root) {
  final result = <State>[];
  void visit(State state) {
    result.add(state);
    for (final child in state.children) { visit(child); }
  }
  for (final state in root.children) { visit(state); }
  return result;
}
Chart build(List<(String, int)> lines) {
  final chart = Chart(), definitions = <Definition>[];
  for (final (text, line) in lines) {
    final words = text.split(' '), kind = words[0], name = words[1];
    final definition = Definition(text, line);
    definitions.add(definition);
    if (['state', 'parallel', 'final', 'history'].contains(kind)) {
      String? parentName, selected, defaultTarget;
      String mode = '';
      if (kind == 'state') {
        if (words.length > 2 && words[2] == 'initial') { selected = words[3]; }
        else {
          parentName = words.length > 2 ? words[2] : null;
          if (words.length > 3 && words[3] == 'initial') selected = words[4];
        }
      } else {
        parentName = words.length > 2 ? words[2] : null;
        if (kind == 'history') { mode = words[3]; defaultTarget = words.length > 4 ? words[4] : null; }
      }
      if (chart.states.containsKey(name)) { chart.errors[line] = 'duplicate state $name'; }
      else if (parentName != null && !chart.states.containsKey(parentName)) { chart.errors[line] = 'unknown state $parentName'; }
      else if (parentName != null && ['final', 'history'].contains(chart.states[parentName]!.kind)) { chart.errors[line] = '$parentName cannot have children'; }
      else {
        final parent = parentName == null ? chart.root : chart.states[parentName]!;
        final state = State(name, kind, parent, line, selected, mode, defaultTarget);
        parent.children.add(state);
        chart.states[name] = state;
        definition.state = state;
      }
    } else if (kind == 'var') {
      if (chart.variables.containsKey(name)) { chart.errors[line] = 'duplicate variable $name'; }
      else { chart.variables[name] = int.parse(words[2]); }
    }
  }
  for (final definition in definitions) {
    if (chart.errors.containsKey(definition.line)) continue;
    final kind = definition.kind, name = definition.name;
    String? error;
    if (kind == 'state') {
      final state = definition.state!;
      if (state.initial != null) {
        final child = chart.states[state.initial];
        if (child == null) { error = 'unknown state ${state.initial}'; }
        else if (child.parent != state || child.kind == 'history') { error = '${child.name} is not a child of $name'; }
      }
    } else if (kind == 'final' || kind == 'history') {
      final state = definition.state!;
      if (state.parent!.kind != 'state' || !compound(state.parent!)) { error = '$name needs a compound parent'; }
      else if (kind == 'history' && state.fallback != null) {
        final target = chart.states[state.fallback];
        if (target == null) { error = 'unknown state ${state.fallback}'; }
        else if (!descendant(target, state.parent!) || target.kind == 'history') { error = '${target.name} is not a descendant of ${state.parent!.name}'; }
      }
    } else if (['entry', 'exit', 'on'].contains(kind)) {
      final source = chart.states[name];
      if (source == null) { error = 'unknown state $name'; }
      else if (source.kind == 'history' && kind != 'on') { error = '$name cannot have actions'; }
      else if (kind == 'on' && ['final', 'history'].contains(source.kind)) { error = '$name cannot have transitions'; }
      else if (kind == 'on') {
        final part = transitionParts(definition.text.substring('on $name '.length));
        final references = <Reference>[...?part.guard?.references];
        if (part.target != null) references.add(Reference('state', part.target!));
        references.addAll(actionReferences(part.actions));
        error = chart.checkReferences(references);
        if (error == null) {
          source.transitions.add(Transition(source, part.kind, part.target == null ? null : chart.states[part.target], part.guard,
              part.trigger == 'always' ? 'always' : part.trigger.startsWith('after ') ? 'timer' : 'event',
              part.trigger.startsWith('after ') ? int.parse(part.trigger.substring(6)) : 0,
              part.trigger.split('|'), part.actions));
        }
      } else {
        final list = actions(definition.text.substring(definition.text.indexOf(' / ') + 3));
        error = chart.checkReferences(actionReferences(list));
        if (error == null) (kind == 'entry' ? source.entries : source.exits).add(list);
      }
    }
    if (error != null) chart.errors[definition.line] = error;
  }
  chart.order = document(chart.root);
  return chart;
}
String names(Iterable<State> states) {
  final result = states.map((state) => state.name).join(',');
  return result.isEmpty ? '-' : result;
}
void warnings(Chart chart, List<String> output) {
  final reachable = <State>{initial(chart.root, chart)};
  bool changed = true;
  while (changed) {
    changed = false;
    void add(State state) {
      if (reachable.add(state)) changed = true;
    }
    for (final state in reachable.toList()) {
      if (state.parent != chart.root) add(state.parent!);
      if (compound(state)) add(initial(state, chart));
      if (parallel(state)) { for (final child in childStates(state)) { add(child); } }
      for (final transition in state.transitions) {
        final target = transition.target;
        if (target != null) add(target.kind == 'history' ? fallback(target, chart) : target);
      }
    }
  }
  for (final state in chart.order) {
    if (state.kind != 'history' && !reachable.contains(state)) output.add('warning: unreachable state ${state.name}');
  }
}

class ChartEvent {
  final String name;
  final int value;
  ChartEvent(this.name, this.value);
}
sealed class Trigger {}
class StartTrigger extends Trigger {}
class AlwaysTrigger extends Trigger {}
class EventTrigger extends Trigger {
  final ChartEvent event;
  EventTrigger(this.event);
}
class TimerTrigger extends Trigger {
  final Transition transition;
  TimerTrigger(this.transition);
}
sealed class Reservation {
  final int due, serial;
  Reservation(this.due, this.serial);
}
class TimerReservation extends Reservation {
  final Transition transition;
  TimerReservation(super.due, super.serial, this.transition);
}
class SendReservation extends Reservation {
  final ChartEvent event;
  SendReservation(super.due, super.serial, this.event);
}
class Choice {
  final Transition transition;
  final State? scope;
  final Set<State> exits;
  Choice(this.transition, this.scope, this.exits);
}
class Machine {
  final Chart chart;
  final List<String> output;
  final configuration = <State>{};
  final Map<String, int> variables;
  final queue = Queue<ChartEvent>();
  List<Reservation> reservations = [];
  int data = 0, serial = 0, time = 0, macrosteps = 0, microsteps = 0;
  bool trace = false, halted = false;
  Machine(this.chart, this.output) : variables = Map.of(chart.variables);
  int evaluate(Expression expression) => value(expression.node);
  int value(Node node) {
    if (node is NumberNode) return node.value;
    if (node is NameNode) {
      if (node.kind == 'state') return configuration.contains(chart.states[node.name]) ? 1 : 0;
      return node.name == '_data' ? data : variables[node.name]!;
    }
    if (node is UnaryNode) {
      final result = value(node.value);
      return node.operator == '-' ? -result : result == 0 ? 1 : 0;
    }
    final binary = node as BinaryNode;
    final a = value(binary.left);
    if (binary.operator == '&&' && a == 0) return 0;
    if (binary.operator == '||' && a != 0) return 1;
    final b = value(binary.right);
    if (['/', '%'].contains(binary.operator) && b == 0) throw EvaluationError();
    return switch (binary.operator) {
      '+' => a + b, '-' => a - b, '*' => a * b, '/' => a ~/ b, '%' => a - (a ~/ b) * b,
      '==' => a == b ? 1 : 0, '!=' => a != b ? 1 : 0, '<' => a < b ? 1 : 0,
      '<=' => a <= b ? 1 : 0, '>' => a > b ? 1 : 0, '>=' => a >= b ? 1 : 0,
      _ => b != 0 ? 1 : 0
    };
  }
  void enqueue(String name, [int value = 0]) => queue.add(ChartEvent(name, value));
  void actionList(List<Action> list) {
    for (final action in list) {
      try {
        final result = action.expression == null ? 0 : evaluate(action.expression!);
        switch (action.kind) {
          case 'assign': variables[action.name] = result; break;
          case 'raise': enqueue(action.event, result); break;
          case 'send': reservations.add(SendReservation(time + action.delay, ++serial, ChartEvent(action.event, result))); break;
          case 'cancel': reservations.removeWhere((item) => item is SendReservation && item.event.name == action.event); break;
          case 'log': output.add('${action.text}${action.expression == null ? '' : result}'); break;
        }
      } on EvaluationError {
        enqueue('error.execution');
        break;
      }
    }
  }
  List<State> effective(Transition transition) {
    final target = transition.target!;
    return target.kind == 'history' ? target.history ?? [fallback(target, chart)] : [target];
  }
  Choice choice(Transition transition) {
    if (transition.kind == 'internal') return Choice(transition, null, {});
    final targets = effective(transition);
    State? scope = transition.kind == 'local' && compound(transition.source)
        && targets.every((target) => descendant(target, transition.source)) ? transition.source : transition.source.parent;
    while (!compound(scope!) || !targets.every((target) => descendant(target, scope!))) { scope = scope!.parent; }
    final result = scope;
    return Choice(transition, result, chart.order.where((state) => configuration.contains(state) && descendant(state, result!)).toSet());
  }
  bool matches(Transition transition, Trigger trigger) {
    if (trigger is AlwaysTrigger) return transition.type == 'always';
    if (trigger is TimerTrigger) return identical(transition, trigger.transition);
    final event = (trigger as EventTrigger).event;
    return transition.type == 'event' && transition.descriptors.any((descriptor) =>
        descriptor == '*' || descriptor == event.name || event.name.startsWith('$descriptor.'));
  }
  List<Choice> select(Trigger trigger) {
    final candidates = <Choice>[], seen = <Transition>{};
    for (final leaf in chart.order) {
      if (!atomic(leaf) || !configuration.contains(leaf)) continue;
      Transition? found;
      for (State state = leaf; state != chart.root && found == null; state = state.parent!) {
        for (final transition in state.transitions) {
          if (!matches(transition, trigger)) continue;
          bool enabled = true;
          try { enabled = transition.guard == null || evaluate(transition.guard!) != 0; }
          on EvaluationError { enqueue('error.execution'); enabled = false; }
          if (enabled) { found = transition; break; }
        }
      }
      if (found != null && seen.add(found)) candidates.add(choice(found));
    }
    final chosen = <Choice>[], exited = <State>{};
    for (final choice in candidates) {
      if (choice.exits.any(exited.contains)) continue;
      chosen.add(choice);
      exited.addAll(choice.exits);
    }
    return chosen;
  }
  List<State> closeEntry(Set<State> set) {
    bool changed = true;
    while (changed) {
      changed = false;
      for (final state in set.toList()) {
        final children = parallel(state) ? childStates(state)
            : compound(state) && !childStates(state).any(set.contains) ? [initial(state, chart)] : <State>[];
        for (final child in children) { if (set.add(child)) changed = true; }
      }
    }
    return chart.order.where(set.contains).toList();
  }
  bool complete(State state) {
    if (atomic(state)) return false;
    if (compound(state)) return childStates(state).any((child) => child.kind == 'final' && configuration.contains(child));
    return parallel(state) && childStates(state).every(complete);
  }
  void enter(List<State> states) {
    for (final state in states) {
      configuration.add(state);
      state.entered++;
      state.enteredAt = time;
      for (final transition in state.transitions) {
        if (transition.type == 'timer') reservations.add(TimerReservation(time + transition.delay, ++serial, transition));
      }
      for (final list in state.entries) { actionList(list); }
      if (state.kind == 'final') {
        enqueue('done.state.${state.parent!.name}');
        final grandparent = state.parent!.parent!;
        if (parallel(grandparent) && childStates(grandparent).every(complete)) enqueue('done.state.${grandparent.name}');
      }
    }
  }
  String display(Trigger trigger) {
    if (trigger is AlwaysTrigger) return 'always';
    if (trigger is TimerTrigger) return 'after(${trigger.transition.delay})@${trigger.transition.source.name}';
    final event = (trigger as EventTrigger).event;
    return '${event.name}${event.value == 0 ? '' : '=${event.value}'}';
  }
  void microstep(List<Choice> chosen, Trigger trigger) {
    final exits = <State>{for (final choice in chosen) ...choice.exits};
    for (final history in chart.order) {
      if (history.kind == 'history' && exits.contains(history.parent)) {
        history.history = chart.order.where((state) => configuration.contains(state)
            && (history.mode == 'deep' ? atomic(state) && descendant(state, history.parent!)
                : state.parent == history.parent && state.kind != 'history')).toList();
      }
    }
    final set = <State>{};
    for (final choice in chosen) {
      if (choice.transition.kind == 'internal') continue;
      for (final target in effective(choice.transition)) {
        for (State? state = target; state != choice.scope; state = state!.parent) { set.add(state!); }
      }
    }
    final entries = closeEntry(set), leaving = chart.order.where(exits.contains).toList().reversed.toList();
    if (trace) output.add('[t=$time] ${display(trigger)} (${names(chosen.map((choice) => choice.transition.source))}): exit ${names(leaving)}; enter ${names(entries)}');
    for (final state in leaving) {
      for (final list in state.exits) { actionList(list); }
      configuration.remove(state);
      state.dwell += time - state.enteredAt;
      reservations.removeWhere((item) => item is TimerReservation && item.transition.source == state);
    }
    for (final choice in chosen) { actionList(choice.transition.actions); choice.transition.source.taken++; }
    enter(entries);
  }
  void macrostep(Trigger trigger) {
    macrosteps++;
    int count = 0;
    void perform(List<Choice> chosen, Trigger cause) {
      if (count == 1000) { output.add('LIVELOCK t=$time'); halted = true; return; }
      count++;
      microsteps++;
      microstep(chosen, cause);
    }
    if (trigger is StartTrigger) {
      data = 0;
      enter(closeEntry({initial(chart.root, chart)}));
    } else {
      data = trigger is TimerTrigger ? 0 : (trigger as EventTrigger).event.value;
      final chosen = select(trigger);
      if (chosen.isNotEmpty) perform(chosen, trigger);
    }
    while (!halted) {
      data = 0;
      final always = AlwaysTrigger();
      final chosen = select(always);
      if (chosen.isNotEmpty) { perform(chosen, always); continue; }
      if (queue.isEmpty) break;
      final event = queue.removeFirst(), cause = EventTrigger(event);
      data = event.value;
      final selected = select(cause);
      if (selected.isNotEmpty) perform(selected, cause);
    }
  }
  List<Reservation> sortedReservations() => List<Reservation>.of(reservations)
    ..sort((a, b) => a.due != b.due ? a.due.compareTo(b.due) : a.serial.compareTo(b.serial));
  Reservation? nextReservation() {
    Reservation? result;
    for (final item in reservations) {
      if (result == null || item.due < result.due || item.due == result.due && item.serial < result.serial) result = item;
    }
    return result;
  }
  void script(String line) {
    if (halted) return;
    final words = line.split(' '), command = words[0];
    if (command == 'event') {
      macrostep(EventTrigger(ChartEvent(words[1], words.length == 3 ? int.parse(words[2]) : 0)));
    } else if (command == 'tick') {
      final finish = time + int.parse(words[1]);
      while (!halted) {
        final first = nextReservation();
        if (first == null || first.due > finish) break;
        reservations.remove(first);
        time = first.due;
        macrostep(first is TimerReservation ? TimerTrigger(first.transition) : EventTrigger((first as SendReservation).event));
      }
      if (!halted) time = finish;
    } else if (command == 'set') {
      if (!variables.containsKey(words[1])) { output.add('error: unknown variable ${words[1]}'); }
      else { variables[words[1]] = int.parse(words[2]); }
    } else if (command == 'trace') { trace = words[1] == 'on'; }
    else if (command == 'eval') {
      final text = line.substring(5), parsed = expression(line.substring(5));
      final error = chart.checkReferences(parsed.references);
      if (error != null) { output.add('error: $error'); }
      else {
        data = 0;
        try { output.add('$text -> ${evaluate(parsed)}'); }
        on EvaluationError { output.add('error: division by zero'); }
      }
    } else if (command == 'dump') {
      output.add('dump t=$time');
      for (final state in chart.order) { if (configuration.contains(state)) output.add('${' ' * (2 * state.depth)}${state.name}'); }
      final variableNames = variables.keys.toList()..sort();
      for (final name in variableNames) { output.add('  var $name = ${variables[name]}'); }
      for (final state in chart.order) {
        if (state.kind == 'history' && state.history != null) output.add('  history ${state.name} = ${names(state.history!)}');
      }
      for (final reservation in sortedReservations()) {
        if (reservation is TimerReservation) {
          output.add('  timer ${reservation.due} after(${reservation.transition.delay})@${reservation.transition.source.name}');
        } else {
          final event = (reservation as SendReservation).event;
          output.add('  send ${reservation.due} ${event.name} ${event.value}');
        }
      }
    }
  }
  void statistics() {
    output.add('end t=$time macrosteps=$macrosteps microsteps=$microsteps');
    for (final state in chart.order) {
      if (state.kind != 'history') output.add('  ${state.name} entered=${state.entered} taken=${state.taken} time=${state.dwell + (configuration.contains(state) ? time - state.enteredAt : 0)}');
    }
  }
}

void main() {
  final output = <String>[];
  final count = int.parse(stdin.readLineSync()!);
  int line = 1;
  for (int chartNumber = 0; chartNumber < count; chartNumber++) {
    final name = stdin.readLineSync()!.substring(6);
    line++;
    final definitions = <(String, int)>[], script = <String>[];
    while (true) {
      final text = stdin.readLineSync()!;
      line++;
      if (text == 'RUN') break;
      definitions.add((text, line));
    }
    while (true) {
      final text = stdin.readLineSync()!;
      line++;
      if (text == 'END') break;
      script.add(text);
    }
    output.add('chart $name');
    final chart = build(definitions);
    if (chart.errors.isNotEmpty) {
      final errorLines = chart.errors.keys.toList()..sort();
      for (final number in errorLines) { output.add('error line $number: ${chart.errors[number]}'); }
      continue;
    }
    warnings(chart, output);
    final machine = Machine(chart, output);
    machine.macrostep(StartTrigger());
    for (final text in script) { machine.script(text); }
    machine.statistics();
  }
  stdout.write('${output.join('\n')}\n');
}
