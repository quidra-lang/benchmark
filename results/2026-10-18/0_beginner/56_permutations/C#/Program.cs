using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static void Permute(string prefix, bool[] used, ref int count) {
    if (prefix.Length == 4) {
        Console.WriteLine($"{++count}: {prefix}");
        return;
    }
    for (int i = 0; i < 4; i++) if (!used[i]) {
        used[i] = true;
        Permute(prefix + "ABCD"[i], used, ref count);
        used[i] = false;
    }
}
int count = 0;
Permute("",new bool[4],ref count);
