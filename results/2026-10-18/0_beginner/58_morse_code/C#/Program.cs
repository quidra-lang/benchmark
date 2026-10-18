using System;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
string[] codes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.".Split(' ');
var reverse = Enumerable.Range(0,codes.Length).ToDictionary(i => codes[i],i => alphabet[i]);
string message = "MEET ME AT PIER 9 AT 1745";
string encoded = string.Join(" / ",message.Split(' ').Select(word => string.Join(" ",word.Select(ch => codes[alphabet.IndexOf(ch)]))));
string decoded = string.Join(" ",encoded.Split(" / ").Select(word => string.Concat(word.Split(' ').Select(code => reverse[code]))));
Console.WriteLine(encoded);
Console.WriteLine(decoded);
