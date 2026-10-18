using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

foreach (string id in new[] { "user_name","maxRetryCount","ShoppingCartItem","background-color","get_last_login_time","isEmailAddressValid" }) {
    string[] words = System.Text.RegularExpressions.Regex.Split(id,"[_-]|(?=[A-Z])").Where(w => w.Length > 0).Select(w => w.ToLowerInvariant()).ToArray();
    string[] capitals = words.Select(w => char.ToUpperInvariant(w[0]) + w[1..]).ToArray();
    string camel = words[0] + string.Concat(capitals.Skip(1));
    Console.WriteLine($"{id}: snake={string.Join("_",words)}, camel={camel}, pascal={string.Concat(capitals)}, kebab={string.Join("-",words)}");
}
