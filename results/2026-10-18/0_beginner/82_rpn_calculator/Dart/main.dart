void main() {
    for (final expression in ['3 4 + 2 *', '-17 5 / 4 -3 * -', '1 2 + * 3', '15 7 1 1 + - / 3 * 2 1 1 + + -',
        '4 2 5 * + 1 3 2 * - 5 + /', '2 3 4 + 5', '46341 46339 * -2 /']) {
        final stack = <int>[];
        String? error;
        for (final token in expression.split(' ')) {
            if (token.length != 1 || !'+-*/'.contains(token)) {
                stack.add(int.parse(token));
                continue;
            }
            if (stack.length < 2) {
                error = 'stack underflow';
                break;
            }
            final b = stack.removeLast(), a = stack.removeLast();
            if (token == '/' && b == 0) {
                error = 'division by zero';
                break;
            }
            stack.add(switch (token) {
                '+' => a + b,
                '-' => a - b,
                '*' => a * b,
                '/' => a ~/ b,
                _ => throw StateError('operator')
            });
        }
        if (error == null && stack.length != 1)
            error = 'leftover operands';
        print('$expression => ${error==null?stack.single:'error: $error'}');
    }
}
