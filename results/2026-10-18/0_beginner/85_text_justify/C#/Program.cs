using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose " +
    "through careful names, small functions and honest tests. When a team agrees on shared rules for " +
    "internationalization, documentation and code review, every newcomer can read the code quickly, change it " +
    "safely and ship new improvements with confidence instead of fear, week after week.";
var lines = new List<List<string>>();
var current = new List<string>();
int letters = 0;
foreach (string word in paragraph.Split(' ')) {
    if (current.Count > 0 && letters + current.Count + word.Length > 30) {
        lines.Add(current);
        current = new List<string>();
        letters = 0;
    }
    current.Add(word);
    letters += word.Length;
}
if (current.Count > 0) lines.Add(current);
for (int i = 0; i < lines.Count; i++) {
    var words = lines[i];
    string text;
    if (i == lines.Count - 1 || words.Count == 1) text = string.Join(" ",words).PadRight(30);
    else {
        int spaces = 30 - words.Sum(w => w.Length), gaps = words.Count - 1;
        var line = new System.Text.StringBuilder(words[0]);
        for (int j = 1; j < words.Count; j++) {
            line.Append(' ',spaces / gaps + (j - 1 < spaces % gaps ? 1 : 0));
            line.Append(words[j]);
        }
        text = line.ToString();
    }
    Console.WriteLine($"|{text}|");
}
