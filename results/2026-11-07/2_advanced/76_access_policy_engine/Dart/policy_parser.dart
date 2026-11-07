part of 'main.dart';

class Clause {
  final String attribute, operator;
  final bool mandatory;
  final Value literal;
  Clause(this.attribute, this.operator, this.mandatory, this.literal);
}

typedef TargetLine = List<List<Clause>>;

class Argument {
  final String name;
  final Expr expression;
  Argument(this.name, this.expression);
}

class Attachment {
  final String kind, effect, id;
  final List<Argument> args = [];
  Attachment(this.kind, this.effect, this.id);
}

class Element {
  final String kind, id, algorithm, effect;
  Element? parent;
  final List<Element> children = [];
  final List<TargetLine> targets = [];
  Expr? condition;
  final List<Attachment> attachments = [];
  Element(this.kind, this.id, {this.algorithm = '', this.effect = ''});
}

TargetLine parseTarget(String s) => [
  for (final alt in s.split(' | '))
    [for (final part in alt.split(' & ')) parseClause(part)],
];
Clause parseClause(String part) {
  final a = part.split(' '),
      ref = a[0],
      mandatory = ref.endsWith('!'),
      literal = a[2].startsWith('"')
          ? Value.string(a[2].substring(1, a[2].length - 1))
          : parseValue(a[2]);
  return Clause(
    mandatory ? ref.substring(0, ref.length - 1) : ref,
    a[1],
    mandatory,
    literal,
  );
}

(Element, List<Element>, List<Element>) readPolicies() {
  Element? root;
  final stack = <Element>[], elements = <Element>[], rules = <Element>[];
  for (final raw in readLines('input/policies.txt')) {
    final line = raw.trimLeft();
    if (line.isEmpty || line.startsWith('#')) continue;
    final space = line.indexOf(' '),
        keyword = space < 0 ? line : line.substring(0, space),
        rest = space < 0 ? '' : line.substring(space + 1);
    if (keyword == 'END') {
      stack.removeLast();
      continue;
    }
    if (['POLICYSET', 'POLICY', 'RULE'].contains(keyword)) {
      final v = rest.split(' '),
          e = Element(
            keyword.toLowerCase(),
            v[0],
            algorithm: keyword == 'RULE' ? '' : v[1],
            effect: keyword == 'RULE' ? v[1] : '',
          );
      if (keyword == 'RULE') rules.add(e);
      if (stack.isEmpty) {
        root = e;
      } else {
        e.parent = stack.last;
        stack.last.children.add(e);
      }
      elements.add(e);
      stack.add(e);
      continue;
    }
    final e = stack.last;
    switch (keyword) {
      case 'TARGET':
        e.targets.add(parseTarget(rest));
        break;
      case 'CONDITION':
        e.condition = parseExpr(rest);
        break;
      case 'OBLIGATION':
      case 'ADVICE':
        final first = rest.indexOf(' '),
            second = rest.indexOf(' ', first + 1),
            a = Attachment(
              keyword.toLowerCase(),
              rest.substring(0, first),
              second < 0
                  ? rest.substring(first + 1)
                  : rest.substring(first + 1, second),
            );
        if (second >= 0) {
          for (final part in rest.substring(second + 1).split(';')) {
            final arg = part.trim(), i = arg.indexOf('=');
            a.args.add(
              Argument(arg.substring(0, i), parseExpr(arg.substring(i + 1))),
            );
          }
        }
        e.attachments.add(a);
        break;
    }
  }
  return (root!, elements, rules);
}
