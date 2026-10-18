using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var groups = new Dictionary<string,List<string>>(); var keys = new List<string>();
foreach (string word in new[] { "listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones" }) { string key = string.Concat(word.Order()); if (!groups.ContainsKey(key)) { groups[key] = new List<string>(); keys.Add(key); } groups[key].Add(word); }
foreach (string key in keys) Console.WriteLine(string.Join(" ", groups[key]));
