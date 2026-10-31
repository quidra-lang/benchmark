part of 'main.dart';

const na = 'NOT_APPLICABLE',
    ip = 'INDETERMINATE{P}',
    id = 'INDETERMINATE{D}',
    idp = 'INDETERMINATE{DP}';

class TargetResult {
  final String state, reason;
  TargetResult(this.state, [this.reason = '']);
}

class ChildState {
  final TargetResult? target;
  final Evaluation? result;
  ChildState({this.target, this.result});
}

bool definite(String d) => d == 'PERMIT' || d == 'DENY';
bool indeterminate(String d) => d == ip || d == id || d == idp;
(String, String, List<ChildState>) combine(
  String algorithm,
  List<Element> children,
  Evaluation Function(Element) evaluate,
  TargetResult Function(Element) target,
) {
  final states = List.generate(children.length, (_) => ChildState());
  if (algorithm == 'only-one-applicable') {
    var matched = -1;
    for (var i = 0; i < children.length; i++) {
      final t = target(children[i]);
      states[i] = ChildState(target: t);
      if (t.state == 'INDETERMINATE') return (idp, t.reason, states);
      if (t.state == 'MATCH') {
        if (matched >= 0)
          return (
            idp,
            'multiple applicable ${children[matched].id} ${children[i].id}',
            states,
          );
        matched = i;
      }
    }
    if (matched < 0) return (na, '', states);
    final result = evaluate(children[matched]);
    states[matched] = ChildState(result: result);
    return (result.decision, result.reason, states);
  }
  final decisions = <String>{};
  var firstError = '';
  for (var i = 0; i < children.length; i++) {
    final result = evaluate(children[i]), d = result.decision;
    states[i] = ChildState(result: result);
    decisions.add(d);
    if (indeterminate(d) && firstError.isEmpty) firstError = result.reason;
    if (algorithm == 'first-applicable' && d != na)
      return (d, result.reason, states);
    if ((algorithm == 'deny-overrides' || algorithm == 'permit-unless-deny') &&
        d == 'DENY')
      return ('DENY', '', states);
    if ((algorithm == 'permit-overrides' ||
            algorithm == 'deny-unless-permit') &&
        d == 'PERMIT')
      return ('PERMIT', '', states);
  }
  if (algorithm == 'deny-unless-permit') return ('DENY', '', states);
  if (algorithm == 'permit-unless-deny') return ('PERMIT', '', states);
  if (algorithm == 'first-applicable') return (na, '', states);
  bool has(String d) => decisions.contains(d);
  var d = na;
  if (algorithm == 'deny-overrides') {
    if (has(idp) || has(id) && (has(ip) || has('PERMIT'))) {
      d = idp;
    } else if (has(id)) {
      d = id;
    } else if (has('PERMIT')) {
      d = 'PERMIT';
    } else if (has(ip)) {
      d = ip;
    }
  } else {
    if (has(idp) || has(ip) && (has(id) || has('DENY'))) {
      d = idp;
    } else if (has(ip)) {
      d = ip;
    } else if (has('DENY')) {
      d = 'DENY';
    } else if (has(id)) {
      d = id;
    }
  }
  return (d, indeterminate(d) ? firstError : '', states);
}
