part of 'main.dart';

class TreeNode {
  final String symbol;
  String mark;
  final List<TreeNode> children;
  TreeNode(this.symbol, {this.mark = '', List<TreeNode>? children})
    : children = children ?? [];
}

typedef InputToken = (String, int);

class StackItem {
  final String symbol;
  final TreeNode? node;
  StackItem(this.symbol, [this.node]);
}

class ParseResult {
  final TreeNode root;
  final trace = <List<String>>[],
      leftParse = <int>[],
      errors = <String>[],
      unknownErrors = <String>[],
      original = <String>[];
  int predicts = 0, matches = 0, skip = 0, pop = 0, missing = 0, maxStack = 0;
  bool accepted = false, language = false;
  ParseResult(this.root);
}

String treeLabel(TreeNode node) =>
    node.mark.isEmpty ? node.symbol : '${node.symbol} (${node.mark})';
ParseResult parseTokens(
  List<InputToken> tokens,
  Grammar g,
  Sets sets,
  ParseTable table,
) {
  final input = <InputToken>[...tokens, (endToken, tokens.length + 1)],
      root = TreeNode(g.start),
      stack = <StackItem>[StackItem(endToken), StackItem(g.start, root)],
      result = ParseResult(root);
  var cursor = 0;
  for (var step = 1; ; step++) {
    final item = stack.last,
        top = item.symbol,
        node = item.node,
        current = input[cursor],
        beforeStack = stack.map((s) => s.symbol).join(' '),
        beforeInput = input.skip(cursor).map((t) => t.$1).join(' ');
    result.maxStack = max(result.maxStack, stack.length);
    var action = '', event = '', terminate = false;
    if (top == endToken && current.$1 == endToken) {
      action = 'accept';
      terminate = true;
    } else if (top == endToken) {
      action = 'error: skip ${current.$1}';
      event = 'skip';
      cursor++;
      result.skip++;
    } else if (!isNonterminal(top)) {
      if (top == current.$1) {
        action = 'match ${current.$1}';
        stack.removeLast();
        cursor++;
        result.matches++;
      } else {
        action = 'error: missing $top';
        node!.mark = 'missing';
        stack.removeLast();
        result.missing++;
        event = 'missing';
      }
    } else if (table.choices.containsKey((top, current.$1))) {
      final number = table.choices[(top, current.$1)]!,
          p = table.productions[number - 1];
      action = 'predict $number: ${p.notation}';
      result.leftParse.add(number);
      stack.removeLast();
      final children = [for (final s in p.rhs) TreeNode(s)];
      if (children.isEmpty) {
        node!.children.add(TreeNode('%empty'));
      } else {
        node!.children.addAll(children);
        for (final child in children.reversed) {
          stack.add(StackItem(child.symbol, child));
        }
      }
      result.predicts++;
    } else if (current.$1 == endToken ||
        sets.follow[top]!.contains(current.$1)) {
      action = 'error: pop $top';
      node!.mark = 'error';
      stack.removeLast();
      result.pop++;
      event = 'pop';
    } else {
      action = 'error: skip ${current.$1}';
      cursor++;
      result.skip++;
      event = 'skip';
    }
    result.trace.add(['$step', beforeStack, beforeInput, action]);
    if (event.isNotEmpty) {
      final unexpected = current.$1 == endToken
          ? 'end of input'
          : '"${current.$1}" at token ${current.$2}';
      final expected = isNonterminal(top)
          ? [
              for (final t in [...sets.terminals, endToken])
                if (table.choices.containsKey((top, t)))
                  t == endToken ? t : '"$t"',
            ].join(' ')
          : top == endToken
          ? endToken
          : '"$top"';
      final recovery = event == 'pop'
          ? 'popped $top'
          : event == 'missing'
          ? 'inserted "$top"'
          : 'skipped "${current.$1}"';
      result.errors.add(
        'step $step: unexpected $unexpected; expected $expected; $recovery',
      );
    }
    if (terminate) {
      break;
    }
  }
  return result;
}
