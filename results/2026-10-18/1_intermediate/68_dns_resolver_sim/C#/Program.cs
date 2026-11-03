using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

class Program
{
    static readonly string[] Types = ["A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA"];
    static readonly string[] Kinds = ["ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT"];

    class Problem(string message) : Exception(message) { } record ResourceRecord(string Owner, int Ttl, int Type, string Data)
    {
        public override string ToString() => $"{Owner} {Ttl} {Types[Type]} {Data}";
    }

    class Zone(string origin, uint server, int line)
    {
        public string Origin = origin;
        public uint Server = server;
        public int Line = line;
        public List<ResourceRecord> Records = [];
        public ResourceRecord? Soa => Records.Find(record => record.Type == 3);
    }

    record CacheEntry(string Kind, List<ResourceRecord> Records, int Expiry);

    class Response(string kind)
    {
        public string Kind = kind, Cut = ".";
        public List<ResourceRecord> Answer = [], Authority = [], Additional = [];
        public string Description => Kind == "REFERRAL" ? Kind + " " + Cut : Kind == "CNAME" ? Kind + " " + Answer[0].Data : Kind;
    }

    record Result(string Status, List<ResourceRecord> Answer);
    static readonly List<uint> Roots = [];
    static readonly List<Zone> Zones = [];

    static Zone? current;
    static readonly HashSet<uint> Down = [];
    static readonly Dictionary<(string Name, int Type), CacheEntry> Cache = [];
    static readonly SortedDictionary<uint, int[]> Queries = [];
    static readonly int[] Resolutions = new int[4];

    static int now, minTtl = 1, maxTtl = 86400, negTtl = 3600, hits;

    static void Require(bool condition, string reason)
    {
        if (!condition) throw new Problem(reason);
    }

    static bool Matches(string text, string pattern) => Regex.IsMatch(text, @"\A(?:" + pattern + @")\z");

    static int TypeIndex(string word)
    {
        int type = Array.IndexOf(Types, word);
        Require(type >= 0, "bad type " + word);
        return type;
    }

    static string Name(string word, bool wildcard, string? origin)
    {
        if (origin is not null && word == "@") return origin;
        if (word == ".") return ".";
        string text = word.EndsWith('.') ? word[..^1] : word;
        string[] labels = text.Split('.');
        for (int i = 0; i < labels.Length; i++) Require(wildcard && i == 0 && labels[i] == "*" || Matches(labels[i], "[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"), "bad name " + word);
        string result = text.ToLowerInvariant() + ".";
        if (origin is not null && !word.EndsWith('.') && origin != ".") result += origin;
        return result;
    }

    static string[] Labels(string name) => name == "." ? [] : name[..^1].Split('.');

    static int Length(string name) => Labels(name).Length;

    static bool Below(string name, string ancestor) => ancestor == "." || name == ancestor || name.EndsWith("." + ancestor, StringComparison.Ordinal);

    static string Parent(string name)
    {
        int dot = name.IndexOf('.');
        return dot == name.Length - 1 ? "." : name[(dot + 1)..];
    }

    static int CompareNames(string left, string right)
    {
        string[] a = Labels(left), b = Labels(right);
        for (int i = 1; i <= Math.Min(a.Length, b.Length); i++)
        {
            int order = StringComparer.Ordinal.Compare(a[^i], b[^i]);
            if (order != 0) return order;
        }
        return a.Length.CompareTo(b.Length);
    }

    static uint Ipv4(string word)
    {
        string[] fields = word.Split('.');
        Require(fields.Length == 4, "bad address " + word);
        uint value = 0;
        foreach (string field in fields)
        {
            Require(Matches(field, "0|[1-9][0-9]{0,2}"), "bad address " + word);
            uint n = uint.Parse(field);
            Require(n <= 255, "bad address " + word);
            value = value * 256 + n;
        }
        return value;
    }

    static string Address(uint value) => $"{value >> 24}.{(value >> 16) & 255}.{(value >> 8) & 255}.{value & 255}";

