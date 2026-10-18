using System;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
string[] names = { "Tanaka","Suzuki","Yamada","Ito","Kato","Mori" };
int[][] scores = { new[] {78,85,94}, new[] {88,74,82}, new[] {65,90,71}, new[] {80,79,85}, new[] {92,88,95}, new[] {70,62,78} };
int[] totals = scores.Select(row => row.Sum()).ToArray();
int[] order = Enumerable.Range(0,names.Length).OrderByDescending(i => totals[i]).ThenBy(i => names[i],StringComparer.Ordinal).ToArray();
int rank = 0, previous = -1;
for (int position = 0; position < order.Length; position++) {
    int i = order[position];
    if (totals[i] != previous) rank = position + 1;
    previous = totals[i];
    Console.WriteLine($"{rank}. {names[i]} total={totals[i]} average={totals[i] / 3.0:F2}");
}
