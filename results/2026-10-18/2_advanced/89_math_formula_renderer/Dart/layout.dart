part of 'main.dart';

class ElementTypes {
  String left, right;
  ElementTypes(this.left, this.right);
}

ElementTypes elementTypes(Node n) {
  var kind = 'ordinary';
  switch (n.kind) {
    case 'symbol':
      kind = symbolTypes[n.value] ?? 'ordinary';
      break;
    case 'command':
      kind = symbolCommands[n.value]!.type;
      break;
    case 'delim':
      return ElementTypes('open', 'close');
    case 'script':
      return elementTypes(n.base!);
    case 'overset':
    case 'underset':
      return elementTypes(n.items[1]);
  }
  return ElementTypes(kind, kind);
}

List<ElementTypes> convertedTypes(List<Node> nodes) {
  final out = nodes.map(elementTypes).toList();
  for (var i = 0; i < out.length; i++) {
    if (out[i].left == 'binary' &&
        (i == 0 ||
            containsWord(
              'binary operator relation open punctuation',
              out[i - 1].right,
            )))
      out[i] = ElementTypes('ordinary', 'ordinary');
    if (i > 0 &&
        containsWord('relation close punctuation', out[i].left) &&
        out[i - 1].right == 'binary')
      out[i - 1] = ElementTypes('ordinary', 'ordinary');
  }
  if (out.isNotEmpty && out.last.right == 'binary')
    out[out.length - 1] = ElementTypes('ordinary', 'ordinary');
  return out;
}

bool wordElement(Node n) => n.kind == 'script'
    ? wordElement(n.base!)
    : n.kind == 'command' &&
          (greek.contains(n.value.substring(1)) || n.value == r'\infty');
bool alphanumeric(Node n) {
  if (n.kind == 'identifier' || n.kind == 'number' || wordElement(n))
    return true;
  if (n.kind == 'script') return alphanumeric(n.base!);
  return n.kind == 'accent' &&
      containsWord('overline hat vec dot tilde', n.value) &&
      alphanumeric(n.items.first);
}

const typeIndex = {
  'ordinary': 0,
  'operator': 1,
  'binary': 2,
  'relation': 3,
  'open': 4,
  'close': 5,
  'punctuation': 6,
};
const spacingTable = [
  ['0', '1', 'B', 'R', '0', '0', '0'],
  ['1', '1', '-', 'R', '0', '0', '0'],
  ['B', 'B', '-', '-', 'B', '-', '-'],
  ['R', 'R', '-', '0', 'R', '0', '0'],
  ['0', '0', '-', '0', '0', '0', '0'],
  ['0', '1', 'B', 'R', '0', '0', '0'],
  ['P', 'P', '-', 'P', 'P', 'P', 'P'],
];
(List<ElementTypes>, List<int>) spacing(
  List<Node> nodes,
  bool script,
  Map<String, int> params,
) {
  final types = convertedTypes(nodes),
      gaps = List.filled(max(0, nodes.length - 1), 0);
  for (var i = 0; i < gaps.length; i++) {
    if (alphanumeric(nodes[i]) &&
        alphanumeric(nodes[i + 1]) &&
        (wordElement(nodes[i]) || wordElement(nodes[i + 1]))) {
      gaps[i] = 1;
      continue;
    }
    final entry =
        spacingTable[typeIndex[types[i].right]!][typeIndex[types[i + 1].left]!];
    if (entry == '1') gaps[i] = 1;
    if (!script) {
      switch (entry) {
        case 'B':
          gaps[i] = params['bin_space']!;
          break;
        case 'R':
          gaps[i] = params['rel_space']!;
          break;
        case 'P':
          gaps[i] = params['punct_space']!;
          break;
      }
    }
  }
  return (types, gaps);
}

Box rowBox(
  List<Box> children,
  List<int> gaps,
  String description, [
  List<String>? roles,
]) {
  var ascent = 0, descent = 0, width = 0;
  for (final child in children) {
    ascent = max(ascent, child.baseline);
    descent = max(descent, child.descent);
    width += child.width;
  }
  for (final gap in gaps) {
    width += gap;
  }
  final out = Box(width, ascent + descent + 1, ascent, description);
  var x = 0;
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    out.add(child, x, ascent - child.baseline, roles?[i] ?? '');
    x += child.width;
    if (i < gaps.length) x += gaps[i];
  }
  return out;
}
