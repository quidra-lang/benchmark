using System;
using System.Linq;

string[] words = { "listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist", "earth", "onset", "heart", "tones" };
foreach (var group in words.GroupBy(word => string.Concat(word.Order())))
    Console.WriteLine(string.Join(" ", group));
