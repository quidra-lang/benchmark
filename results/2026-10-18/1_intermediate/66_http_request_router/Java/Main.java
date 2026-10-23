import java.io.*;
import java.util.*;
import java.util.regex.*;

public class Main {
    static final String NAME = "[a-z][a-z0-9_]{0,19}", MEDIA = "[a-z0-9.+-]+/[a-z0-9.+-]+";
    static final Set<String> ROUTE_METHODS = Set.of("GET", "POST", "PUT", "PATCH", "DELETE");
    static final Set<String> REQUEST_METHODS = Set.of("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS");
    static final String[] HEADER_ORDER = {"Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length"};
    static final Map<Integer, String> PHRASES = Map.ofEntries(Map.entry(200,"OK"), Map.entry(204,"No Content"), Map.entry(301,"Moved Permanently"), Map.entry(302,"Found"), Map.entry(304,"Not Modified"), Map.entry(307,"Temporary Redirect"), Map.entry(308,"Permanent Redirect"), Map.entry(400,"Bad Request"), Map.entry(401,"Unauthorized"), Map.entry(403,"Forbidden"), Map.entry(404,"Not Found"), Map.entry(405,"Method Not Allowed"), Map.entry(406,"Not Acceptable"), Map.entry(412,"Precondition Failed"), Map.entry(429,"Too Many Requests"), Map.entry(501,"Not Implemented"));
    record Piece(char kind, String text) {}
    static class Route {
        String name, pattern, role;
        Set<String> methods;
        List<Piece> pieces;
        List<String> types;
        int literals, typed, number, selections;
        boolean wildcard;
    }
    record Redirect(String from, String to, boolean prefix, int code) {}
    record Pair(String name, String value) {}
    static class Client {
        int level, last, allowed, limited;
    }

    static class Response {
        int status;
        String body, type = "text/plain";
        Map<String, String> headers = new HashMap<>();
        Response(int status, String body) {
            this.status = status;
            this.body = body;
        }
        Response header(String name, String value) {
            headers.put(name, value);
            return this;
        }
    }

    static class Request {
        String line;
        List<String> headerLines;
        Map<String, String> headers = new HashMap<>();
        boolean head, headersValid;
        Request(String line, List<String> headers) {
            this.line = line;
            this.headerLines = headers;
        }
    }

    static class Invalid extends RuntimeException {
        Invalid(String text) {
            super(text);
        }
    }

    static final List<Route> routes = new ArrayList<>();
    static List<Route> priority;
    static final Map<String, String> tokens = new HashMap<>();
    static final List<Redirect> redirects = new ArrayList<>();
    static final Set<String> origins = new HashSet<>();
    static final TreeMap<String, Client> clients = new TreeMap<>();
    static final TreeMap<Integer, Integer> statuses = new TreeMap<>();
    static int capacity, period, configErrors, requests, urlOk, urlErrors;
    static void invalid(String message) {
        throw new Invalid(message);
    }

    static String strip(String text) {
        return text.replaceAll("^ +| +$", "");
    }

    static String lower(String text) {
        return text.toLowerCase(Locale.ROOT);
    }

    static boolean unreserved(char c) {
        return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || "-._~".indexOf(c) >= 0;
    }

    static boolean segment(String text) {
        return !text.isEmpty() && !text.equals(".") && !text.equals("..") && text.chars().allMatch(c -> unreserved((char)c));
    }

    static boolean canonical(String text) {
        return text.equals("/") || text.startsWith("/") && Arrays.stream(text.substring(1).split("/", -1)).allMatch(Main::segment);
    }

    static boolean rulePath(String text) {
        return canonical(text) || text.endsWith("/*") && text.length() > 3 && canonical(text.substring(0, text.length() - 2));
    }

    static String base(String text) {
        return text.endsWith("/*") ? text.substring(0, text.length() - 2) : text;
    }

