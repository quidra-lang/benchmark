part of 'main.dart';

final numberPattern = RegExp(r'^(0|[1-9][0-9]*)$'),
    literalPattern = RegExp(r'^(0|-?[1-9][0-9]*)$');
bool validNumber(String token) =>
    token.length <= 6 && numberPattern.hasMatch(token);
bool validLiteral(String token) =>
    (token.startsWith('-') ? token.length - 1 : token.length) <= 6 &&
    literalPattern.hasMatch(token);

class Formula {
  final int variables;
  final List<List<int>> clauses;
  Formula(this.variables, this.clauses);
}

class CnfError implements Exception {
  final String message;
  CnfError(this.message);
}

Formula readDimacs(String filename) {
  int? variables, declared;
  final clauses = <List<int>>[];
  var partial = <int>[];
  final lines = readLines('input/$filename');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index],
        number = index + 1,
        tokens = line.split(' ').where((t) => t.isNotEmpty).toList();
    if (line.startsWith('c') || tokens.isEmpty) continue;
    if (tokens[0] == 'p') {
      if (declared != null) throw CnfError('duplicate header at line $number');
      if (tokens.length != 4 ||
          tokens[1] != 'cnf' ||
          !validNumber(tokens[2]) ||
          !validNumber(tokens[3]))
        throw CnfError('bad header at line $number');
      variables = int.parse(tokens[2]);
      declared = int.parse(tokens[3]);
      continue;
    }
    if (variables == null) throw CnfError('missing header');
    for (final token in tokens) {
      if (!validLiteral(token))
        throw CnfError('bad token $token at line $number');
      final literal = int.parse(token);
      if (literal.abs() > variables)
        throw CnfError('literal out of range $token at line $number');
      if (literal != 0) {
        partial.add(literal);
      } else {
        clauses.add(partial);
        partial = [];
      }
    }
  }
  if (variables == null) throw CnfError('missing header');
  if (partial.isNotEmpty) throw CnfError('unterminated clause');
  if (clauses.length != declared)
    throw CnfError(
      'clause count mismatch header=$declared found=${clauses.length}',
    );
  return Formula(variables, clauses);
}

List<String> modelLines(List<bool> model) {
  final tokens = [
    for (var v = 1; v < model.length; v++) '${model[v] ? v : -v}',
    '0',
  ];
  return [
    for (var start = 0; start < tokens.length; start += 10)
      'v ${tokens.sublist(start, math.min(start + 10, tokens.length)).join(' ')}',
  ];
}
