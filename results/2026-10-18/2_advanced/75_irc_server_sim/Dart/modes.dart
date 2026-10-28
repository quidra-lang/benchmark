part of 'main.dart';

class ModeItem {
  final String sign, flag;
  String arg;
  bool has;
  ModeItem(this.sign, this.flag, [this.arg = '', this.has = false]);
}

List<ModeItem> modeItems(String mode, List<String> args) {
  final out = <ModeItem>[];
  var sign = '+', at = 0;
  for (var i = 0; i < mode.length; i++) {
    final flag = mode[i];
    if (flag == '+' || flag == '-') {
      sign = flag;
      continue;
    }
    final item = ModeItem(sign, flag),
        take =
            flag == 'o' ||
            flag == 'v' ||
            flag == 'b' ||
            flag == 'k' ||
            flag == 'l' && sign == '+';
    if (take && at < args.length) {
      item.arg = args[at++];
      item.has = true;
    }
    if (flag == 'k' && sign == '-') {
      item.arg = '*';
      item.has = true;
    }
    if (flag == 'l' &&
        sign == '+' &&
        (!item.has ||
            !digits(item.arg) ||
            item.arg.length > 4 ||
            number(item.arg) < 1))
      item.has = false;
    out.add(item);
  }
  return out;
}

String changeString(List<ModeItem> changes) {
  final mode = StringBuffer(), args = <String>[];
  var last = '';
  for (final c in changes) {
    if (c.sign != last) {
      mode.write(c.sign);
      last = c.sign;
    }
    mode.write(c.flag);
    if (c.has) args.add(c.arg);
  }
  return args.isEmpty ? mode.toString() : '$mode ${args.join(' ')}';
}
