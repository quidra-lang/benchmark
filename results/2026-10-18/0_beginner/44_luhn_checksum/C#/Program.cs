using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (string number in new[] { "688126340316","0128469655154","92181914514156","177332430060552","7982377590420309","9884593615513906" }) {
    int sum = 0;
    for (int i = number.Length - 1, position = 1; i >= 0; i--, position++) {
        int digit = number[i] - '0';
        if (position % 2 == 0) {
            digit *= 2;
            if (digit > 9) digit -= 9;
        }
        sum += digit;
    }
    int expected = (10 - (sum - (number[^1] - '0')) % 10) % 10;
    Console.WriteLine(number + ": " + (sum % 10 == 0 ? "valid" : $"invalid (expected check digit {expected})"));
}
