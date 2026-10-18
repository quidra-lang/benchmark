using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] matches = { "Lions 0-3 Bears",
    "Tigers 2-2 Wolves",
    "Eagles 4-0 Sharks",
    "Bears 0-1 Sharks",
    "Wolves 2-1 Eagles",
    "Lions 0-1 Tigers",
    "Tigers 3-3 Bears",
    "Eagles 2-2 Lions",
    "Sharks 2-2 Wolves",
    "Bears 3-1 Wolves",
    "Lions 2-0 Sharks",
    "Tigers 2-1 Eagles",
    "Eagles 1-0 Bears",
    "Sharks 2-0 Tigers",
    "Wolves 2-1 Lions" };
string[] names = { "Lions","Tigers","Eagles","Sharks","Wolves","Bears" };
int[,] stats = new int[6,6];
foreach (string match in matches) {
    string[] parts = match.Split(' '), goals = parts[1].Split('-');
    int home = Array.IndexOf(names,parts[0]), away = Array.IndexOf(names,parts[2]);
    int h = int.Parse(goals[0],CultureInfo.InvariantCulture), a = int.Parse(goals[1],CultureInfo.InvariantCulture);
    stats[home,0]++;
    stats[away,0]++;
    stats[home,4] += h;
    stats[home,5] += a;
    stats[away,4] += a;
    stats[away,5] += h;
    if (h == a) {
        stats[home,2]++;
        stats[away,2]++;
    } else {
        stats[h > a ? home : away,1]++;
        stats[h > a ? away : home,3]++;
    }
}
int[] order = Enumerable.Range(0,6).OrderByDescending(i => 3 * stats[i,1] + stats[i,2])
    .ThenByDescending(i => stats[i,4] - stats[i,5]).ThenByDescending(i => stats[i,4])
    .ThenBy(i => names[i],StringComparer.Ordinal).ToArray();
for (int position = 0; position < 6; position++) {
    int i = order[position], gd = stats[i,4] - stats[i,5];
    string difference = (gd > 0 ? "+" : "") + gd;
    Console.WriteLine($"{position + 1}. {names[i]} P={stats[i,0]} W={stats[i,1]} D={stats[i,2]} " +
        $"L={stats[i,3]} GF={stats[i,4]} GA={stats[i,5]} GD={difference} Pts={3 * stats[i,1] + stats[i,2]}");
}
