class EvaluationError implements Exception {
    final String message;
    EvaluationError(this.message);
}

class Parser {
    final List<String> tokens;
    final Map<String, int> variables;
    int position;
    Parser(this.tokens, this.variables, this.position);
    bool at(String s) => position < tokens.length && tokens[position] == s;
    int expression() {
        var result = term();
        while (at('+') || at('-')) {
            final op = tokens[position++], right = term();
            result = op == '+' ? result + right : result - right;
        }
        return result;
    }

    int term() {
        var result = unary();
        while (at('*') || at('/')) {
            final op = tokens[position++], right = unary();
            if (op == '/' && right == 0)
                throw EvaluationError('division by zero');
            result = op == '*' ? result * right : result ~/ right;
        }
        return result;
    }

    int unary() {
        if (at('-')) {
            position++;
            return -unary();
        }
        return primary();
    }

    int primary() {
        if (at('(')) {
            position++;
            final result = expression();
            position++;
            return result;
        }
        final token = tokens[position++];
        if (RegExp(r'^\d').hasMatch(token))
            return int.parse(token);
        return variables[token] ?? (throw EvaluationError('undefined variable $token'));
    }
}

void main() {
    const lines = ['width = 12', 'height = width - 5', 'area = width * height', '(area + 6) / 4',
        'shift = -area / 8 + 3', 'height = 100 / (height - 7) + bonus', 'volume = area * depth', 'width = (width+3)*-(2-4)',
        'width * shift - height'];
    final variables = <String, int>{};
    for (final line in lines) {
        final tokens = RegExp(r'\d+|[a-z]+|[()+*/=\-]').allMatches(line).map((m) => m.group(0)!).toList(),
            assignment = tokens.length > 1 && tokens[1] == '=';
        final parser = Parser(tokens, variables, assignment ? 2 : 0);
        try {
            final result = parser.expression();
            if (assignment) {
                variables[tokens[0]] = result;
                print('${tokens[0]} = $result');
            } else {
                print(result);
            }
        } on EvaluationError catch (error) {
            print('error: ${error.message}');
        }
    }
}
