part of 'main.dart';

class Command {
  final int indent;
  final bool flat;
  final Doc doc;
  Command(this.indent, this.flat, this.doc);
}

void pushChildren(List<Command> stack, Command c) {
  for (var j = c.doc.children.length - 1; j >= 0; j--) {
    stack.add(Command(c.indent, c.flat, c.doc.children[j]));
  }
}

bool fits(int remaining, Command first, List<Command> original) {
  if (remaining < 0) return false;
  final stack = [first];
  var unused = original.length - 1;
  while (stack.isNotEmpty || unused >= 0) {
    if (stack.isEmpty) stack.add(original[unused--]);
    final c = stack.removeLast(), d = c.doc;
    switch (d.kind) {
      case 'text':
        remaining -= d.text.length;
        break;
      case 'if_break':
        remaining -= (c.flat ? d.other : d.text).length;
        break;
      case 'line':
        if (!c.flat) return true;
        remaining--;
        break;
      case 'softline':
        if (!c.flat) return true;
        break;
      case 'hardline':
        return true;
      case 'concat':
        pushChildren(stack, c);
        break;
      case 'group':
        stack.add(
          Command(c.indent, d.forced ? false : c.flat, d.children.first),
        );
        break;
      case 'nest':
      case 'align':
        stack.add(Command(c.indent, c.flat, d.children.first));
        break;
    }
    if (remaining < 0) return false;
  }
  return true;
}

List<String> printDoc(Doc doc, int width, int commentColumn) {
  final lines = <String>[],
      pending = <String>[],
      stack = [Command(0, false, doc)];
  var current = '', column = 0;
  void finalize() {
    var line = current.trimRight();
    if (pending.isNotEmpty) {
      final comments = pending.join(' ');
      if (commentColumn > 0 &&
          line.length < commentColumn - 1 &&
          commentColumn - 1 + comments.length <= width) {
        line += repeated(' ', commentColumn - 1 - line.length) + comments;
      } else {
        line += ' $comments';
      }
    }
    pending.clear();
    lines.add(line);
  }

  while (stack.isNotEmpty) {
    final c = stack.removeLast(), d = c.doc;
    var newline = false;
    switch (d.kind) {
      case 'text':
        current += d.text;
        column += d.text.length;
        break;
      case 'if_break':
        final value = c.flat ? d.other : d.text;
        current += value;
        column += value.length;
        break;
      case 'line':
        if (c.flat) {
          current += ' ';
          column++;
        } else {
          newline = true;
        }
        break;
      case 'softline':
        newline = !c.flat;
        break;
      case 'hardline':
        newline = true;
        break;
      case 'concat':
        pushChildren(stack, c);
        break;
      case 'nest':
        stack.add(Command(c.indent + d.number, c.flat, d.children.first));
        break;
      case 'align':
        stack.add(Command(column, c.flat, d.children.first));
        break;
      case 'suffix':
        pending.add(d.text);
        break;
      case 'group':
        var mode = 'flat', flat = true;
        if (!c.flat) {
          if (d.forced) {
            mode = 'forced';
            flat = false;
          } else if (!fits(
            width - column,
            Command(c.indent, true, d.children.first),
            stack,
          )) {
            mode = 'break';
            flat = false;
          }
        }
        d.mode = mode;
        stack.add(Command(c.indent, flat, d.children.first));
        break;
    }
    if (newline) {
      finalize();
      current = repeated(' ', c.indent);
      column = c.indent;
    }
  }
  finalize();
  return lines;
}
