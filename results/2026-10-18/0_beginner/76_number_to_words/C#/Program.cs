using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string UnderThousand(int n) {
    string[] ones = { "zero","one","two","three","four","five","six","seven","eight","nine",
        "ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen" };
    string[] tens = { "", "", "twenty","thirty","forty","fifty","sixty","seventy","eighty","ninety" };
    var parts = new List<string>();
    if (n >= 100) parts.Add(ones[n / 100] + " hundred");
    int remainder = n % 100;
    if (remainder >= 20) parts.Add(tens[remainder / 10] + (remainder % 10 > 0 ? "-" + ones[remainder % 10] : ""));
    else if (remainder > 0) parts.Add(ones[remainder]);
    return string.Join(" ",parts);
}
foreach (int n in new[] { 0,13,40,100,568,71000,300019,999999 }) {
    var parts = new List<string>();
    if (n == 0) parts.Add("zero");
    if (n >= 1000) parts.Add(UnderThousand(n / 1000) + " thousand");
    if (n % 1000 > 0) parts.Add(UnderThousand(n % 1000));
    Console.WriteLine($"{n}: {string.Join(" ",parts)}");
}
