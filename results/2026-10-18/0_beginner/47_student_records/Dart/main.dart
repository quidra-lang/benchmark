void main() {
    final students = [('Tanaka', [78, 85, 94]), ('Suzuki', [88, 74, 82]), ('Yamada', [65, 90, 71]),
        ('Ito', [80, 79, 85]), ('Kato', [92, 88, 95]), ('Mori', [70, 62, 78])];
    int total((String, List<int>) s) => s.$2.reduce((a, b) => a + b);
    students.sort((a, b) {
        final c = total(b).compareTo(total(a));
        return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    var rank = 0, previous = -1;
    for (var i = 0; i < students.length; i++) {
        final s = students[i], t = total(s);
        if (t != previous)
            rank = i + 1;
        previous = t;
        print('$rank. ${s.$1} total=$t average=${(t / 3).toStringAsFixed(2)}');
    }
}
