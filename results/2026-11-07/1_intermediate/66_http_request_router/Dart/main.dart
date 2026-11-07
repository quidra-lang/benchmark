import 'dart:convert';
import 'dart:io';

typedef Pair = (String, String);
typedef RulePath = ({String base, bool prefix});
typedef AcceptElement = ({String range, int weight, int specificity});

class InputFailure implements Exception {
  final String message;
  InputFailure(this.message);
}

class Piece {
  final String kind;
  final String value;
  Piece(this.kind, this.value);
}

class Route {
  final String name;
  final Set<String> methods;
  final String pattern;
  final List<Piece> pieces;
  final String role;
  List<String>? types;
  final int order;
  int selected = 0;
  Route(this.name, this.methods, this.pattern, this.pieces, this.role, this.order);
}

class Redirect {
  final String from;
  final String to;
  final bool prefix;
  final int code;
  Redirect(this.from, this.to, this.prefix, this.code);
}

class Client {
  int level;
  int last;
  int allowed = 0;
  int limited = 0;
  Client(this.level, this.last);
}

class RateLimit {
  final int capacity;
  final int seconds;
  RateLimit(this.capacity, this.seconds);
}

class RouterResponse {
  final int code;
  final String body;
  final Map<String, String> headers;
  final bool head;
  RouterResponse(this.code, this.body, this.headers, this.head);
}

