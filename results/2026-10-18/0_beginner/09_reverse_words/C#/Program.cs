using System;

string sentence = "every program starts with a single line";
char[] characters = sentence.ToCharArray();
Array.Reverse(characters);
Console.WriteLine(new string(characters));
string[] words = sentence.Split(' ');
Array.Reverse(words);
Console.WriteLine(string.Join(" ", words));
