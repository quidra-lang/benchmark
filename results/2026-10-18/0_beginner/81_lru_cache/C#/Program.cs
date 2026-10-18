using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var cache = new List<char>();
int hits = 0, misses = 0;
foreach (char key in "BACBDABEADDCAEB") {
    string status;
    if (cache.Remove(key)) {
        hits++;
        status = "hit";
    } else {
        misses++;
        status = "miss";
        if (cache.Count == 3) {
            status += $", evict {cache[^1]}";
            cache.RemoveAt(cache.Count - 1);
        }
    }
    cache.Insert(0,key);
    Console.WriteLine($"{key}: {status} [{string.Join(" ",cache)}]");
}
Console.WriteLine($"hits: {hits} misses: {misses}");