    static Route find(String name) {
        for (Route route : routes) if (route.name.equals(name)) return route;
        return null;
    }

    static List<Piece> pattern(String text) {
        if (!text.startsWith("/")) return null;
        if (text.equals("/")) return new ArrayList<>();
        String[] fields = text.substring(1).split("/", -1);
        List<Piece> pieces = new ArrayList<>();
        Set<String> names = new HashSet<>();
        for (int i = 0; i < fields.length; i++) {
            String field = fields[i];
            Piece piece;
            if (segment(field)) piece = new Piece('L', field);
            else {
                Matcher match = Pattern.compile("\\{(\\*?)(" + NAME + ")(?::(int|slug))?\\}").matcher(field);
                if (!match.matches() || !match.group(1).isEmpty() && match.group(3) != null) return null;
                char kind = !match.group(1).isEmpty() ? 'W' : match.group(3) == null ? 'U' : match.group(3).equals("int") ? 'I' : 'S';
                if (kind == 'W' && i != fields.length - 1 || !names.add(match.group(2))) return null;
                piece = new Piece(kind, match.group(2));
            }
            pieces.add(piece);
        }
        return pieces;
    }

    static boolean decimal(String text, int maximum) {
        if (!text.matches("[1-9][0-9]*") || text.length() > Integer.toString(maximum).length()) return false;
        return Integer.parseInt(text) <= maximum;
    }

    static void configure(String[] a) {
        if (!Set.of("ROUTE", "TOKEN", "REDIRECT", "ORIGIN", "LIMIT", "TYPES").contains(a[0])) invalid("unknown command " + a[0]);
        int n = a.length - 1;
        boolean correct = switch (a[0]) {
            case "ROUTE" -> n == 3 || n == 5;
            case "TOKEN", "LIMIT" -> n == 2;
            case "REDIRECT" -> n == 3;
            case "ORIGIN" -> n == 1;
            default -> n >= 2;
        };
        if (!correct) invalid("wrong number of arguments");
        switch (a[0]) {
            case "ROUTE": {
                if (!a[1].matches(NAME)) invalid("bad route name " + a[1]);
                if (find(a[1]) != null) invalid("duplicate route " + a[1]);
                Set<String> methods = new HashSet<>();
                for (String method : a[2].split(",", -1)) if (!ROUTE_METHODS.contains(method) || !methods.add(method)) invalid("bad methods " + a[2]);
                List<Piece> pieces = pattern(a[3]);
                if (pieces == null) invalid("bad pattern " + a[3]);
                if (n == 5 && !a[4].equals("ROLE")) invalid("unknown option " + a[4]);
                if (n == 5 && !a[5].matches("[a-z]{1,16}")) invalid("bad role " + a[5]);
                Route route = new Route();
                route.name = a[1];
                route.methods = methods;
                route.pattern = a[3];
                route.pieces = pieces;
                route.role = n == 5 ? a[5] : "none";
                route.number = routes.size();
                for (Piece p : pieces) {
                    if (p.kind() == 'L') route.literals++;
                    if (p.kind() == 'I' || p.kind() == 'S') route.typed++;
                    if (p.kind() == 'W') route.wildcard = true;
                }
                routes.add(route);
                break;
            }
            case "TOKEN": if (!a[1].matches("[A-Za-z0-9._-]{1,32}")) invalid("bad token " + a[1]);
            if (tokens.containsKey(a[1])) invalid("duplicate token " + a[1]);
            if (!a[2].matches("[a-z]{1,16}")) invalid("bad role " + a[2]);
            tokens.put(a[1], a[2]);
            break;
            case "REDIRECT": if (!rulePath(a[1])) invalid("bad path " + a[1]);
            if (!rulePath(a[2])) invalid("bad path " + a[2]);
            if (a[1].endsWith("/*") != a[2].endsWith("/*")) invalid("wildcard mismatch");
            if (!Set.of("301", "302", "307", "308").contains(a[3])) invalid("bad redirect code " + a[3]);
            for (Redirect redirect : redirects) if ((redirect.from() + (redirect.prefix() ? "/*" : "")).equals(a[1])) invalid("duplicate redirect " + a[1]);
            redirects.add(new Redirect(base(a[1]), base(a[2]), a[1].endsWith("/*"), Integer.parseInt(a[3])));
            break;
            case "ORIGIN": if (!a[1].matches("https?://[a-z0-9.:-]+")) invalid("bad origin " + a[1]);
            if (origins.contains(a[1])) invalid("duplicate origin " + a[1]);
            origins.add(a[1]);
            break;
            case "LIMIT": if (!decimal(a[1], 100) || !decimal(a[2], 3600)) invalid("bad limit");
            if (capacity != 0) invalid("duplicate limit");
            capacity = Integer.parseInt(a[1]);
            period = Integer.parseInt(a[2]);
            break;
            case "TYPES": Route route = find(a[1]);
            if (route == null) invalid("unknown route " + a[1]);
            if (route.types != null) invalid("duplicate types " + a[1]);
            List<String> types = new ArrayList<>();
            for (String type : Arrays.copyOfRange(a, 2, a.length)) {
                if (!type.matches(MEDIA)) invalid("bad media type " + type);
                if (types.contains(type)) invalid("duplicate media type " + type);
                types.add(type);
            }
            route.types = types;
        }
    }

