using System;
using System.Collections.Generic;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] values = { 3,8,11,15,19,24,27,31,36,42,47,53,58,64,70,77 };
foreach (int target in new[] { 42,3,77,31,50,1 }) {
    int lo = 0, hi = 15, found = -1;
    var probes = new List<int>();
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        probes.Add(mid);
        if (values[mid] == target) {
            found = mid;
            break;
        }
        if (values[mid] < target) lo = mid + 1; else hi = mid - 1;
    }
    Console.WriteLine($"{target}: probes {string.Join(" ", probes)} -> {(found >= 0 ? "index " + found : "not found")}");
}
