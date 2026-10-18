using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
foreach (string text in new[] { "Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?" }) {
    var encoded = new System.Text.StringBuilder();
    for (int i = 0; i < text.Length; i += 3) {
        int remaining = text.Length - i;
        int bits = text[i] << 16;
        if (remaining > 1) bits |= text[i + 1] << 8;
        if (remaining > 2) bits |= text[i + 2];
        encoded.Append(alphabet[(bits >> 18) & 63]);
        encoded.Append(alphabet[(bits >> 12) & 63]);
        encoded.Append(remaining > 1 ? alphabet[(bits >> 6) & 63] : '=');
        encoded.Append(remaining > 2 ? alphabet[bits & 63] : '=');
    }
    Console.WriteLine($"\"{text}\" -> \"{encoded}\"");
}
