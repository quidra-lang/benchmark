using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

class Program
{
    const string NamePattern = "[a-z][a-z0-9_]{0,19}", MediaPattern = "[a-z0-9.+-]+/[a-z0-9.+-]+";
    static readonly HashSet<string> RouteMethods = ["GET", "POST", "PUT", "PATCH", "DELETE"];
    static readonly HashSet<string> RequestMethods = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"];
    static readonly string[] HeaderOrder = ["Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length"];
    static readonly Dictionary<int, string> Phrases = new() { [200] = "OK", [204] = "No Content", [301] = "Moved Permanently", [302] = "Found", [304] = "Not Modified", [307] = "Temporary Redirect", [308] = "Permanent Redirect", [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden", [404] = "Not Found", [405] = "Method Not Allowed", [406] = "Not Acceptable", [412] = "Precondition Failed", [429] = "Too Many Requests", [501] = "Not Implemented" };
    record Piece(char Kind, string Text);
    class Route
    {
        public required string Name, Pattern, Role;
        public required HashSet<string> Methods;
        public required List<Piece> Pieces;
        public List<string>? Types;
        public int Literals, Typed, Number, Selections;
        public bool Wildcard;
    }
    record Redirect(string From, string To, bool Prefix, int Code);
    record Pair(string Name, string Value);
    class Client { public int Level, Last, Allowed, Limited; }
    class Response(int status, string body)
    {
        public int Status = status;
        public string Body = body, Type = "text/plain";
        public Dictionary<string, string> Headers = new(StringComparer.Ordinal);
        public Response Header(string name, string value) { Headers[name] = value; return this; }
    }
    class Request(string line, List<string> headerLines)
    {
        public string Line = line;
        public List<string> HeaderLines = headerLines;
        public Dictionary<string, string> Headers = new(StringComparer.Ordinal);
        public bool Head, HeadersValid;
    }
    class Invalid(string message) : Exception(message);
    static readonly List<Route> Routes = [];
    static List<Route> priority = [];
    static readonly Dictionary<string, string> Tokens = new(StringComparer.Ordinal);
    static readonly List<Redirect> Redirects = [];
    static readonly HashSet<string> Origins = new(StringComparer.Ordinal);
    static readonly SortedDictionary<string, Client> Clients = new(StringComparer.Ordinal);
    static readonly SortedDictionary<int, int> Statuses = [];
    static int capacity, period, configErrors, requests, urlOk, urlErrors;
    static bool Matches(string text, string pattern) => Regex.IsMatch(text, @"\A(?:" + pattern + @")\z");
    static bool Unreserved(char c) => c is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9' || "-._~".Contains(c);
    static bool Segment(string text) => text.Length > 0 && text is not ("." or "..") && text.All(Unreserved);
    static bool Canonical(string text) => text == "/" || text.StartsWith('/') && text[1..].Split('/').All(Segment);
    static bool RulePath(string text) => Canonical(text) || text.EndsWith("/*", StringComparison.Ordinal) && text.Length > 3 && Canonical(text[..^2]);
    static string Base(string text) => text.EndsWith("/*", StringComparison.Ordinal) ? text[..^2] : text;
    static Route? Find(string name) => Routes.Find(route => route.Name == name);
    static List<Piece>? ParsePattern(string text)
    {
        if (!text.StartsWith('/')) return null;
        if (text == "/") return [];
        string[] fields = text[1..].Split('/');
        List<Piece> pieces = []; HashSet<string> names = new(StringComparer.Ordinal);
        for (int i = 0; i < fields.Length; i++)
        {
            string field = fields[i];
            if (Segment(field)) { pieces.Add(new('L', field)); continue; }
            Match match = Regex.Match(field, @"\A\{(\*?)(" + NamePattern + @")(?::(int|slug))?\}\z");
            if (!match.Success || match.Groups[1].Length > 0 && match.Groups[3].Success) return null;
            char kind = match.Groups[1].Length > 0 ? 'W' : !match.Groups[3].Success ? 'U' : match.Groups[3].Value == "int" ? 'I' : 'S';
            if (kind == 'W' && i != fields.Length - 1 || !names.Add(match.Groups[2].Value)) return null;
            pieces.Add(new(kind, match.Groups[2].Value));
        }
        return pieces;
    }
    static bool Decimal(string text, int maximum) => Matches(text, "[1-9][0-9]*") && text.Length <= maximum.ToString(CultureInfo.InvariantCulture).Length && int.Parse(text) <= maximum;
    static void Configure(string[] args)
    {
        string command = args[0]; int count = args.Length - 1;
        if (command is not ("ROUTE" or "TOKEN" or "REDIRECT" or "ORIGIN" or "LIMIT" or "TYPES")) throw new Invalid("unknown command " + command);
        bool correct = command switch { "ROUTE" => count is 3 or 5, "TOKEN" or "LIMIT" => count == 2, "REDIRECT" => count == 3, "ORIGIN" => count == 1, _ => count >= 2 };
        if (!correct) throw new Invalid("wrong number of arguments");
        switch (command)
        {
            case "ROUTE":
            {
                if (!Matches(args[1], NamePattern)) throw new Invalid("bad route name " + args[1]);
                if (Find(args[1]) is not null) throw new Invalid("duplicate route " + args[1]);
                HashSet<string> methods = new(StringComparer.Ordinal);
                foreach (string method in args[2].Split(',')) if (!RouteMethods.Contains(method) || !methods.Add(method)) throw new Invalid("bad methods " + args[2]);
                List<Piece> pieces = ParsePattern(args[3]) ?? throw new Invalid("bad pattern " + args[3]);
                if (count == 5 && args[4] != "ROLE") throw new Invalid("unknown option " + args[4]);
                if (count == 5 && !Matches(args[5], "[a-z]{1,16}")) throw new Invalid("bad role " + args[5]);
                Routes.Add(new() { Name = args[1], Methods = methods, Pattern = args[3], Pieces = pieces, Role = count == 5 ? args[5] : "none", Number = Routes.Count, Literals = pieces.Count(piece => piece.Kind == 'L'), Typed = pieces.Count(piece => piece.Kind is 'I' or 'S'), Wildcard = pieces.Any(piece => piece.Kind == 'W') });
                break;
            }
            case "TOKEN":
                if (!Matches(args[1], "[A-Za-z0-9._-]{1,32}")) throw new Invalid("bad token " + args[1]);
                if (Tokens.ContainsKey(args[1])) throw new Invalid("duplicate token " + args[1]);
                if (!Matches(args[2], "[a-z]{1,16}")) throw new Invalid("bad role " + args[2]);
                Tokens[args[1]] = args[2]; break;
            case "REDIRECT":
                if (!RulePath(args[1])) throw new Invalid("bad path " + args[1]);
                if (!RulePath(args[2])) throw new Invalid("bad path " + args[2]);
                if (args[1].EndsWith("/*", StringComparison.Ordinal) != args[2].EndsWith("/*", StringComparison.Ordinal)) throw new Invalid("wildcard mismatch");
                if (args[3] is not ("301" or "302" or "307" or "308")) throw new Invalid("bad redirect code " + args[3]);
                if (Redirects.Any(rule => rule.From + (rule.Prefix ? "/*" : "") == args[1])) throw new Invalid("duplicate redirect " + args[1]);
                Redirects.Add(new(Base(args[1]), Base(args[2]), args[1].EndsWith("/*", StringComparison.Ordinal), int.Parse(args[3]))); break;
            case "ORIGIN":
                if (!Matches(args[1], "https?://[a-z0-9.:-]+")) throw new Invalid("bad origin " + args[1]);
                if (Origins.Contains(args[1])) throw new Invalid("duplicate origin " + args[1]);
                Origins.Add(args[1]); break;
            case "LIMIT":
                if (!Decimal(args[1], 100) || !Decimal(args[2], 3600)) throw new Invalid("bad limit");
                if (capacity != 0) throw new Invalid("duplicate limit");
                capacity = int.Parse(args[1]); period = int.Parse(args[2]); break;
            case "TYPES":
            {
                Route route = Find(args[1]) ?? throw new Invalid("unknown route " + args[1]);
                if (route.Types is not null) throw new Invalid("duplicate types " + args[1]);
                List<string> types = [];
                foreach (string type in args.Skip(2))
                {
                    if (!Matches(type, MediaPattern)) throw new Invalid("bad media type " + type);
                    if (types.Contains(type)) throw new Invalid("duplicate media type " + type);
                    types.Add(type);
                }
                route.Types = types; break;
            }
        }
    }
    static void Table()
    {
        Console.WriteLine($"CONFIG routes={Routes.Count} tokens={Tokens.Count} redirects={Redirects.Count} origins={Origins.Count} limit={(capacity == 0 ? "none" : $"{capacity}/{period}")} errors={configErrors}");
        foreach (Route route in Routes) route.Types ??= ["application/json"];
        priority = Routes.OrderByDescending(route => route.Literals).ThenByDescending(route => route.Typed).ThenBy(route => route.Wildcard).ThenBy(route => route.Number).ToList();
        int rank = 0;
        foreach (Route route in priority)
        {
            SortedSet<string> methods = new(route.Methods, StringComparer.Ordinal); if (methods.Contains("GET")) methods.Add("HEAD");
            Console.WriteLine($"TABLE {++rank} {route.Name} {string.Join(",", methods)} {route.Pattern} role={(route.Role == "none" ? "-" : route.Role)} types={string.Join(",", route.Types!)}");
        }
    }
    static string Decode(string text)
    {
        StringBuilder output = new();
        for (int i = 0; i < text.Length; i++)
            if (text[i] == '%') { output.Append((char)int.Parse(text.AsSpan(i + 1, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture)); i += 2; }
            else output.Append(text[i]);
        return output.ToString();
    }
    static string Encode(string text)
    {
        StringBuilder output = new();
        foreach (char c in text) if (Unreserved(c)) output.Append(c); else output.Append('%').Append(((int)c).ToString("X2", CultureInfo.InvariantCulture));
        return output.ToString();
    }
    static string Normalize(string path)
    {
        StringBuilder text = new();
        for (int i = 0; i < path.Length; i++)
            if (path[i] == '%')
            {
                char value = (char)int.Parse(path.AsSpan(i + 1, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                text.Append(Unreserved(value) ? value.ToString() : "%" + path.Substring(i + 1, 2).ToUpperInvariant()); i += 2;
            }
            else text.Append(path[i]);
        List<string> parts = [];
        foreach (string part in text.ToString()[1..].Split('/'))
            if (part == "..") { if (parts.Count > 0) parts.RemoveAt(parts.Count - 1); }
            else if (part.Length > 0 && part != ".") parts.Add(part);
        return "/" + string.Join("/", parts);
    }
    static bool RouteMatches(Route route, string[] segments)
    {
        int count = route.Pieces.Count - (route.Wildcard ? 1 : 0);
        if (route.Wildcard ? segments.Length < count : segments.Length != count) return false;
        for (int i = 0; i < count; i++)
        {
            Piece piece = route.Pieces[i]; string value = segments[i];
            if (piece.Kind == 'L' && piece.Text != value || piece.Kind == 'I' && !Matches(value, "[0-9]{1,9}") || piece.Kind == 'S' && !Matches(value, "[a-z0-9-]+")) return false;
        }
        return true;
    }
    static string? Negotiate(List<string> types, string? accept)
    {
        if (accept is null) return types[0];
        string? selected = null; int bestWeight = 0;
        foreach (string type in types)
        {
            int specificity = 0, weight = 0;
            foreach (string element in accept.Split(','))
            {
                string[] parts = element.Split(';'); string range = parts[0].Trim(' ').ToLowerInvariant();
                int spec = range == "*/*" ? 1 : Matches(range, @"[a-z0-9.+-]+/\*") ? 2 : Matches(range, MediaPattern) ? 3 : 0;
                if (spec == 0) continue;
                string? q = null;
                foreach (string parameter in parts.Skip(1))
                {
                    int equal = parameter.IndexOf('=');
                    if (equal >= 0 && parameter[..equal].Trim(' ').ToLowerInvariant() == "q") { q = parameter[(equal + 1)..].Trim(' '); break; }
                }
                if (q is not null && !Matches(q, @"(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)")) continue;
                int value = 1000;
                if (q is not null)
                {
                    string digits = q.Contains('.') ? q[(q.IndexOf('.') + 1)..] : "";
                    value = (q[0] - '0') * 1000 + int.Parse((digits + "000")[..3]);
                }
                bool fits = spec == 1 || spec == 2 && type.StartsWith(range[..^1], StringComparison.Ordinal) || spec == 3 && type == range;
                if (fits && spec > specificity) { specificity = spec; weight = value; }
            }
            if (weight > bestWeight) { bestWeight = weight; selected = type; }
        }
        return selected;
    }
    static string Json(string text) => "\"" + text.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    static string Html(string text) => text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
    static string JsonPairs(List<Pair> pairs, bool query) => (query ? "[" : "{") + string.Join(",", pairs.Select(pair => query ? "[" + Json(pair.Name) + "," + Json(pair.Value) + "]" : Json(pair.Name) + ":" + Json(pair.Value))) + (query ? "]" : "}");
    static string EncodedPairs(List<Pair> pairs) => pairs.Count == 0 ? "-" : string.Join("&", pairs.Select(pair => Encode(pair.Name) + "=" + Encode(pair.Value)));
    static string Body(Route route, string[] segments, string? query, Dictionary<string, string> headers, string type)
    {
        List<Pair> parameters = [], queries = [], cookies = [];
        for (int i = 0; i < route.Pieces.Count; i++)
        {
            Piece piece = route.Pieces[i]; if (piece.Kind == 'L') continue;
            string value = piece.Kind switch { 'W' => string.Join("/", segments.Skip(i).Select(Decode)), 'I' => int.Parse(segments[i]).ToString(CultureInfo.InvariantCulture), 'U' => Decode(segments[i]), _ => segments[i] };
            parameters.Add(new(piece.Text, value));
        }
        parameters = parameters.OrderBy(pair => pair.Name, StringComparer.Ordinal).ToList();
        if (query is not null)
            foreach (string part in query.Split('&'))
                if (part.Length > 0)
                {
                    int equal = part.IndexOf('=');
                    queries.Add(new(Decode((equal < 0 ? part : part[..equal]).Replace('+', ' ')), Decode((equal < 0 ? "" : part[(equal + 1)..]).Replace('+', ' '))));
                }
        HashSet<string> seen = new(StringComparer.Ordinal);
        if (headers.TryGetValue("cookie", out string? cookie))
            foreach (string raw in cookie.Split(';'))
            {
                string part = raw.Trim(' '); int equal = part.IndexOf('=');
                if (equal > 0 && seen.Add(part[..equal])) cookies.Add(new(part[..equal], part[(equal + 1)..]));
            }
        cookies = cookies.OrderBy(pair => pair.Name, StringComparer.Ordinal).ToList();
        if (type == "application/json") return "{\"route\":" + Json(route.Name) + ",\"params\":" + JsonPairs(parameters, false) + ",\"query\":" + JsonPairs(queries, true) + ",\"cookies\":" + JsonPairs(cookies, false) + "}";
        if (type == "text/html")
        {
            StringBuilder output = new("<dl><dt>route</dt><dd>" + Html(route.Name) + "</dd>");
            List<Pair>[] groups = [parameters, queries, cookies]; string[] labels = ["param", "query", "cookie"];
            for (int i = 0; i < 3; i++) foreach (Pair pair in groups[i]) output.Append("<dt>").Append(labels[i]).Append(' ').Append(Html(pair.Name)).Append("</dt><dd>").Append(Html(pair.Value)).Append("</dd>");
            return output.Append("</dl>").ToString();
        }
        return $"route={route.Name} params={EncodedPairs(parameters)} query={EncodedPairs(queries)} cookies={EncodedPairs(cookies)}";
    }
    static string Etag(string body)
    {
        int a = 1, b = 0;
        foreach (char c in body) { a = (a + c) % 65521; b = (b + a) % 65521; }
        return "\"" + b.ToString("x4", CultureInfo.InvariantCulture) + a.ToString("x4", CultureInfo.InvariantCulture) + "\"";
    }
    static Response Process(Request request)
    {
        string[] line = request.Line.Split(' ');
        if (line.Length != 3 || !Matches(line[0], "[A-Z]{1,16}") || !line[1].StartsWith('/') || line[1].Contains('#') || line[2] != "HTTP/1.1") return new(400, "bad request: request line");
        string method = line[0], target = line[1]; request.Head = method == "HEAD";
        for (int i = 0; i < target.Length; i++) if (target[i] == '%')
        {
            if (i + 2 >= target.Length || !Matches(target.Substring(i + 1, 2), "[0-9a-fA-F]{2}")) return new(400, "bad request: percent escape");
            int value = int.Parse(target.AsSpan(i + 1, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            if (value is < 32 or > 126) return new(400, "bad request: percent escape"); i += 2;
        }
        var headers = request.Headers;
        int number = 0;
        foreach (string header in request.HeaderLines)
        {
            number++; int colon = header.IndexOf(':');
            if (colon < 0 || !Matches(header[..colon], "[A-Za-z0-9-]+")) return new(400, "bad request: header line " + number);
            string name = header[..colon].ToLowerInvariant();
            if (headers.ContainsKey(name)) return new(400, "bad request: duplicate header " + name);
            headers[name] = header[(colon + 1)..].Trim(' ');
        }
        request.HeadersValid = true;
        if (!RequestMethods.Contains(method)) return new(501, "not implemented: " + method);
        if (headers.GetValueOrDefault("host", "").Length == 0) return new(400, "bad request: missing host");
        string effective = method;
        if (headers.TryGetValue("x-http-method-override", out string? overridden))
        {
            if (method != "POST" || overridden is not ("PUT" or "PATCH" or "DELETE")) return new(400, "bad request: method override");
            effective = overridden;
        }
        string clientName = headers.GetValueOrDefault("x-client", "");
        if (clientName.Length > 0)
        {
            int time = int.Parse(headers["x-time"]);
            if (!Clients.TryGetValue(clientName, out Client? client)) { client = new() { Level = capacity * period, Last = time }; Clients[clientName] = client; }
            if (capacity > 0)
            {
                client.Level = Math.Min(capacity * period, client.Level + (time - client.Last) * capacity); client.Last = time;
                if (client.Level < period) { client.Limited++; return new Response(429, "too many requests: client " + clientName).Header("Retry-After", ((period - client.Level + capacity - 1) / capacity).ToString(CultureInfo.InvariantCulture)); }
                client.Level -= period;
            }
            client.Allowed++;
        }
        int question = target.IndexOf('?');
        string path = question < 0 ? target : target[..question], suffix = question < 0 ? "" : target[question..];
        string? query = question < 0 ? null : target[(question + 1)..];
        string normalized = Normalize(path);
        if (normalized != path) { string location = normalized + suffix; return new Response(308, "redirect to " + location).Header("Location", location); }
        foreach (Redirect rule in Redirects)
            if (path == rule.From || rule.Prefix && path.StartsWith(rule.From + "/", StringComparison.Ordinal))
            { string location = rule.To + path[rule.From.Length..] + suffix; return new Response(rule.Code, "redirect to " + location).Header("Location", location); }
        string[] segments = path == "/" ? [] : path[1..].Split('/');
        List<Route> matching = priority.Where(matchedRoute => RouteMatches(matchedRoute, segments)).ToList();
        if (matching.Count == 0) return new(404, "not found: " + path);
        SortedSet<string> allowed = new(StringComparer.Ordinal) { "OPTIONS" };
        foreach (Route candidate in matching) allowed.UnionWith(candidate.Methods);
        if (allowed.Contains("GET")) allowed.Add("HEAD");
        string allow = string.Join(", ", allowed);
        if (effective == "OPTIONS") return new Response(204, "").Header("Allow", allow);
        string lookup = effective == "HEAD" ? "GET" : effective;
        Route? route = matching.Find(candidate => candidate.Methods.Contains(lookup));
        if (route is null) return new Response(405, "method not allowed: " + effective).Header("Allow", allow);
        route.Selections++;
        if (route.Role != "none")
        {
            if (!headers.TryGetValue("authorization", out string? authorization)) return new Response(401, "unauthorized: missing token").Header("WWW-Authenticate", "Bearer realm=\"api\"");
            int space = authorization.IndexOf(' '); string scheme = space < 0 ? authorization : authorization[..space], token = space < 0 ? "" : authorization[(space + 1)..];
            if (scheme.ToLowerInvariant() != "bearer" || !Tokens.TryGetValue(token, out string? role)) return new Response(401, "unauthorized: invalid token").Header("WWW-Authenticate", "Bearer realm=\"api\", error=\"invalid_token\"");
            if (role != route.Role && role != "admin") return new(403, "forbidden: requires role " + route.Role);
        }
        string? type = Negotiate(route.Types!, headers.GetValueOrDefault("accept"));
        Response response;
        if (type is null) response = new(406, "not acceptable: " + string.Join(", ", route.Types!));
        else
        {
            string body = Body(route, segments, query, headers, type), tag = Etag(body);
            bool matched = false;
            if (headers.TryGetValue("if-none-match", out string? condition))
                foreach (string item in condition.Split(','))
                {
                    string value = item.Trim(' '); if (value.StartsWith("W/", StringComparison.Ordinal)) value = value[2..];
                    if (value == "*" || value == tag) matched = true;
                }
            if (matched && lookup == "GET") response = new Response(304, "").Header("ETag", tag);
            else if (matched) response = new(412, "precondition failed: " + tag);
            else { response = new Response(200, body).Header("ETag", tag); response.Type = type; }
        }
        if (route.Types!.Count >= 2) response.Header("Vary", "Accept");
        return response;
    }
    static void Respond(Request request)
    {
        Response response = Process(request);
        if (request.HeadersValid && request.Headers.TryGetValue("origin", out string? origin) && Origins.Contains(origin))
        {
            response.Header("Access-Control-Allow-Origin", origin);
            if (response.Status == 204 && request.Headers.ContainsKey("access-control-request-method")) response.Header("Access-Control-Allow-Methods", response.Headers["Allow"]);
        }
        if (response.Status is not (204 or 304)) response.Header("Content-Type", response.Status == 200 ? response.Type : "text/plain").Header("Content-Length", response.Body.Length.ToString(CultureInfo.InvariantCulture));
        Statuses[response.Status] = Statuses.GetValueOrDefault(response.Status) + 1;
        Console.WriteLine($"REQUEST {++requests}"); Console.WriteLine($"HTTP/1.1 {response.Status} {Phrases[response.Status]}");
        foreach (string name in HeaderOrder) if (response.Headers.TryGetValue(name, out string? value)) Console.WriteLine(name + ": " + value);
        if (response.Status is not (204 or 304) && !request.Head) Console.WriteLine(response.Body);
    }
    static bool ValidParameter(Piece piece, string value) => piece.Kind switch
    {
        'I' => Matches(value, "[0-9]{1,9}"), 'S' => Matches(value, "[a-z0-9-]+"),
        'W' => value.Length == 0 || value.Split('/').All(part => part.Length > 0 && part is not ("." or "..")),
        _ => value.Length > 0 && value is not ("." or "..")
    };
    static void UrlFor(string[] args)
    {
        try
        {
            Route route = Find(args[1]) ?? throw new Invalid("unknown route " + args[1]);
            HashSet<string> names = route.Pieces.Where(candidatePiece => candidatePiece.Kind != 'L').Select(piece => piece.Text).ToHashSet(StringComparer.Ordinal);
            Dictionary<string, string> parameters = new(StringComparer.Ordinal); List<Pair> query = [];
            foreach (string argument in args.Skip(2))
            {
                int equal = argument.IndexOf('='); if (equal <= 0) throw new Invalid("bad argument " + argument);
                string name = argument[..equal], value = argument[(equal + 1)..];
                if (names.Contains(name)) { if (parameters.ContainsKey(name)) throw new Invalid("duplicate parameter " + name); parameters[name] = value; }
                else query.Add(new(name, value));
            }
            foreach (Piece piece in route.Pieces.Where(candidatePiece => candidatePiece.Kind != 'L'))
            {
                if (piece.Kind != 'W' && !parameters.ContainsKey(piece.Text)) throw new Invalid("missing parameter " + piece.Text);
                if (!ValidParameter(piece, parameters.GetValueOrDefault(piece.Text, ""))) throw new Invalid("bad value for " + piece.Text);
            }
            List<string> pieces = [];
            foreach (Piece piece in route.Pieces)
                if (piece.Kind == 'L') pieces.Add(piece.Text);
                else if (piece.Kind == 'W')
                {
                    string value = parameters.GetValueOrDefault(piece.Text, ""); if (value.Length > 0) pieces.AddRange(value.Split('/').Select(Encode));
                }
                else pieces.Add(Encode(parameters[piece.Text]));
            string url = "/" + string.Join("/", pieces); if (query.Count > 0) url += "?" + EncodedPairs(query);
            urlOk++; Console.WriteLine($"URLFOR {args[1]} {url}");
        }
        catch (Invalid error) { urlErrors++; Console.WriteLine("URLFOR ERROR " + error.Message); }
    }
    static void Main()
    {
        string line; int number = 0;
        while ((line = Console.ReadLine()!) != "REQUESTS")
        {
            number++;
            try { Configure(line.Split(' ')); }
            catch (Invalid error) { configErrors++; Console.WriteLine($"CONFIG ERROR {number}: {error.Message}"); }
        }
        Table();
        while ((line = Console.ReadLine()!) != "END")
            if (line.StartsWith("URLFOR ", StringComparison.Ordinal)) UrlFor(line.Split(' '));
            else
            {
                List<string> headers = []; string header;
                while ((header = Console.ReadLine()!).Length > 0) headers.Add(header);
                Respond(new(line, headers));
            }
        Console.WriteLine($"SUMMARY requests={requests} urlfor_ok={urlOk} urlfor_error={urlErrors}");
        foreach (var pair in Statuses) Console.WriteLine($"STATUS {pair.Key} {pair.Value}");
        foreach (Route route in Routes) Console.WriteLine($"ROUTE {route.Name} {route.Selections}");
        foreach (var pair in Clients) Console.WriteLine($"CLIENT {pair.Key} allowed={pair.Value.Allowed} limited={pair.Value.Limited}");
    }
}