    static int[] Ipv6(string word)
    {
        int colon = word.IndexOf("::", StringComparison.Ordinal);
        string left = colon < 0 ? word : word[..colon], right = colon < 0 ? "" : word[(colon + 2)..];
        Require(colon < 0 || colon == word.LastIndexOf("::", StringComparison.Ordinal), "bad address " + word);
        string[] a = left.Length == 0 ? [] : left.Split(':'), b = right.Length == 0 ? [] : right.Split(':');
        Require(colon < 0 ? a.Length == 8 : a.Length + b.Length <= 7, "bad address " + word);
        int[] groups = new int[8];
        for (int i = 0; i < a.Length; i++)
        {
            Require(Matches(a[i], "[0-9a-fA-F]{1,4}"), "bad address " + word);
            groups[i] = int.Parse(a[i], NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }
        for (int i = 0; i < b.Length; i++)
        {
            Require(Matches(b[i], "[0-9a-fA-F]{1,4}"), "bad address " + word);
            groups[8 - b.Length + i] = int.Parse(b[i], NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }
        return groups;
    }

    static string Address6(int[] groups)
    {
        int best = -1, count = 1;
        for (int i = 0; i < 8;)
        {
            if (groups[i] != 0)
            {
                i++;
                continue;
            }
            int end = i;
            while (end < 8 && groups[end] == 0) end++;
            if (end - i > count)
            {
                best = i;
                count = end - i;
            }
            i = end;
        }
        string Group(int index) => groups[index].ToString("x", CultureInfo.InvariantCulture);
        if (best < 0) return string.Join(":", Enumerable.Range(0, 8).Select(Group));
        return string.Join(":", Enumerable.Range(0, best).Select(Group)) + "::" + string.Join(":", Enumerable.Range(best + count, 8 - best - count).Select(Group));
    }

    static int? Integer(string word) => Matches(word, "0|[1-9][0-9]{0,8}") ? int.Parse(word) : null;

    static int Ttl(string word)
    {
        int? plain = Integer(word);
        long total = plain ?? 0;
        if (plain is null)
        {
            int position = 0, previous = -1;
            const string units = "wdhms";
            int[] seconds = [604800, 86400, 3600, 60, 1];
            while (position < word.Length)
            {
                int start = position;
                while (position < word.Length && word[position] is >= '0' and <= '9') position++;
                string number = word[start..position];
                Require(number.Length is >= 1 and <= 3 && Integer(number) is not null && position < word.Length, "bad ttl " + word);
                int unit = units.IndexOf(char.ToLowerInvariant(word[position++]));
                Require(unit > previous, "bad ttl " + word);
                previous = unit;
                total += (long)int.Parse(number) * seconds[unit];
            }
        }
        Require(total is >= 1 and <= 604800, "bad ttl " + word);
        return (int)total;
    }

    static int CompareData(ResourceRecord left, ResourceRecord right)
    {
        switch (left.Type)
        {
            case 0:
                return Ipv4(left.Data).CompareTo(Ipv4(right.Data));
            case 7:
                int[] a = Ipv6(left.Data), b = Ipv6(right.Data);
                for (int i = 0; i < 8; i++)
                {
                    int order = a[i].CompareTo(b[i]);
                    if (order != 0) return order;
                }
                return 0;
            case 1:
            case 2:
            case 4:
                return CompareNames(left.Data, right.Data);
            case 5:
                string[] x = left.Data.Split(' '), y = right.Data.Split(' ');
                int comparison = int.Parse(x[0]).CompareTo(int.Parse(y[0]));
                return comparison == 0 ? CompareNames(x[1], y[1]) : comparison;
            case 6:
                return StringComparer.Ordinal.Compare(left.Data, right.Data);
            default:
                return 0;
        }
    }

    static List<ResourceRecord> Sorted(IEnumerable<ResourceRecord> records) => records.OrderBy(record => record, Comparer<ResourceRecord>.Create(CompareData)).ToList();

    static List<ResourceRecord> Records(Zone zone, string owner, int type) => Sorted(zone.Records.Where(record => record.Owner == owner && record.Type == type));

    static void ZoneLine(string[] words, int line)
    {
        if (words[0] == "ROOT")
        {
            List<uint> additions = [];
            foreach (string word in words.Skip(1))
            {
                uint value = Ipv4(word);
                Require(!Roots.Contains(value) && !additions.Contains(value), "duplicate root " + word);
                additions.Add(value);
            }
            Roots.AddRange(additions);
            return;
        }
        if (words[0] == "ZONE")
        {
            current = null;
            string origin = Name(words[1], false, null);
            uint server = Ipv4(words[2]);
            Require(!Zones.Any(zone => zone.Origin == origin && zone.Server == server), $"duplicate zone {origin} at {words[2]}");
            current = new(origin, server, line);
            Zones.Add(current);
            return;
        }
        Require(current is not null, "no current zone");
        Zone selected = current!;
        string owner = Name(words[0], true, selected.Origin);
        Require(Below(owner, selected.Origin), "out of zone " + owner);
        int ttl = Ttl(words[1]), type = TypeIndex(words[2]);
        string[] data = words[3..];
        Require(type == 6 || data.Length == (type == 5 ? 2 : type == 3 ? 7 : 1), "wrong field count");
        string text;
        if (type == 0) text = Address(Ipv4(data[0]));
        else if (type == 7) text = Address6(Ipv6(data[0]));
        else if (type is 1 or 2 or 4) text = Name(data[0], false, selected.Origin);
        else if (type == 5)
        {
            int? preference = Integer(data[0]);
            Require(preference is not null && preference <= 65535, "bad preference " + data[0]);
            text = preference + " " + Name(data[1], false, selected.Origin);
        }
        else if (type == 6)
        {
            text = string.Join(" ", data);
            Require(text.Length >= 2 && text.StartsWith('"') && text.EndsWith('"') && !text[1..^1].Contains('"'), "bad text " + text);
        }
        else
        {
            List<string> fields = [Name(data[0], false, selected.Origin), Name(data[1], false, selected.Origin)];
            for (int i = 2; i < 6; i++)
            {
                Require(Integer(data[i]) is not null, "bad number " + data[i]);
                fields.Add(data[i]);
            }
            int? minimum = Integer(data[6]);
            Require(minimum is >= 1 and <= 86400, "bad minimum " + data[6]);
            fields.Add(data[6]);
            text = string.Join(" ", fields);
        }
        Require(type != 1 || !owner.StartsWith("*.", StringComparison.Ordinal), "ns at wildcard");
        Require(type != 3 || owner == selected.Origin, "soa not at origin");
        Require(type != 3 || selected.Soa is null, "duplicate soa");
        Require(!selected.Records.Any(record => record.Owner == owner && record.Type == type && record.Data == text), "duplicate record");
        Require(!selected.Records.Any(record => record.Owner == owner && (type == 2 || record.Type == 2)), "cname conflict " + owner);
        selected.Records.Add(new(owner, ttl, type, text));
    }

    static void FinishZones()
    {
        List<Zone> valid = [];
        foreach (Zone zone in Zones) if (zone.Soa is null) Console.WriteLine($"error line {zone.Line}: zone {zone.Origin} at {Address(zone.Server)} has no soa");
        else
        {
            Console.WriteLine($"zone {zone.Origin} at {Address(zone.Server)} records={zone.Records.Count}");
            valid.Add(zone);
        }
        Zones.Clear();
        Zones.AddRange(valid);
        Console.WriteLine($"loaded roots={Roots.Count} zones={Zones.Count} records={Zones.Sum(zone => zone.Records.Count)}");
    }

    static bool Exists(Zone zone, string name) => zone.Records.Any(record => Below(record.Owner, name));

    static Response Authoritative(uint server, string name, int type, string cut)
    {
        if (Down.Contains(server) || !Zones.Any(candidate => candidate.Server == server)) return new("TIMEOUT");
        Zone? zone = null;
        foreach (Zone candidate in Zones) if (candidate.Server == server && Below(name, candidate.Origin) && (zone is null || Length(candidate.Origin) > Length(zone.Origin))) zone = candidate;
        if (zone is null || Length(zone.Origin) < Length(cut)) return new("LAME");
        string? delegation = null;
        foreach (ResourceRecord record in zone.Records) if (record.Type == 1 && record.Owner != zone.Origin && Below(name, record.Owner) && (delegation is null || Length(record.Owner) < Length(delegation))) delegation = record.Owner;
        if (delegation is not null)
        {
            Response response = new("REFERRAL") { Cut = delegation, Authority = Records(zone, delegation, 1) };
            foreach (ResourceRecord ns in response.Authority) response.Additional.AddRange(Records(zone, ns.Data, 0));
            return response;
        }
        List<ResourceRecord> chosen = zone.Records.Where(record => record.Owner == name).ToList();
        if (chosen.Count == 0 && !Exists(zone, name))
        {
            string ancestor = Parent(name);
            while (!Exists(zone, ancestor)) ancestor = Parent(ancestor);
            string wildcard = ancestor == "." ? "*." : "*." + ancestor;
            chosen = zone.Records.Where(record => record.Owner == wildcard).ToList();
        }
        Response result;
        if (chosen.Count == 0) result = new(Exists(zone, name) ? "NODATA" : "NXDOMAIN");
        else
        {
            List<ResourceRecord> answer = chosen.Where(record => record.Type == type).Select(record => record with { Owner = name }).ToList();
            if (answer.Count > 0) return new("ANSWER") { Answer = Sorted(answer) };
            if (type != 2)
            {
                ResourceRecord? alias = chosen.Find(record => record.Type == 2);
                if (alias is not null) return new("CNAME")
                {
                    Answer = [alias with { Owner = name }]
                };
            }
            result = new("NODATA");
        }
        result.Authority.Add(zone.Soa!);
        return result;
    }

    static Response Ask(uint server, string name, int type, string cut)
    {
        Response response = Authoritative(server, name, type, cut);
        if (!Queries.TryGetValue(server, out int[]? counts))
        {
            counts = new int[7];
            Queries[server] = counts;
        }
        counts[Array.IndexOf(Kinds, response.Kind)]++;
        return response;
    }

    static void Trace(int depth, string text) => Console.WriteLine(new string(' ', 2 * (depth + 1)) + text);

    static int Store(List<ResourceRecord> records)
    {
        int ttl = Math.Min(maxTtl, Math.Max(minTtl, records.Min(record => record.Ttl)));
        ResourceRecord first = records[0];
        Cache[(first.Owner, first.Type)] = new("POS", Sorted(records), now + ttl);
        return ttl;
    }

    static List<ResourceRecord> CachedRecords(CacheEntry entry) => entry.Records.Select(record => record with { Ttl = entry.Expiry - now }).ToList();

    static Response? QueryServers(string name, int type, string cut, List<string>? servers, int depth, List<(string Name, int Type)> resolving)
    {
        if (servers is null)
        {
            foreach (uint server in Roots)
            {
                Response response = Ask(server, name, type, cut);
                Trace(depth, $"ASK {Address(server)} {name} {Types[type]} -> {response.Description}");
                if (response.Kind is not ("LAME" or "TIMEOUT")) return response;
            }
        }
        else foreach (string host in servers.Distinct(StringComparer.Ordinal).OrderBy(entry => entry, Comparer<string>.Create(CompareNames)))
        {
            SortedSet<uint> addresses = [];
            if (Cache.TryGetValue((host, 0), out CacheEntry? cached) && cached.Kind == "POS") foreach (ResourceRecord record in cached.Records) addresses.Add(Ipv4(record.Data));
            else if (resolving.Contains((host, 0))) Trace(depth, "GLUELESS " + host + " -> LOOP");
            else
            {
                Trace(depth, "GLUELESS " + host);
                Result result = Resolve(host, 0, depth + 1, resolving);
                if (result.Status == "NOERROR") foreach (ResourceRecord record in result.Answer) if (record.Type == 0) addresses.Add(Ipv4(record.Data));
            }
            foreach (uint server in addresses)
            {
                Response response = Ask(server, name, type, cut);
                Trace(depth, $"ASK {Address(server)} {name} {Types[type]} -> {response.Description}");
                if (response.Kind is not ("LAME" or "TIMEOUT")) return response;
            }
        }
        return null;
    }

    static Response Lookup(string name, int type, int depth, List<(string Name, int Type)> resolving)
    {
        Response? cached = null;
        if (Cache.TryGetValue((name, type), out CacheEntry? exact)) cached = new(exact.Kind == "POS" ? "ANSWER" : exact.Kind) { Answer = exact.Kind == "POS" ? CachedRecords(exact) : [] };
        if (cached is null && Cache.Any(entry => entry.Value.Kind == "NXDOMAIN" && Below(name, entry.Key.Name))) cached = new("NXDOMAIN");
        if (cached is null && type != 2 && Cache.TryGetValue((name, 2), out CacheEntry? alias) && alias.Kind == "POS") cached = new("CNAME") { Answer = CachedRecords(alias) };
        if (cached is not null)
        {
            hits++;
            Trace(depth, $"CACHE HIT {name} {Types[type]} -> {cached.Description}");
            return cached;
        }
        string cut = ".";
        List<string>? servers = null;
        foreach (var entry in Cache) if (entry.Key.Type == 1 && entry.Value.Kind == "POS" && Below(name, entry.Key.Name) && (servers is null || Length(entry.Key.Name) > Length(cut)))
        {
            cut = entry.Key.Name;
            servers = entry.Value.Records.Select(record => record.Data).ToList();
        }
        if (servers is not null)
        {
            hits++;
            Trace(depth, $"CACHE HIT {name} {Types[type]} -> REFERRAL {cut}");
        }
        while (true)
        {
            Response? response = QueryServers(name, type, cut, servers, depth, resolving);
            if (response is null) return new("SERVFAIL no server for " + cut);
            if (response.Kind == "REFERRAL")
            {
                Store(response.Authority);
                foreach (var group in response.Additional.GroupBy(record => record.Owner, StringComparer.Ordinal)) Store(group.ToList());
                cut = response.Cut;
                servers = response.Authority.Select(record => record.Data).ToList();
                continue;
            }
            if (response.Kind is "ANSWER" or "CNAME")
            {
                int ttl = Store(response.Answer);
                response.Answer = response.Answer.Select(record => record with { Ttl = ttl }).ToList();
            }
            else
            {
                ResourceRecord soa = response.Authority[0];
                int minimum = int.Parse(soa.Data.Split(' ')[6]);
                Cache[(name, type)] = new(response.Kind, [], now + Math.Min(negTtl, Math.Min(soa.Ttl, minimum)));
            }
            return response;
        }
    }

    static Result Resolve(string name, int type, int depth, List<(string Name, int Type)> resolving)
    {
        resolving.Add((name, type));
        List<ResourceRecord> aliases = [];
        HashSet<string> seen = new(StringComparer.Ordinal) { name };
        string currentName = name, status;
        List<ResourceRecord> answer;
        while (true)
        {
            Response response = Lookup(currentName, type, depth, resolving);
            if (response.Kind == "CNAME")
            {
                ResourceRecord alias = response.Answer[0];
                aliases.Add(alias);
                string target = alias.Data;
                if (seen.Contains(target))
                {
                    status = "SERVFAIL cname loop";
                    answer = [];
                    break;
                }
                if (aliases.Count == 9)
                {
                    status = "SERVFAIL cname chain too long";
                    answer = [];
                    break;
                }
                seen.Add(target);
                currentName = target;
                continue;
            }
            if (response.Kind == "ANSWER")
            {
                status = "NOERROR";
                answer = [.. aliases, .. response.Answer];
            }
            else if (response.Kind is "NODATA" or "NXDOMAIN")
            {
                status = response.Kind;
                answer = aliases;
            }
            else
            {
                status = response.Kind;
                answer = [];
            }
            break;
        }
        resolving.RemoveAt(resolving.Count - 1);
        Resolutions[status == "NOERROR" ? 0 : status == "NODATA" ? 1 : status == "NXDOMAIN" ? 2 : 3]++;
        return new(status, answer);
    }

    static Result Resolve(string name, int type) => Resolve(name, type, 0, []);

    static void Answer(Result result)
    {
        foreach (ResourceRecord record in result.Answer) Console.WriteLine("answer " + record);
        Console.WriteLine("status " + result.Status);
    }

    static void Addresses(string host, string prefix)
    {
        Result a = Resolve(host, 0), aaaa = Resolve(host, 7);
        List<string> addresses = [];
        if (a.Status == "NOERROR") addresses.AddRange(a.Answer.Where(record => record.Type == 0).Select(record => record.Data));
        if (aaaa.Status == "NOERROR") addresses.AddRange(aaaa.Answer.Where(record => record.Type == 7).Select(record => record.Data));
        Console.WriteLine(prefix + host + " -> " + (addresses.Count == 0 ? "no address" : string.Join(" ", addresses)));
    }

    static List<KeyValuePair<(string Name, int Type), CacheEntry>> Selected(string? name) => Cache.Where(entry => name is null || Below(entry.Key.Name, name)).OrderBy(entry => entry.Key.Name, Comparer<string>.Create(CompareNames)).ThenBy(entry => entry.Key.Type).ToList();

    static void Command(string[] words)
    {
        switch (words[0])
        {
            case "RESOLVE":
            {
                string name = Name(words[1], true, null);
                int type = TypeIndex(words[2]);
                Console.WriteLine($"resolve {name} {Types[type]}");
                Answer(Resolve(name, type));
                break;
            }
            case "REVERSE":
            {
                string output, reverse;
                if (words[1].Contains(':'))
                {
                    int[] groups = Ipv6(words[1]);
                    output = Address6(groups);
                    string digits = string.Concat(groups.Select(group => group.ToString("x4", CultureInfo.InvariantCulture)));
                    reverse = string.Join(".", digits.Reverse()) + ".ip6.arpa.";
                }
                else
                {
                    output = Address(Ipv4(words[1]));
                    string[] fields = output.Split('.');
                    reverse = $"{fields[3]}.{fields[2]}.{fields[1]}.{fields[0]}.in-addr.arpa.";
                }
                Console.WriteLine($"reverse {output} {reverse}");
                Answer(Resolve(reverse, 4));
                break;
            }
            case "MX":
            {
                string name = Name(words[1], true, null);
                Console.WriteLine("mx " + name);
                Result result = Resolve(name, 5);
                Answer(result);
                if (result.Status == "NOERROR") foreach (ResourceRecord record in result.Answer.Where(entry => entry.Type == 5))
                {
                    string[] fields = record.Data.Split(' ');
                    if (fields[1] == ".") Console.WriteLine($"exchange {fields[0]} . -> null");
                    else Addresses(fields[1], "exchange " + fields[0] + " ");
                }
                if (result.Status == "NODATA")
                {
                    string host = name;
                    foreach (ResourceRecord record in result.Answer) if (record.Type == 2) host = record.Data;
                    Addresses(host, "implicit ");
                }
                break;
            }
            case "QUERY":
            {
                uint server = Ipv4(words[1]);
                string name = Name(words[2], true, null);
                int type = TypeIndex(words[3]);
                Response response = Ask(server, name, type, ".");
                Console.WriteLine($"query {Address(server)} {name} {Types[type]} -> {response.Description}");
                foreach (ResourceRecord record in response.Answer) Console.WriteLine("answer " + record);
                foreach (ResourceRecord record in response.Authority) Console.WriteLine("authority " + record);
                foreach (ResourceRecord record in response.Additional) Console.WriteLine("additional " + record);
                break;
            }
            case "DUMP":
            {
                uint server = Ipv4(words[1]);
                string name = Name(words[2], false, null);
                if (Down.Contains(server) || !Zones.Any(candidate => candidate.Server == server))
                {
                    Console.WriteLine($"dump {Address(server)} {name} -> TIMEOUT");
                    break;
                }
                Zone? zone = Zones.Find(candidate => candidate.Server == server && candidate.Origin == name);
                if (zone is null) Console.WriteLine($"dump {Address(server)} {name} -> REFUSED");
                else
                {
                    Console.WriteLine($"dump {Address(server)} {name} records={zone.Records.Count}");
                    foreach (ResourceRecord record in zone.Records.OrderBy(entry => entry.Owner, Comparer<string>.Create(CompareNames)).ThenBy(entry => entry.Type).ThenBy(entry => entry, Comparer<ResourceRecord>.Create(CompareData))) Console.WriteLine("  " + record);
                }
                break;
            }
            case "DOWN":
            case "UP":
            {
                uint server = Ipv4(words[1]);
                bool disable = words[0] == "DOWN";
                Require(disable ? !Down.Contains(server) : Down.Contains(server), "server " + words[1] + (disable ? " already down" : " not down"));
                if (disable) Down.Add(server);
                else Down.Remove(server);
                Console.WriteLine((disable ? "down " : "up ") + Address(server));
                break;
            }
            case "SET":
            {
                Require(words[1] is "MINTTL" or "MAXTTL" or "NEGTTL", "bad setting " + words[1]);
                int? value = Integer(words[2]);
                Require(value is >= 1 and <= 604800, "bad value " + words[2]);
                Require((words[1] == "MINTTL" ? value!.Value : minTtl) <= (words[1] == "MAXTTL" ? value!.Value : maxTtl), "minttl above maxttl");
                if (words[1] == "MINTTL") minTtl = value!.Value;
                else if (words[1] == "MAXTTL") maxTtl = value!.Value;
                else negTtl = value!.Value;
                Console.WriteLine($"set {words[1]}={value}");
                break;
            }
            case "TIME":
            {
                int? value = Integer(words[1]);
                Require(value is >= 1 and <= 1000000, "bad time " + words[1]);
                now += value!.Value;
                int before = Cache.Count;
                foreach (var key in Cache.Where(entry => entry.Value.Expiry <= now).Select(entry => entry.Key).ToList()) Cache.Remove(key);
                Console.WriteLine($"time now={now} expired={before - Cache.Count}");
                break;
            }
            case "CACHE":
            case "FLUSH":
            {
                string? name = words.Length == 2 ? Name(words[1], false, null) : null;
                var entries = Selected(name);
                if (words[0] == "FLUSH")
                {
                    foreach (var entry in entries) Cache.Remove(entry.Key);
                    Console.WriteLine($"flush removed={entries.Count}");
                }
                else
                {
                    Console.WriteLine($"cache entries={entries.Count}");
                    foreach (var entry in entries) if (entry.Value.Kind == "POS") foreach (ResourceRecord record in CachedRecords(entry.Value)) Console.WriteLine("  " + record);
                    else Console.WriteLine($"  {entry.Key.Name} {entry.Value.Expiry - now} {Types[entry.Key.Type]} {entry.Value.Kind}");
                }
                break;
            }
            case "STATS": Console.WriteLine($"stats queries={Queries.Values.Sum(counts => counts.Sum())} hits={hits}");
            foreach (var entry in Queries) Console.WriteLine($"  {Address(entry.Key)} sent={entry.Value.Sum()} " + string.Join(" ", Kinds.Select((kind, i) => kind.ToLowerInvariant() + "=" + entry.Value[i])));
            Console.WriteLine($"resolutions noerror={Resolutions[0]} nodata={Resolutions[1]} nxdomain={Resolutions[2]} servfail={Resolutions[3]}");
            break;
        }
    }

    static void Main()
    {
        string line;
        int number = 0;
        while ((line = Console.ReadLine()!) != "END ZONES")
        {
            number++;
            try
            {
                ZoneLine(line.Split(' '), number);
            }
            catch (Problem error)
            {
                Console.WriteLine($"error line {number}: {error.Message}");
            }
        }
        number++;
        FinishZones();
        while ((line = Console.ReadLine()!) != "END")
        {
            number++;
            try
            {
                Command(line.Split(' '));
            }
            catch (Problem error)
            {
                Console.WriteLine($"error line {number}: {error.Message}");
            }
        }
    }
}
