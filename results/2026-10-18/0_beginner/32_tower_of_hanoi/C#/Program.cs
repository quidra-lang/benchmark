using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static int Hanoi(int n, char source, char target, char auxiliary) {
    if (n == 0) return 0;
    int count = Hanoi(n - 1, source, auxiliary, target);
    Console.WriteLine($"move disk {n} from {source} to {target}");
    return count + 1 + Hanoi(n - 1, auxiliary, target, source);
}
Console.WriteLine($"total moves: {Hanoi(4, 'A', 'C', 'B')}");