final validName = RegExp(r'^[a-z][a-z0-9_]{0,19}$');
final roleName = RegExp(r'^[a-z]{1,16}$');
final mediaType = RegExp(r'^[a-z0-9.+-]+\/[a-z0-9.+-]+$');
final unreserved = RegExp(r'^[A-Za-z0-9._~-]$');
const methods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};
const requestMethods = {...methods, 'HEAD', 'OPTIONS'};
const headerOrder = ['Location', 'Allow', 'Retry-After', 'WWW-Authenticate', 'Access-Control-Allow-Origin', 'Access-Control-Allow-Methods', 'Vary', 'ETag', 'Content-Type', 'Content-Length'];
const reasons = {200: 'OK', 204: 'No Content', 301: 'Moved Permanently', 302: 'Found', 304: 'Not Modified', 307: 'Temporary Redirect', 308: 'Permanent Redirect', 400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed', 406: 'Not Acceptable', 412: 'Precondition Failed', 429: 'Too Many Requests', 501: 'Not Implemented'};
String strip(String text) => text.replaceAll(RegExp(r'^ +| +$'), '');

bool segment(String text) => RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(text) && text != '.' && text != '..';
bool canonicalPath(String text) => text == '/' || text.startsWith('/') && text.substring(1).split('/').every(segment);

RulePath? rulePath(String text) {
  if (canonicalPath(text)) return (base: text, prefix: false);
  if (text.endsWith('/*')) {
    final base = text.substring(0, text.length - 2);
    if (base != '/' && canonicalPath(base)) return (base: base, prefix: true);
  }
  return null;
}

List<Piece>? parsePattern(String pattern) {
  if (pattern == '/') return [];
  if (!pattern.startsWith('/')) return null;
  final texts = pattern.substring(1).split('/');
  final pieces = <Piece>[];
  final names = <String>{};
  for (var index = 0; index < texts.length; index++) {
    final text = texts[index];
    if (segment(text)) {
      pieces.add(Piece('literal', text));
      continue;
    }
    final parameter = RegExp(r'^\{([a-z][a-z0-9_]{0,19})(?::(int|slug))?\}$').firstMatch(text);
    final wildcard = RegExp(r'^\{\*([a-z][a-z0-9_]{0,19})\}$').firstMatch(text);
    if (parameter == null && wildcard == null) return null;
    final name = parameter == null ? wildcard![1]! : parameter[1]!;
    final kind = parameter == null ? 'wildcard' : parameter[2] ?? 'parameter';
    if (names.contains(name) || kind == 'wildcard' && index != texts.length - 1) return null;
    names.add(name);
    pieces.add(Piece(kind, name));
  }
  return pieces;
}

int compareRoutes(Route a, Route b) {
  int count(Route route, Set<String> kinds) => route.pieces.where((piece) => kinds.contains(piece.kind)).length;
  for (final comparison in [count(b, {'literal'}) - count(a, {'literal'}), count(b, {'int', 'slug'}) - count(a, {'int', 'slug'}), count(a, {'wildcard'}) - count(b, {'wildcard'}), a.order - b.order]) {
    if (comparison != 0) return comparison;
  }
  return 0;
}

String encode(String text) => text.split('').map((char) => unreserved.hasMatch(char) ? char : '%${char.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(2, '0')}').join();
String decode(String text) => text.replaceAllMapped(RegExp(r'%([0-9A-Fa-f]{2})'), (match) => String.fromCharCode(int.parse(match[1]!, radix: 16)));

bool validEscapes(String text) {
  for (var index = 0; index < text.length; index++) {
    if (text[index] != '%') continue;
    if (index + 2 >= text.length) return false;
    final digits = text.substring(index + 1, index + 3);
    if (!RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(digits)) return false;
    final code = int.parse(digits, radix: 16);
    if (code < 32 || code > 126) return false;
    index += 2;
  }
  return true;
}

String normalizePath(String path) {
  final decoded = path.replaceAllMapped(RegExp(r'%([0-9A-Fa-f]{2})'), (match) {
    final char = String.fromCharCode(int.parse(match[1]!, radix: 16));
    return unreserved.hasMatch(char) ? char : match[0]!.toUpperCase();
  });
  final pieces = <String>[];
  for (final piece in decoded.substring(1).split('/')) {
    if (piece.isEmpty || piece == '.') continue;
    if (piece == '..') {
      if (pieces.isNotEmpty) pieces.removeLast();
    } else {
      pieces.add(piece);
    }
  }
  return '/${pieces.join('/')}';
}

bool matchRoute(Route route, List<String> segments) {
  final wildcard = route.pieces.any((piece) => piece.kind == 'wildcard');
  final length = route.pieces.length - (wildcard ? 1 : 0);
  if (wildcard ? segments.length < length : segments.length != length) return false;
  for (var index = 0; index < length; index++) {
    final piece = route.pieces[index];
    final value = segments[index];
    if (piece.kind == 'literal' && piece.value != value) return false;
    if (piece.kind == 'int' && !RegExp(r'^[0-9]{1,9}$').hasMatch(value)) return false;
    if (piece.kind == 'slug' && !RegExp(r'^[a-z0-9-]+$').hasMatch(value)) return false;
  }
  return true;
}

List<Pair> parameterPairs(Route route, List<String> segments) {
  final pairs = <Pair>[];
  for (var index = 0; index < route.pieces.length; index++) {
    final piece = route.pieces[index];
    if (piece.kind == 'literal') continue;
    final value = piece.kind == 'wildcard' ? segments.skip(index).map(decode).join('/') : piece.kind == 'int' ? int.parse(segments[index]).toString() : piece.kind == 'slug' ? segments[index] : decode(segments[index]);
    pairs.add((piece.value, value));
  }
  return pairs..sort((a, b) => a.$1.compareTo(b.$1));
}

List<Pair> queryPairs(String? query) {
  if (query == null) return [];
  final pairs = <Pair>[];
  for (final part in query.split('&')) {
    if (part.isEmpty) continue;
    final separator = part.indexOf('=');
    final name = separator < 0 ? part : part.substring(0, separator);
    final value = separator < 0 ? '' : part.substring(separator + 1);
    pairs.add((decode(name.replaceAll('+', ' ')), decode(value.replaceAll('+', ' '))));
  }
  return pairs;
}

List<Pair> cookiePairs(String? cookie) {
  final pairs = <String, String>{};
  if (cookie != null) {
    for (final part in cookie.split(';').map(strip)) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator);
      pairs.putIfAbsent(name, () => part.substring(separator + 1));
    }
  }
  return pairs.entries.map((entry) => (entry.key, entry.value)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
}

