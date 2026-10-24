using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;

string[] queries = { "name=Alice+Smith&age=30&city=New%20York",
    "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
    "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
    "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips" };
for (int index = 0; index < queries.Length; index++) {
    var values = new SortedDictionary<string,List<string>>(StringComparer.Ordinal);
    foreach (string item in queries[index].Split('&')) {
        int equals = item.IndexOf('=');
        string key = WebUtility.UrlDecode(equals < 0 ? item : item[..equals]);
        string value = WebUtility.UrlDecode(equals < 0 ? "" : item[(equals + 1)..]);
        if (!values.ContainsKey(key)) values[key] = new List<string>();
        values[key].Add(value);
    }
    Console.WriteLine($"query {index + 1}:");
    foreach (var pair in values) {
        var quoted = pair.Value.Select(v => "\"" + v + "\"");
        Console.WriteLine($"  {pair.Key}: {string.Join(", ",quoted)}");
    }
}
