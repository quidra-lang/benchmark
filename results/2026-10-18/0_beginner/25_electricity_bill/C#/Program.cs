using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] names = { "Sato","Suzuki","Takahashi","Tanaka","Ito","Watanabe" };
int[] usages = { 85,120,254,300,438,176 };
int total = 0;
for (int i = 0; i < names.Length; i++) {
    int u = usages[i], bill = 900 + Math.Min(u, 120) * 30 + Math.Min(Math.Max(u - 120, 0), 180) * 36 + Math.Max(u - 300, 0) * 40;
    total += bill;
    Console.WriteLine($"{names[i]}: {u} kWh, {bill} yen");
}
Console.WriteLine($"total: {total} yen");