String buildBody(Route route, String type, List<Pair> params, List<Pair> query, List<Pair> cookies) {
  String quote(String value) => jsonEncode(value);
  if (type == 'application/json') {
    String object(List<Pair> pairs) => '{${pairs.map((pair) => '${quote(pair.$1)}:${quote(pair.$2)}').join(',')}}';
    return '{"route":${quote(route.name)},"params":${object(params)},"query":[${query.map((pair) => '[${quote(pair.$1)},${quote(pair.$2)}]').join(',')}],"cookies":${object(cookies)}}';
  }
  if (type == 'text/html') {
    const escapes = {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'};
    String html(String value) => value.replaceAllMapped(RegExp('[&<>"]'), (match) => escapes[match[0]]!);
    final result = StringBuffer('<dl><dt>route</dt><dd>${html(route.name)}</dd>');
    for (final group in [('param', params), ('query', query), ('cookie', cookies)]) {
      for (final pair in group.$2) result.write('<dt>${group.$1} ${html(pair.$1)}</dt><dd>${html(pair.$2)}</dd>');
    }
    return '${result.toString()}</dl>';
  }
  String list(List<Pair> pairs) => pairs.isEmpty ? '-' : pairs.map((pair) => '${encode(pair.$1)}=${encode(pair.$2)}').join('&');
  return 'route=${route.name} params=${list(params)} query=${list(query)} cookies=${list(cookies)}';
}

String etag(String body) {
  var a = 1;
  var b = 0;
  for (final code in body.codeUnits) {
    a = (a + code) % 65521;
    b = (b + a) % 65521;
  }
  return '"${b.toRadixString(16).padLeft(4, '0')}${a.toRadixString(16).padLeft(4, '0')}"';
}

String? negotiate(List<String> types, String? accept) {
  if (accept == null) return types[0];
  final elements = <AcceptElement>[];
  for (final element in accept.split(',')) {
    final parts = element.split(';').map(strip).toList();
    final range = parts[0].toLowerCase();
    final int specificity;
    if (range == '*/*') {
      specificity = 1;
    } else if (RegExp(r'^[a-z0-9.+-]+\/\*$').hasMatch(range)) {
      specificity = 2;
    } else if (mediaType.hasMatch(range)) {
      specificity = 3;
    } else {
      continue;
    }
    var weight = 1000;
    var valid = true;
    for (final parameter in parts.skip(1)) {
      final separator = parameter.indexOf('=');
      if (separator < 0 || strip(parameter.substring(0, separator)).toLowerCase() != 'q') continue;
      final q = strip(parameter.substring(separator + 1));
      if (!RegExp(r'^(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)$').hasMatch(q)) {
        valid = false;
      } else {
        final decimal = q.indexOf('.');
        weight = q.startsWith('1') ? 1000 : decimal < 0 ? 0 : int.parse(q.substring(decimal + 1).padRight(3, '0'));
      }
      break;
    }
    if (valid) elements.add((range: range, weight: weight, specificity: specificity));
  }
  String? best;
  var bestWeight = 0;
  for (final type in types) {
    var specificity = 0;
    var weight = 0;
    for (final element in elements) {
      final fits = element.range == '*/*' || element.range == type || element.specificity == 2 && element.range.substring(0, element.range.length - 1) == '${type.split('/')[0]}/';
      if (fits && element.specificity > specificity) {
        specificity = element.specificity;
        weight = element.weight;
      }
    }
    if (weight > bestWeight) {
      best = type;
      bestWeight = weight;
    }
  }
  return best;
}

class HttpRouter {
  final List<Route> routes = [];
  final Map<String, Route> byName = {};
  final Map<String, String> tokens = {};
  final List<Redirect> redirects = [];
  final Set<String> origins = {};
  RateLimit? limit;
  final Map<String, Client> clients = {};
  final Map<int, int> statuses = {};
  int errors = 0;
  int requestCount = 0;
  int urlOk = 0;
  int urlError = 0;
  final List<String> output = [];
  List<Route> table = [];

  void configure(List<String> words) {
    final command = words[0];
    final args = words.sublist(1);
    const arities = {'ROUTE': [3, 5], 'TOKEN': [2], 'REDIRECT': [3], 'ORIGIN': [1], 'LIMIT': [2]};
    if (!arities.containsKey(command) && command != 'TYPES') throw InputFailure('unknown command $command');
    if (command == 'TYPES' ? args.length < 2 : !arities[command]!.contains(args.length)) throw InputFailure('wrong number of arguments');
    if (command == 'ROUTE') {
      final name = args[0];
      final methodText = args[1];
      final pattern = args[2];
      if (!validName.hasMatch(name)) throw InputFailure('bad route name $name');
      if (byName.containsKey(name)) throw InputFailure('duplicate route $name');
      final methodList = methodText.split(',');
      if (methodList.any((method) => !methods.contains(method)) || methodList.toSet().length != methodList.length) throw InputFailure('bad methods $methodText');
      final pieces = parsePattern(pattern);
      if (pieces == null) throw InputFailure('bad pattern $pattern');
      if (args.length == 5 && args[3] != 'ROLE') throw InputFailure('unknown option ${args[3]}');
      if (args.length == 5 && !roleName.hasMatch(args[4])) throw InputFailure('bad role ${args[4]}');
      final route = Route(name, methodList.toSet(), pattern, pieces, args.length == 5 ? args[4] : 'none', routes.length);
      routes.add(route);
      byName[name] = route;
    } else if (command == 'TOKEN') {
      final value = args[0];
      final role = args[1];
      if (!RegExp(r'^[A-Za-z0-9._-]{1,32}$').hasMatch(value)) throw InputFailure('bad token $value');
      if (tokens.containsKey(value)) throw InputFailure('duplicate token $value');
      if (!roleName.hasMatch(role)) throw InputFailure('bad role $role');
      tokens[value] = role;
    } else if (command == 'REDIRECT') {
      final from = rulePath(args[0]);
      if (from == null) throw InputFailure('bad path ${args[0]}');
      final to = rulePath(args[1]);
      if (to == null) throw InputFailure('bad path ${args[1]}');
      if (from.prefix != to.prefix) throw InputFailure('wildcard mismatch');
      if (!['301', '302', '307', '308'].contains(args[2])) throw InputFailure('bad redirect code ${args[2]}');
      if (redirects.any((rule) => rule.from == from.base && rule.prefix == from.prefix)) throw InputFailure('duplicate redirect ${args[0]}');
      redirects.add(Redirect(from.base, to.base, from.prefix, int.parse(args[2])));
    } else if (command == 'ORIGIN') {
      if (!RegExp(r'^https?:\/\/[a-z0-9.:-]+$').hasMatch(args[0])) throw InputFailure('bad origin ${args[0]}');
      if (origins.contains(args[0])) throw InputFailure('duplicate origin ${args[0]}');
      origins.add(args[0]);
    } else if (command == 'LIMIT') {
      final n = int.tryParse(args[0]);
      final seconds = int.tryParse(args[1]);
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(args[0]) || n == null || n > 100 || !RegExp(r'^[1-9][0-9]*$').hasMatch(args[1]) || seconds == null || seconds > 3600) throw InputFailure('bad limit');
      if (limit != null) throw InputFailure('duplicate limit');
      limit = RateLimit(n, seconds);
    } else {
      final route = byName[args[0]];
      if (route == null) throw InputFailure('unknown route ${args[0]}');
      if (route.types != null) throw InputFailure('duplicate types ${args[0]}');
      final types = <String>[];
      for (final type in args.skip(1)) {
        if (!mediaType.hasMatch(type)) throw InputFailure('bad media type $type');
        if (types.contains(type)) throw InputFailure('duplicate media type $type');
        types.add(type);
      }
      route.types = types;
    }
  }

  void finishConfiguration() {
    output.add('CONFIG routes=${routes.length} tokens=${tokens.length} redirects=${redirects.length} origins=${origins.length} limit=${limit == null ? 'none' : '${limit!.capacity}/${limit!.seconds}'} errors=$errors');
    for (final route in routes) route.types ??= ['application/json'];
    table = routes.toList()..sort(compareRoutes);
    for (var index = 0; index < table.length; index++) {
      final route = table[index];
      final methodSet = {...route.methods};
      if (methodSet.contains('GET')) methodSet.add('HEAD');
      final methodList = methodSet.toList()..sort();
      output.add('TABLE ${index + 1} ${route.name} ${methodList.join(',')} ${route.pattern} role=${route.role == 'none' ? '-' : route.role} types=${route.types!.join(',')}');
    }
  }

  RouterResponse request(String line, List<String> headerLines) {
    final headers = <String, String>{};
    var head = false;
    var cors = false;
    RouterResponse finish(int code, [String body = '', List<Pair> extra = const [], String type = 'text/plain']) {
      final responseHeaders = Map<String, String>.fromEntries(extra.map((pair) => MapEntry(pair.$1, pair.$2)));
      final origin = headers['origin'];
      if (cors && origin != null && origins.contains(origin)) {
        responseHeaders['Access-Control-Allow-Origin'] = origin;
        if (code == 204 && headers.containsKey('access-control-request-method')) responseHeaders['Access-Control-Allow-Methods'] = responseHeaders['Allow']!;
      }
      if (code != 204 && code != 304) {
        responseHeaders['Content-Type'] = code == 200 ? type : 'text/plain';
        responseHeaders['Content-Length'] = '${body.length}';
      }
      return RouterResponse(code, body, responseHeaders, head);
    }
    final parts = line.split(' ');
    if (parts.length != 3 || !RegExp(r'^[A-Z]{1,16}$').hasMatch(parts[0]) || !parts[1].startsWith('/') || parts[1].contains('#') || parts[2] != 'HTTP/1.1') return finish(400, 'bad request: request line');
    final method = parts[0];
    final target = parts[1];
    head = method == 'HEAD';
    if (!validEscapes(target)) return finish(400, 'bad request: percent escape');
    for (var index = 0; index < headerLines.length; index++) {
      final header = headerLines[index];
      final separator = header.indexOf(':');
      if (separator < 0 || !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(header.substring(0, separator))) return finish(400, 'bad request: header line ${index + 1}');
      final name = header.substring(0, separator).toLowerCase();
      if (headers.containsKey(name)) return finish(400, 'bad request: duplicate header $name');
      headers[name] = strip(header.substring(separator + 1));
    }
    cors = true;
    if (!requestMethods.contains(method)) return finish(501, 'not implemented: $method');
    if (!headers.containsKey('host') || headers['host'] == '') return finish(400, 'bad request: missing host');
    var effective = method;
    if (headers.containsKey('x-http-method-override')) {
      final override = headers['x-http-method-override']!;
      if (method != 'POST' || !['PUT', 'PATCH', 'DELETE'].contains(override)) return finish(400, 'bad request: method override');
      effective = override;
    }
    final clientName = headers['x-client'];
    if (clientName != null && clientName.isNotEmpty) {
      final time = int.parse(headers['x-time']!);
      final client = clients.putIfAbsent(clientName, () => Client(limit == null ? 0 : limit!.capacity * limit!.seconds, time));
      final rate = limit;
      if (rate != null) {
        final refilled = client.level + (time - client.last) * rate.capacity;
        final capacity = rate.capacity * rate.seconds;
        client.level = refilled < capacity ? refilled : capacity;
        client.last = time;
        if (client.level < rate.seconds) {
          client.limited++;
          final wait = (rate.seconds - client.level + rate.capacity - 1) ~/ rate.capacity;
          return finish(429, 'too many requests: client $clientName', [('Retry-After', '$wait')]);
        }
        client.level -= rate.seconds;
      }
      client.allowed++;
    }
    final question = target.indexOf('?');
    final path = question < 0 ? target : target.substring(0, question);
    final query = question < 0 ? null : target.substring(question + 1);
    final suffix = question < 0 ? '' : target.substring(question);
    final normalized = normalizePath(path);
    if (normalized != path) return finish(308, 'redirect to $normalized$suffix', [('Location', normalized + suffix)]);
    for (final rule in redirects) {
      if (path == rule.from || rule.prefix && path.startsWith('${rule.from}/')) {
        final destination = rule.to + path.substring(rule.from.length) + suffix;
        return finish(rule.code, 'redirect to $destination', [('Location', destination)]);
      }
    }
    final segments = path == '/' ? <String>[] : path.substring(1).split('/');
    final matching = table.where((route) => matchRoute(route, segments)).toList();
    if (matching.isEmpty) return finish(404, 'not found: $path');
    final allowed = <String>{'OPTIONS'};
    for (final route in matching) allowed.addAll(route.methods);
    if (allowed.contains('GET')) allowed.add('HEAD');
    final allowedList = allowed.toList()..sort();
    final allow = allowedList.join(', ');
    if (effective == 'OPTIONS') return finish(204, '', [('Allow', allow)]);
    final lookup = effective == 'HEAD' ? 'GET' : effective;
    Route? selected;
    for (final route in matching) {
      if (route.methods.contains(lookup)) {
        selected = route;
        break;
      }
    }
    if (selected == null) return finish(405, 'method not allowed: $effective', [('Allow', allow)]);
    selected.selected++;
    if (selected.role != 'none') {
      if (!headers.containsKey('authorization')) return finish(401, 'unauthorized: missing token', [('WWW-Authenticate', 'Bearer realm="api"')]);
      final authorization = headers['authorization']!;
      final space = authorization.indexOf(' ');
      final scheme = space < 0 ? authorization : authorization.substring(0, space);
      final token = space < 0 ? '' : authorization.substring(space + 1);
      if (scheme.toLowerCase() != 'bearer' || !tokens.containsKey(token)) return finish(401, 'unauthorized: invalid token', [('WWW-Authenticate', 'Bearer realm="api", error="invalid_token"')]);
      final role = tokens[token]!;
      if (role != selected.role && role != 'admin') return finish(403, 'forbidden: requires role ${selected.role}');
    }
    final types = selected.types!;
    final extra = <Pair>[if (types.length > 1) ('Vary', 'Accept')];
    final type = negotiate(types, headers['accept']);
    if (type == null) return finish(406, 'not acceptable: ${types.join(', ')}', extra);
    final body = buildBody(selected, type, parameterPairs(selected, segments), queryPairs(query), cookiePairs(headers['cookie']));
    final tag = etag(body);
    final condition = headers['if-none-match'];
    if (condition != null && condition.split(',').map(strip).map((value) => value.startsWith('W/') ? value.substring(2) : value).any((value) => value == '*' || value == tag)) {
      if (lookup == 'GET') return finish(304, '', [...extra, ('ETag', tag)]);
      return finish(412, 'precondition failed: $tag', extra);
    }
    return finish(200, body, [...extra, ('ETag', tag)], type);
  }

  String urlFor(List<String> words) {
    final name = words[1];
    final route = byName[name];
    if (route == null) throw InputFailure('unknown route $name');
    final parameterNames = route.pieces.where((piece) => piece.kind != 'literal').map((piece) => piece.value).toSet();
    final parameters = <String, String>{};
    final query = <Pair>[];
    for (final argument in words.skip(2)) {
      final separator = argument.indexOf('=');
      if (separator <= 0) throw InputFailure('bad argument $argument');
      final key = argument.substring(0, separator);
      final value = argument.substring(separator + 1);
      if (parameterNames.contains(key)) {
        if (parameters.containsKey(key)) throw InputFailure('duplicate parameter $key');
        parameters[key] = value;
      } else {
        query.add((key, value));
      }
    }
    final segments = <String>[];
    for (final piece in route.pieces) {
      if (piece.kind == 'literal') {
        segments.add(piece.value);
        continue;
      }
      final value = parameters[piece.value];
      if (piece.kind != 'wildcard' && value == null) throw InputFailure('missing parameter ${piece.value}');
      final text = value ?? '';
      final bool valid;
      if (piece.kind == 'parameter') {
        valid = text.isNotEmpty && text != '.' && text != '..';
      } else if (piece.kind == 'int') {
        valid = RegExp(r'^[0-9]{1,9}$').hasMatch(text);
      } else if (piece.kind == 'slug') {
        valid = RegExp(r'^[a-z0-9-]+$').hasMatch(text);
      } else {
        valid = text.isEmpty || text.split('/').every((part) => part.isNotEmpty && part != '.' && part != '..');
      }
      if (!valid) throw InputFailure('bad value for ${piece.value}');
      if (piece.kind == 'wildcard') {
        if (text.isNotEmpty) segments.addAll(text.split('/').map(encode));
      } else {
        segments.add(encode(text));
      }
    }
    final suffix = query.isEmpty ? '' : '?${query.map((pair) => '${encode(pair.$1)}=${encode(pair.$2)}').join('&')}';
    return 'URLFOR $name /${segments.join('/')}$suffix';
  }

  void emitResponse(RouterResponse response) {
    requestCount++;
    statuses[response.code] = (statuses[response.code] ?? 0) + 1;
    output.add('REQUEST $requestCount');
    output.add('HTTP/1.1 ${response.code} ${reasons[response.code]}');
    for (final name in headerOrder) {
      if (response.headers.containsKey(name)) output.add('$name: ${response.headers[name]}');
    }
    if (!response.head && response.code != 204 && response.code != 304) output.add(response.body);
  }

  void run(List<String> lines) {
    var position = 0;
    while (lines[position] != 'REQUESTS') {
      try {
        configure(lines[position].split(' '));
      } on InputFailure catch (error) {
        errors++;
        output.add('CONFIG ERROR ${position + 1}: ${error.message}');
      }
      position++;
    }
    position++;
    finishConfiguration();
    while (lines[position] != 'END') {
      final line = lines[position++];
      if (line.startsWith('URLFOR ')) {
        try {
          output.add(urlFor(line.split(' ')));
          urlOk++;
        } on InputFailure catch (error) {
          urlError++;
          output.add('URLFOR ERROR ${error.message}');
        }
      } else {
        final headers = <String>[];
        while (lines[position].isNotEmpty) headers.add(lines[position++]);
        position++;
        emitResponse(request(line, headers));
      }
    }
    output.add('SUMMARY requests=$requestCount urlfor_ok=$urlOk urlfor_error=$urlError');
    final codes = statuses.keys.toList()..sort();
    for (final code in codes) output.add('STATUS $code ${statuses[code]}');
    for (final route in routes) output.add('ROUTE ${route.name} ${route.selected}');
    final clientNames = clients.keys.toList()..sort();
    for (final name in clientNames) {
      final client = clients[name]!;
      output.add('CLIENT $name allowed=${client.allowed} limited=${client.limited}');
    }
  }
}

Future<void> main() async {
  final router = HttpRouter();
  router.run((await stdin.transform(utf8.decoder).join()).split('\n'));
  stdout.write('${router.output.join('\n')}\n');
}
