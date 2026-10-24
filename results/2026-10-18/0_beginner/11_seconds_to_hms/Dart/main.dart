void main() {
    String two(int n) => n.toString().padLeft(2, '0');
    for (final s in [0, 59, 3725, 45296, 86400, 312047]) {
        print('$s seconds = ${two(s ~/ 3600)}:${two((s ~/ 60) % 60)}:${two(s % 60)}');
    }
}