    static void table() {
        System.out.println("CONFIG routes=" + routes.size() + " tokens=" + tokens.size() + " redirects=" + redirects.size() + " origins=" + origins.size() + " limit=" + (capacity == 0 ? "none" : capacity + "/" + period) + " errors=" + configErrors);
        for (Route route : routes) if (route.types == null) route.types = List.of("application/json");
        priority = routes.stream().sorted(Comparator.comparingInt((Route r) -> -r.literals).thenComparingInt(r -> -r.typed).thenComparing(r -> r.wildcard).thenComparingInt(r -> r.number)).toList();
        int rank = 0;
        for (Route route : priority) {
            Set<String> methods = new TreeSet<>(route.methods);
            if (methods.contains("GET")) methods.add("HEAD");
            System.out.println("TABLE " + (++rank) + " " + route.name + " " + String.join(",", methods) + " " + route.pattern + " role=" + (route.role.equals("none") ? "-" : route.role) + " types=" + String.join(",", route.types));
        }
    }

    static String decode(String text) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < text.length(); i++) if (text.charAt(i) == '%') {
            out.append((char)Integer.parseInt(text.substring(i + 1, i + 3), 16));
            i += 2;
        } else out.append(text.charAt(i));
        return out.toString();
    }

    static String encode(String text) {
        StringBuilder out = new StringBuilder();
        for (char c : text.toCharArray()) if (unreserved(c)) out.append(c);
        else out.append(String.format(Locale.ROOT, "%%%02X", (int)c));
        return out.toString();
    }

    static String normalize(String path) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < path.length(); i++) {
            char c = path.charAt(i);
            if (c == '%') {
                char decoded = (char)Integer.parseInt(path.substring(i + 1, i + 3), 16);
                text.append(unreserved(decoded) ? "" + decoded : "%" + path.substring(i + 1, i + 3).toUpperCase(Locale.ROOT));
                i += 2;
            } else text.append(c);
        }
        List<String> parts = new ArrayList<>();
        for (String part : text.substring(1).split("/", -1)) if (part.equals("..")) {
            if (!parts.isEmpty()) parts.removeLast();
        } else if (!part.isEmpty() && !part.equals(".")) parts.add(part);
        return "/" + String.join("/", parts);
    }

    static boolean matches(Route route, String[] segments) {
        int count = route.pieces.size() - (route.wildcard ? 1 : 0);
        if (route.wildcard ? segments.length < count : segments.length != count) return false;
        for (int i = 0; i < count; i++) {
            Piece p = route.pieces.get(i);
            String s = segments[i];
            if (p.kind() == 'L' && !p.text().equals(s) || p.kind() == 'I' && !s.matches("[0-9]{1,9}") || p.kind() == 'S' && !s.matches("[a-z0-9-]+")) return false;
        }
        return true;
    }

    static String negotiate(List<String> types, String accept) {
        if (accept == null) return types.get(0);
        String selected = null;
        int bestWeight = 0;
        for (String type : types) {
            int specificity = 0, weight = 0;
            for (String element : accept.split(",", -1)) {
                String[] parts = element.split(";", -1);
                String range = lower(strip(parts[0]));
                int spec = range.equals("*/*") ? 1 : range.matches("[a-z0-9.+-]+/\\*") ? 2 : range.matches(MEDIA) ? 3 : 0;
                if (spec == 0) continue;
                String q = null;
                for (int i = 1; i < parts.length; i++) {
                    int eq = parts[i].indexOf('=');
                    if (eq >= 0 && lower(strip(parts[i].substring(0, eq))).equals("q")) {
                        q = strip(parts[i].substring(eq + 1));
                        break;
                    }
                }
                if (q != null && !q.matches("(?:0(?:\\.[0-9]{0,3})?|1(?:\\.0{0,3})?)")) continue;
                int w = 1000;
                if (q != null) {
                    String digits = q.contains(".") ? q.substring(q.indexOf('.') + 1) : "";
                    w = (q.charAt(0) - '0') * 1000 + Integer.parseInt((digits + "000").substring(0, 3));
                }
                boolean fits = spec == 1 || spec == 2 && type.startsWith(range.substring(0, range.length() - 1)) || spec == 3 && type.equals(range);
                if (fits && spec > specificity) {
                    specificity = spec;
                    weight = w;
                }
            }
            if (weight > bestWeight) {
                bestWeight = weight;
                selected = type;
            }
        }
        return selected;
    }

    static String json(String text) {
        return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    static String html(String text) {
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }

    static String jsonPairs(List<Pair> pairs, boolean query) {
        List<String> parts = new ArrayList<>();
        for (Pair p : pairs) parts.add(query ? "[" + json(p.name()) + "," + json(p.value()) + "]" : json(p.name()) + ":" + json(p.value()));
        return (query ? "[" : "{") + String.join(",", parts) + (query ? "]" : "}");
    }

    static String encodedPairs(List<Pair> pairs) {
        return pairs.isEmpty() ? "-" : String.join("&", pairs.stream().map(p -> encode(p.name()) + "=" + encode(p.value())).toList());
    }

    static String body(Route route, String[] segments, String query, Map<String, String> headers, String type) {
        List<Pair> params = new ArrayList<>(), queries = new ArrayList<>(), cookies = new ArrayList<>();
        for (int i = 0; i < route.pieces.size(); i++) {
            Piece p = route.pieces.get(i);
            if (p.kind() == 'L') continue;
            String value = p.kind() == 'W' ? String.join("/", Arrays.stream(segments).skip(i).map(Main::decode).toList()) : p.kind() == 'I' ? Integer.toString(Integer.parseInt(segments[i])) : p.kind() == 'U' ? decode(segments[i]) : segments[i];
            params.add(new Pair(p.text(), value));
        }
        params.sort(Comparator.comparing(Pair::name));
        if (query != null) for (String part : query.split("&", -1)) if (!part.isEmpty()) {
            int eq = part.indexOf('=');
            queries.add(new Pair(decode((eq < 0 ? part : part.substring(0, eq)).replace('+', ' ')), decode((eq < 0 ? "" : part.substring(eq + 1)).replace('+', ' '))));
        }
        Set<String> seen = new HashSet<>();
        if (headers.containsKey("cookie")) for (String raw : headers.get("cookie").split(";", -1)) {
            String part = strip(raw);
            int eq = part.indexOf('=');
            if (eq > 0 && seen.add(part.substring(0, eq))) cookies.add(new Pair(part.substring(0, eq), part.substring(eq + 1)));
        }
        cookies.sort(Comparator.comparing(Pair::name));
        if (type.equals("application/json")) return "{\"route\":" + json(route.name) + ",\"params\":" + jsonPairs(params, false) + ",\"query\":" + jsonPairs(queries, true) + ",\"cookies\":" + jsonPairs(cookies, false) + "}";
        if (type.equals("text/html")) {
            StringBuilder out = new StringBuilder("<dl><dt>route</dt><dd>" + html(route.name) + "</dd>");
            List<List<Pair>> groups = List.of(params, queries, cookies);
            String[] labels = {"param", "query", "cookie"};
            for (int i = 0; i < 3; i++) for (Pair p : groups.get(i)) out.append("<dt>").append(labels[i]).append(" ").append(html(p.name())).append("</dt><dd>").append(html(p.value())).append("</dd>");
            return out.append("</dl>").toString();
        }
        return "route=" + route.name + " params=" + encodedPairs(params) + " query=" + encodedPairs(queries) + " cookies=" + encodedPairs(cookies);
    }

    static String etag(String body) {
        int a = 1, b = 0;
        for (char c : body.toCharArray()) {
            a = (a + c) % 65521;
            b = (b + a) % 65521;
        }
        return String.format(Locale.ROOT, "\"%04x%04x\"", b, a);
    }

    static Response process(Request request) {
        String[] line = request.line.split(" ", -1);
        if (line.length != 3 || !line[0].matches("[A-Z]{1,16}") || !line[1].startsWith("/") || line[1].contains("#") || !line[2].equals("HTTP/1.1")) return new Response(400, "bad request: request line");
        String method = line[0], target = line[1];
        request.head = method.equals("HEAD");
        for (int i = 0; i < target.length(); i++) if (target.charAt(i) == '%') {
            if (i + 2 >= target.length() || !target.substring(i + 1, i + 3).matches("[0-9a-fA-F]{2}")) return new Response(400, "bad request: percent escape");
            int value = Integer.parseInt(target.substring(i + 1, i + 3), 16);
            if (value < 32 || value > 126) return new Response(400, "bad request: percent escape");
            i += 2;
        }
        Map<String, String> headers = request.headers;
        int number = 0;
        for (String header : request.headerLines) {
            number++;
            int colon = header.indexOf(':');
            if (colon < 0 || !header.substring(0, colon).matches("[A-Za-z0-9-]+")) return new Response(400, "bad request: header line " + number);
            String name = lower(header.substring(0, colon));
            if (headers.containsKey(name)) return new Response(400, "bad request: duplicate header " + name);
            headers.put(name, strip(header.substring(colon + 1)));
        }
        request.headersValid = true;
        if (!REQUEST_METHODS.contains(method)) return new Response(501, "not implemented: " + method);
        if (headers.getOrDefault("host", "").isEmpty()) return new Response(400, "bad request: missing host");
        String effective = method;
        if (headers.containsKey("x-http-method-override")) {
            effective = headers.get("x-http-method-override");
            if (!method.equals("POST") || !Set.of("PUT", "PATCH", "DELETE").contains(effective)) return new Response(400, "bad request: method override");
        }
        String clientName = headers.getOrDefault("x-client", "");
        if (!clientName.isEmpty()) {
            int time = Integer.parseInt(headers.get("x-time"));
            Client client = clients.get(clientName);
            if (client == null) {
                client = new Client();
                client.level = capacity * period;
                client.last = time;
                clients.put(clientName, client);
            }
            if (capacity != 0) {
                client.level = Math.min(capacity * period, client.level + (time - client.last) * capacity);
                client.last = time;
                if (client.level < period) {
                    client.limited++;
                    return new Response(429, "too many requests: client " + clientName).header("Retry-After", "" + ((period - client.level + capacity - 1) / capacity));
                }
                client.level -= period;
            }
            client.allowed++;
        }
        int question = target.indexOf('?');
        String path = question < 0 ? target : target.substring(0, question), query = question < 0 ? null : target.substring(question + 1), suffix = question < 0 ? "" : target.substring(question);
        String normal = normalize(path);
        if (!normal.equals(path)) {
            String location = normal + suffix;
            return new Response(308, "redirect to " + location).header("Location", location);
        }
        for (Redirect redirect : redirects) if (path.equals(redirect.from()) || redirect.prefix() && path.startsWith(redirect.from() + "/")) {
            String location = redirect.to() + path.substring(redirect.from().length()) + suffix;
            return new Response(redirect.code(), "redirect to " + location).header("Location", location);
        }
        String[] segments = path.equals("/") ? new String[0] : path.substring(1).split("/", -1);
        List<Route> matching = priority.stream().filter(r -> matches(r, segments)).toList();
        if (matching.isEmpty()) return new Response(404, "not found: " + path);
        Set<String> allowed = new TreeSet<>();
        allowed.add("OPTIONS");
        for (Route route : matching) allowed.addAll(route.methods);
        if (allowed.contains("GET")) allowed.add("HEAD");
        String allow = String.join(", ", allowed);
        if (effective.equals("OPTIONS")) return new Response(204, "").header("Allow", allow);
        String lookup = effective.equals("HEAD") ? "GET" : effective;
        Route route = null;
        for (Route candidate : matching) if (candidate.methods.contains(lookup)) {
            route = candidate;
            break;
        }
        if (route == null) return new Response(405, "method not allowed: " + effective).header("Allow", allow);
        route.selections++;
        if (!route.role.equals("none")) {
            if (!headers.containsKey("authorization")) return new Response(401, "unauthorized: missing token").header("WWW-Authenticate", "Bearer realm=\"api\"");
            String auth = headers.get("authorization");
            int space = auth.indexOf(' ');
            String scheme = space < 0 ? auth : auth.substring(0, space), token = space < 0 ? "" : auth.substring(space + 1);
            if (!lower(scheme).equals("bearer") || !tokens.containsKey(token)) return new Response(401, "unauthorized: invalid token").header("WWW-Authenticate", "Bearer realm=\"api\", error=\"invalid_token\"");
            if (!tokens.get(token).equals(route.role) && !tokens.get(token).equals("admin")) return new Response(403, "forbidden: requires role " + route.role);
        }
        String type = negotiate(route.types, headers.get("accept"));
        Response response;
        if (type == null) response = new Response(406, "not acceptable: " + String.join(", ", route.types));
        else {
            String body = body(route, segments, query, headers, type), tag = etag(body);
            boolean match = false;
            if (headers.containsKey("if-none-match")) for (String item : headers.get("if-none-match").split(",", -1)) {
                String value = strip(item);
                if (value.startsWith("W/")) value = value.substring(2);
                if (value.equals("*") || value.equals(tag)) match = true;
            }
            if (match && lookup.equals("GET")) response = new Response(304, "").header("ETag", tag);
            else if (match) response = new Response(412, "precondition failed: " + tag);
            else {
                response = new Response(200, body).header("ETag", tag);
                response.type = type;
            }
        }
        if (route.types.size() >= 2) response.header("Vary", "Accept");
        return response;
    }

    static void respond(Request request) {
        Response response = process(request);
        String origin = request.headers.get("origin");
        if (request.headersValid && origin != null && origins.contains(origin)) {
            response.header("Access-Control-Allow-Origin", origin);
            if (response.status == 204 && request.headers.containsKey("access-control-request-method")) response.header("Access-Control-Allow-Methods", response.headers.get("Allow"));
        }
        if (response.status != 204 && response.status != 304) {
            response.header("Content-Type", response.status == 200 ? response.type : "text/plain");
            response.header("Content-Length", "" + response.body.length());
        }
        statuses.merge(response.status, 1, Integer::sum);
        System.out.println("REQUEST " + (++requests));
        System.out.println("HTTP/1.1 " + response.status + " " + PHRASES.get(response.status));
        for (String name : HEADER_ORDER) if (response.headers.containsKey(name)) System.out.println(name + ": " + response.headers.get(name));
        if (response.status != 204 && response.status != 304 && !request.head) System.out.println(response.body);
    }

    static boolean validParameter(Piece p, String value) {
        return switch (p.kind()) {
            case 'I' -> value.matches("[0-9]{1,9}");
            case 'S' -> value.matches("[a-z0-9-]+");
            case 'W' -> value.isEmpty() || Arrays.stream(value.split("/", -1)).allMatch(s -> !s.isEmpty() && !s.equals(".") && !s.equals(".."));
            default -> !value.isEmpty() && !value.equals(".") && !value.equals("..");
        };
    }

    static void urlfor(String[] a) {
        try {
            Route route = find(a[1]);
            if (route == null) invalid("unknown route " + a[1]);
            Set<String> names = new HashSet<>();
            for (Piece p : route.pieces) if (p.kind() != 'L') names.add(p.text());
            Map<String, String> parameters = new HashMap<>();
            List<Pair> query = new ArrayList<>();
            for (String arg : Arrays.copyOfRange(a, 2, a.length)) {
                int eq = arg.indexOf('=');
                if (eq <= 0) invalid("bad argument " + arg);
                String name = arg.substring(0, eq), value = arg.substring(eq + 1);
                if (names.contains(name)) {
                    if (parameters.containsKey(name)) invalid("duplicate parameter " + name);
                    parameters.put(name, value);
                } else query.add(new Pair(name, value));
            }
            for (Piece p : route.pieces) if (p.kind() != 'L') {
                if (p.kind() != 'W' && !parameters.containsKey(p.text())) invalid("missing parameter " + p.text());
                if (!validParameter(p, parameters.getOrDefault(p.text(), ""))) invalid("bad value for " + p.text());
            }
            List<String> pieces = new ArrayList<>();
            for (Piece p : route.pieces) if (p.kind() == 'L') pieces.add(p.text());
            else if (p.kind() == 'W') {
                String value = parameters.getOrDefault(p.text(), "");
                if (!value.isEmpty()) for (String part : value.split("/", -1)) pieces.add(encode(part));
            } else pieces.add(encode(parameters.get(p.text())));
            String url = "/" + String.join("/", pieces);
            if (!query.isEmpty()) url += "?" + encodedPairs(query);
            urlOk++;
            System.out.println("URLFOR " + a[1] + " " + url);
        } catch (Invalid ex) {
            urlErrors++;
            System.out.println("URLFOR ERROR " + ex.getMessage());
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        String line;
        int number = 0;
        while (!(line = input.readLine()).equals("REQUESTS")) {
            number++;
            try {
                configure(line.split(" ", -1));
            } catch (Invalid ex) {
                configErrors++;
                System.out.println("CONFIG ERROR " + number + ": " + ex.getMessage());
            }
        }
        table();
        while (!(line = input.readLine()).equals("END")) {
            if (line.startsWith("URLFOR ")) urlfor(line.split(" ", -1));
            else {
                List<String> headers = new ArrayList<>();
                String header;
                while (!(header = input.readLine()).isEmpty()) headers.add(header);
                respond(new Request(line, headers));
            }
        }
        System.out.println("SUMMARY requests=" + requests + " urlfor_ok=" + urlOk + " urlfor_error=" + urlErrors);
        statuses.forEach((status, count) -> System.out.println("STATUS " + status + " " + count));
        for (Route route : routes) System.out.println("ROUTE " + route.name + " " + route.selections);
        clients.forEach((name, client) -> System.out.println("CLIENT " + name + " allowed=" + client.allowed + " limited=" + client.limited));
    }
}
