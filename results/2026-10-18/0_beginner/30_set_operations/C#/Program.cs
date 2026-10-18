using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var a = new HashSet<int> { 12,5,8,21,5,17,3,12,9 }; var b = new HashSet<int> { 8,14,21,6,14,3,25,6 };
var results = new[] { a.Union(b), a.Intersect(b), a.Except(b), a.Union(b).Except(a.Intersect(b)) };
string[] labels = { "union", "intersection", "difference", "symmetric difference" };
for (int i = 0; i < labels.Length; i++) Console.WriteLine($"{labels[i]}: {string.Join(" ", results[i].Order())}");
