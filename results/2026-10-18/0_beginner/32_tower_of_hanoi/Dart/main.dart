import 'dart:io';

void main() {
    final out = StringBuffer();
    var count = 0;
    void hanoi(int n, String source, String target, String auxiliary) {
        if (n == 0)
            return;
        hanoi(n - 1, source, auxiliary, target);
        out.writeln('move disk $n from $source to $target');
        count++;
        hanoi(n - 1, auxiliary, target, source);
    }
    hanoi(4, 'A', 'C', 'B');
    out.writeln('total moves: $count');
    stdout.write(out);
}
