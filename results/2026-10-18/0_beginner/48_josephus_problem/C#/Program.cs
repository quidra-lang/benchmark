using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (var (n,k) in new[] { (7,3),(10,2),(41,3) }) {
    int index = 0; var people = Enumerable.Range(1,n).ToList(); var removed = new List<int>();
    while (people.Count > 0) { index = (index + k - 1) % people.Count; removed.Add(people[index]); people.RemoveAt(index); }
    Console.WriteLine($"n={n} k={k}: {string.Join(" ",removed)}");
    Console.WriteLine($"survivor: {removed[^1]}");
}
