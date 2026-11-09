<?php
class ConfigurationFault extends Exception {}
class UrlFault extends Exception {}

class HttpRouter
{
    private array $routes = [];
    private array $ordered = [];
    private array $tokens = [];
    private array $redirects = [];
    private array $origins = [];
    private ?array $limit = null;
    private int $errors = 0;
    private array $clients = [];
    private array $statuses = [];
    private int $requests = 0;
    private int $urlOk = 0;
    private int $urlError = 0;
    private const NAME = '/\A[a-z][a-z0-9_]{0,19}\z/';
    private const ROLE = '/\A[a-z]{1,16}\z/';
    private const MEDIA = '~\A[a-z0-9.+-]+/[a-z0-9.+-]+\z~';
    private const REASONS = [200 => 'OK', 204 => 'No Content', 301 => 'Moved Permanently', 302 => 'Found', 304 => 'Not Modified',
        307 => 'Temporary Redirect', 308 => 'Permanent Redirect', 400 => 'Bad Request', 401 => 'Unauthorized', 403 => 'Forbidden',
        404 => 'Not Found', 405 => 'Method Not Allowed', 406 => 'Not Acceptable', 412 => 'Precondition Failed', 429 => 'Too Many Requests', 501 => 'Not Implemented'];
    private const HEADERS = ['Location', 'Allow', 'Retry-After', 'WWW-Authenticate', 'Access-Control-Allow-Origin', 'Access-Control-Allow-Methods', 'Vary', 'ETag', 'Content-Type', 'Content-Length'];

    private function fail(string $message): never
    {
        throw new ConfigurationFault($message);
    }

    private function findRoute(string $name): ?object
    {
        foreach ($this->routes as $route) if ($route->name === $name) return $route;
        return null;
    }

    private function segment(string $text): bool
    {
        return preg_match('/\A[A-Za-z0-9._~\-]+\z/', $text) && $text !== '.' && $text !== '..';
    }

    private function canonical(string $text): bool
    {
        if ($text === '/') return true;
        if (!str_starts_with($text, '/')) return false;
        foreach (explode('/', substr($text, 1)) as $part) if (!$this->segment($part)) return false;
        return true;
    }

    private function pattern(string $text): ?array
    {
        if ($text === '/') return [];
        if (!str_starts_with($text, '/')) return null;
        $parts = explode('/', substr($text, 1));
        $pieces = [];
        $names = [];
        foreach ($parts as $index => $part) {
            if ($this->segment($part)) {
                $pieces[] = ['literal', $part];
                continue;
            }
            if (!preg_match('/\A\{(\*?)([a-z][a-z0-9_]{0,19})(?::(int|slug))?\}\z/', $part, $match)) return null;
            $star = $match[1] === '*';
            $name = $match[2];
            $type = $match[3] ?? '';
            if (isset($names[$name]) || ($star && ($type !== '' || $index !== count($parts) - 1))) return null;
            $names[$name] = true;
            $pieces[] = [$star ? 'wildcard' : ($type === '' ? 'parameter' : $type), $name];
        }
        return $pieces;
    }

    private function configure(string $line, int $number): void
    {
        $args = explode(' ', $line);
        $command = array_shift($args);
        try {
            $counts = ['ROUTE' => [3, 5], 'TOKEN' => [2], 'REDIRECT' => [3], 'ORIGIN' => [1], 'LIMIT' => [2]];
            if (!isset($counts[$command]) && $command !== 'TYPES') $this->fail("unknown command $command");
            if ($command === 'TYPES' ? count($args) < 2 : !in_array(count($args), $counts[$command], true)) $this->fail('wrong number of arguments');
            switch ($command) {
                case 'ROUTE':
                    [$name, $methods, $path] = $args;
                    if (!preg_match(self::NAME, $name)) $this->fail("bad route name $name");
                    if ($this->findRoute($name) !== null) $this->fail("duplicate route $name");
                    $methodList = explode(',', $methods);
                    if (array_diff($methodList, ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) !== [] || count(array_unique($methodList)) !== count($methodList)) $this->fail("bad methods $methods");
                    $pieces = $this->pattern($path);
                    if ($pieces === null) $this->fail("bad pattern $path");
                    if (count($args) === 5 && $args[3] !== 'ROLE') $this->fail("unknown option $args[3]");
                    if (count($args) === 5 && !preg_match(self::ROLE, $args[4])) $this->fail("bad role $args[4]");
                    $this->routes[] = (object)['name' => $name, 'methods' => $methodList, 'pattern' => $path, 'pieces' => $pieces,
                        'role' => count($args) === 5 ? $args[4] : 'none', 'types' => null, 'hits' => 0, 'number' => count($this->routes)];
                    break;
                case 'TOKEN':
                    [$token, $role] = $args;
                    if (!preg_match('/\A[A-Za-z0-9._-]{1,32}\z/', $token)) $this->fail("bad token $token");
                    if (isset($this->tokens[$token])) $this->fail("duplicate token $token");
                    if (!preg_match(self::ROLE, $role)) $this->fail("bad role $role");
                    $this->tokens[$token] = $role;
                    break;
                case 'REDIRECT':
                    [$from, $to, $code] = $args;
                    foreach ([$from, $to] as $path) {
                        $star = str_ends_with($path, '/*');
                        $base = $star ? substr($path, 0, -2) : $path;
                        if (!$this->canonical($base) || ($star && $base === '/')) $this->fail("bad path $path");
                    }
                    $star = str_ends_with($from, '/*');
                    if ($star !== str_ends_with($to, '/*')) $this->fail('wildcard mismatch');
                    if (!in_array($code, ['301', '302', '307', '308'], true)) $this->fail("bad redirect code $code");
                    foreach ($this->redirects as $rule) if ($rule['from'] === $from) $this->fail("duplicate redirect $from");
                    $this->redirects[] = ['from' => $from, 'base' => $star ? substr($from, 0, -2) : $from, 'to' => $star ? substr($to, 0, -2) : $to, 'wildcard' => $star, 'code' => (int)$code];
                    break;
                case 'ORIGIN':
                    $origin = $args[0];
                    if (!preg_match('~\Ahttps?://[a-z0-9.:-]+\z~', $origin)) $this->fail("bad origin $origin");
                    if (in_array($origin, $this->origins, true)) $this->fail("duplicate origin $origin");
                    $this->origins[] = $origin;
                    break;
                case 'LIMIT':
                    if (!preg_match('/\A[1-9][0-9]*\z/', $args[0]) || !preg_match('/\A[1-9][0-9]*\z/', $args[1]) || (int)$args[0] > 100 || (int)$args[1] > 3600) $this->fail('bad limit');
                    if ($this->limit !== null) $this->fail('duplicate limit');
                    $this->limit = array_map('intval', $args);
                    break;
                case 'TYPES':
                    $name = array_shift($args);
                    $route = $this->findRoute($name);
                    if ($route === null) $this->fail("unknown route $name");
                    if ($route->types !== null) $this->fail("duplicate types $name");
                    $seen = [];
                    foreach ($args as $type) {
                        if (!preg_match(self::MEDIA, $type)) $this->fail("bad media type $type");
                        if (isset($seen[$type])) $this->fail("duplicate media type $type");
                        $seen[$type] = true;
                    }
                    $route->types = $args;
                    break;
            }
        } catch (ConfigurationFault $error) {
            $this->errors++;
            echo "CONFIG ERROR $number: {$error->getMessage()}\n";
        }
    }

    private function priority(object $route): array
    {
        $literals = 0;
        $typed = 0;
        $wildcard = false;
        foreach ($route->pieces as [$kind, $name]) {
            if ($kind === 'literal') $literals++;
            if (in_array($kind, ['int', 'slug'], true)) $typed++;
            if ($kind === 'wildcard') $wildcard = true;
        }
        return [-$literals, -$typed, $wildcard ? 1 : 0, $route->number];
    }

    private function decode(string $text): string
    {
        return preg_replace_callback('/%([0-9A-Fa-f]{2})/', fn($match) => chr(hexdec($match[1])), $text);
    }

    private function encode(string $text): string
    {
        return preg_replace_callback('/[^A-Za-z0-9._~\-]/', fn($match) => sprintf('%%%02X', ord($match[0])), $text);
    }

    private function normalize(string $path): string
    {
        $path = preg_replace_callback('/%([0-9A-Fa-f]{2})/', function ($match) {
            $char = chr(hexdec($match[1]));
            return preg_match('/[A-Za-z0-9._~\-]/', $char) ? $char : sprintf('%%%02X', ord($char));
        }, $path);
        $parts = [];
        foreach (explode('/', substr($path, 1)) as $part) {
            if ($part === '..') array_pop($parts);
            elseif ($part !== '' && $part !== '.') $parts[] = $part;
        }
        return '/' . implode('/', $parts);
    }

    private function matchRoute(object $route, array $segments): ?array
    {
        $pieces = $route->pieces;
        $wildcard = $pieces !== [] && $pieces[array_key_last($pieces)][0] === 'wildcard';
        $count = count($pieces) - ($wildcard ? 1 : 0);
        if ($wildcard ? count($segments) < $count : count($segments) !== $count) return null;
        $parameters = [];
        foreach ($pieces as $index => [$kind, $name]) {
            $text = $segments[$index] ?? '';
            switch ($kind) {
                case 'literal':
                    if ($text !== $name) return null;
                    break;
                case 'parameter':
                    $parameters[$name] = $this->decode($text);
                    break;
                case 'int':
                    if (!preg_match('/\A[0-9]{1,9}\z/', $text)) return null;
                    $parameters[$name] = (string)(int)$text;
                    break;
                case 'slug':
                    if (!preg_match('/\A[a-z0-9-]+\z/', $text)) return null;
                    $parameters[$name] = $text;
                    break;
                case 'wildcard':
                    $parameters[$name] = implode('/', array_map(fn($part) => $this->decode($part), array_slice($segments, $count)));
                    break;
            }
        }
        return $parameters;
    }

    private function selectedType(array $types, ?string $accept): ?string
    {
        if ($accept === null) return $types[0];
        $elements = [];
        foreach (explode(',', $accept) as $element) {
            $parts = array_map(fn($part) => trim($part, ' '), explode(';', $element));
            $range = strtolower(array_shift($parts));
            if ($range !== '*/*' && !preg_match('~\A[a-z0-9.+-]+/\*\z~', $range) && !preg_match(self::MEDIA, $range)) continue;
            $q = null;
            foreach ($parts as $part) {
                if (!str_contains($part, '=')) continue;
                [$name, $value] = array_map(fn($item) => trim($item, ' '), explode('=', $part, 2));
                if (strtolower($name) === 'q') {
                    $q = $value;
                    break;
                }
            }
            if ($q !== null && !preg_match('/\A(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)\z/', $q)) continue;
            $weight = $q === null ? 1000 : (int)round((float)$q * 1000);
            $specificity = $range === '*/*' ? 1 : (str_ends_with($range, '/*') ? 2 : 3);
            $elements[] = [$range, $specificity, $weight];
        }
        $best = null;
        $bestWeight = 0;
        foreach ($types as $type) {
            $specificity = 0;
            $weight = 0;
            foreach ($elements as [$range, $rank, $candidate]) {
                $fits = $range === '*/*' || $range === $type || ($rank === 2 && explode('/', $range)[0] === explode('/', $type)[0]);
                if ($fits && $rank > $specificity) {
                    $specificity = $rank;
                    $weight = $candidate;
                }
            }
            if ($weight > $bestWeight) {
                $bestWeight = $weight;
                $best = $type;
            }
        }
        return $best;
    }

    private function jsonString(string $text): string
    {
        return '"' . strtr($text, ['\\' => '\\\\', '"' => '\\"']) . '"';
    }

    private function html(string $text): string
    {
        return strtr($text, ['&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;']);
    }

    private function bodyFor(object $route, array $parameters, ?string $query, array $headers, string $type): string
    {
        ksort($parameters, SORT_STRING);
        $params = [];
        foreach ($parameters as $name => $value) $params[] = [$name, $value];
        $queries = [];
        if ($query !== null) {
            foreach (explode('&', $query) as $part) {
                if ($part === '') continue;
                [$name, $value] = array_pad(explode('=', $part, 2), 2, '');
                $queries[] = [$this->decode(str_replace('+', ' ', $name)), $this->decode(str_replace('+', ' ', $value))];
            }
        }
        $cookies = [];
        if (array_key_exists('cookie', $headers)) {
            foreach (explode(';', $headers['cookie']) as $part) {
                $part = trim($part, ' ');
                if (!str_contains($part, '=')) continue;
                [$name, $value] = explode('=', $part, 2);
                if ($name !== '' && !array_key_exists($name, $cookies)) $cookies[$name] = $value;
            }
        }
        ksort($cookies, SORT_STRING);
        $cookiePairs = [];
        foreach ($cookies as $name => $value) $cookiePairs[] = [(string)$name, $value];
        if ($type === 'application/json') {
            $pairs = fn($list) => implode(',', array_map(fn($pair) => $this->jsonString($pair[0]) . ':' . $this->jsonString($pair[1]), $list));
            $queryJson = implode(',', array_map(fn($pair) => '[' . $this->jsonString($pair[0]) . ',' . $this->jsonString($pair[1]) . ']', $queries));
            return '{"route":' . $this->jsonString($route->name) . ',"params":{' . $pairs($params) . '},"query":[' . $queryJson . '],"cookies":{' . $pairs($cookiePairs) . '}}';
        }
        if ($type === 'text/html') {
            $output = '<dl><dt>route</dt><dd>' . $this->html($route->name) . '</dd>';
            foreach ([['param', $params], ['query', $queries], ['cookie', $cookiePairs]] as [$label, $list]) {
                foreach ($list as [$name, $value]) $output .= '<dt>' . $label . ' ' . $this->html($name) . '</dt><dd>' . $this->html($value) . '</dd>';
            }
            return $output . '</dl>';
        }
        $pairs = fn($list) => $list === [] ? '-' : implode('&', array_map(fn($pair) => $this->encode($pair[0]) . '=' . $this->encode($pair[1]), $list));
        return "route=$route->name params=" . $pairs($params) . ' query=' . $pairs($queries) . ' cookies=' . $pairs($cookiePairs);
    }

    private function etag(string $body): string
    {
        $a = 1;
        $b = 0;
        for ($index = 0; $index < strlen($body); $index++) {
            $a = ($a + ord($body[$index])) % 65521;
            $b = ($b + $a) % 65521;
        }
        return sprintf('"%04x%04x"', $b, $a);
    }

    private function response(int $status, string $body = '', array $headers = [], ?string $type = null): array
    {
        return ['status' => $status, 'body' => $body, 'headers' => $headers, 'type' => $type];
    }

    private function handle(string $method, string $target, array $headers): array
    {
        if (!in_array($method, ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'], true)) return $this->response(501, "not implemented: $method");
        if (!isset($headers['host']) || $headers['host'] === '') return $this->response(400, 'bad request: missing host');
        $effective = $method;
        if (array_key_exists('x-http-method-override', $headers)) {
            $override = $headers['x-http-method-override'];
            if ($method !== 'POST' || !in_array($override, ['PUT', 'PATCH', 'DELETE'], true)) return $this->response(400, 'bad request: method override');
            $effective = $override;
        }
        $client = $headers['x-client'] ?? '';
        if ($client !== '') {
            $time = (int)$headers['x-time'];
            if (!isset($this->clients[$client])) $this->clients[$client] = (object)['allowed' => 0, 'limited' => 0, 'level' => $this->limit === null ? 0 : $this->limit[0] * $this->limit[1], 'last' => $time];
            $record = $this->clients[$client];
            if ($this->limit !== null) {
                [$capacity, $period] = $this->limit;
                $record->level = min($capacity * $period, $record->level + ($time - $record->last) * $capacity);
                $record->last = $time;
                if ($record->level < $period) {
                    $record->limited++;
                    $wait = intdiv($period - $record->level + $capacity - 1, $capacity);
                    return $this->response(429, "too many requests: client $client", ['Retry-After' => (string)$wait]);
                }
                $record->level -= $period;
            }
            $record->allowed++;
        }
        $targetParts = explode('?', $target, 2);
        $path = $targetParts[0];
        $query = $targetParts[1] ?? null;
        $suffix = count($targetParts) === 2 ? '?' . $query : '';
        $normalized = $this->normalize($path);
        if ($normalized !== $path) return $this->response(308, "redirect to $normalized$suffix", ['Location' => $normalized . $suffix]);
        foreach ($this->redirects as $rule) {
            if ($path === $rule['base'] || ($rule['wildcard'] && str_starts_with($path, $rule['base'] . '/'))) {
                $destination = $rule['to'] . substr($path, strlen($rule['base'])) . $suffix;
                return $this->response($rule['code'], "redirect to $destination", ['Location' => $destination]);
            }
        }
        $segments = $path === '/' ? [] : explode('/', substr($path, 1));
        $matches = [];
        $allowed = ['OPTIONS'];
        foreach ($this->ordered as $route) {
            $parameters = $this->matchRoute($route, $segments);
            if ($parameters !== null) {
                $matches[] = [$route, $parameters];
                array_push($allowed, ...$route->methods);
            }
        }
        if ($matches === []) return $this->response(404, "not found: $path");
        if (in_array('GET', $allowed, true)) $allowed[] = 'HEAD';
        $allowed = array_unique($allowed);
        sort($allowed, SORT_STRING);
        $allow = implode(', ', $allowed);
        if ($effective === 'OPTIONS') return $this->response(204, '', ['Allow' => $allow]);
        $lookup = $effective === 'HEAD' ? 'GET' : $effective;
        $selected = null;
        foreach ($matches as $candidate) {
            if (in_array($lookup, $candidate[0]->methods, true)) {
                $selected = $candidate;
                break;
            }
        }
        if ($selected === null) return $this->response(405, "method not allowed: $effective", ['Allow' => $allow]);
        [$route, $parameters] = $selected;
        $route->hits++;
        if ($route->role !== 'none') {
            if (!array_key_exists('authorization', $headers)) return $this->response(401, 'unauthorized: missing token', ['WWW-Authenticate' => 'Bearer realm="api"']);
            [$scheme, $token] = array_pad(explode(' ', $headers['authorization'], 2), 2, '');
            if (strtolower($scheme) !== 'bearer' || !array_key_exists($token, $this->tokens)) return $this->response(401, 'unauthorized: invalid token', ['WWW-Authenticate' => 'Bearer realm="api", error="invalid_token"']);
            if ($this->tokens[$token] !== $route->role && $this->tokens[$token] !== 'admin') return $this->response(403, "forbidden: requires role $route->role");
        }
        $extra = count($route->types) >= 2 ? ['Vary' => 'Accept'] : [];
        $type = $this->selectedType($route->types, $headers['accept'] ?? null);
        if ($type === null) return $this->response(406, 'not acceptable: ' . implode(', ', $route->types), $extra);
        $body = $this->bodyFor($route, $parameters, $query, $headers, $type);
        $tag = $this->etag($body);
        if (array_key_exists('if-none-match', $headers)) {
            foreach (explode(',', $headers['if-none-match']) as $part) {
                $part = trim($part, ' ');
                if (str_starts_with($part, 'W/')) $part = substr($part, 2);
                if ($part === '*' || $part === $tag) return $lookup === 'GET'
                    ? $this->response(304, '', [...$extra, 'ETag' => $tag])
                    : $this->response(412, "precondition failed: $tag", $extra);
            }
        }
        return $this->response(200, $body, [...$extra, 'ETag' => $tag], $type);
    }

    private function request(string $line, array $headerLines): void
    {
        $this->requests++;
        $head = false;
        $cors = false;
        $headers = [];
        if (!preg_match('~\A([A-Z]{1,16}) (/[^ #]*) HTTP/1\.1\z~', $line, $match)) {
            $result = $this->response(400, 'bad request: request line');
        } else {
            [, $method, $target] = $match;
            $head = $method === 'HEAD';
            $validEscapes = true;
            for ($position = 0; $position < strlen($target); $position++) {
                if ($target[$position] !== '%') continue;
                $hex = substr($target, $position + 1, 2);
                if (!preg_match('/\A[0-9A-Fa-f]{2}\z/', $hex) || hexdec($hex) < 32 || hexdec($hex) > 126) {
                    $validEscapes = false;
                    break;
                }
                $position += 2;
            }
            if (!$validEscapes) {
                $result = $this->response(400, 'bad request: percent escape');
            } else {
                $result = null;
                foreach ($headerLines as $index => $text) {
                    $parts = explode(':', $text, 2);
                    if (count($parts) !== 2 || !preg_match('/\A[A-Za-z0-9-]+\z/', $parts[0])) {
                        $result = $this->response(400, 'bad request: header line ' . ($index + 1));
                        break;
                    }
                    $name = strtolower($parts[0]);
                    if (array_key_exists($name, $headers)) {
                        $result = $this->response(400, "bad request: duplicate header $name");
                        break;
                    }
                    $headers[$name] = trim($parts[1], ' ');
                }
                if ($result === null) {
                    $cors = true;
                    $result = $this->handle($method, $target, $headers);
                }
            }
        }
        if ($cors && isset($headers['origin']) && in_array($headers['origin'], $this->origins, true)) {
            $result['headers']['Access-Control-Allow-Origin'] = $headers['origin'];
            if ($result['status'] === 204 && array_key_exists('access-control-request-method', $headers)) $result['headers']['Access-Control-Allow-Methods'] = $result['headers']['Allow'];
        }
        $status = $result['status'];
        $this->statuses[$status] = ($this->statuses[$status] ?? 0) + 1;
        if (!in_array($status, [204, 304], true)) {
            $result['headers']['Content-Type'] = $status === 200 ? $result['type'] : 'text/plain';
            $result['headers']['Content-Length'] = (string)strlen($result['body']);
        }
        echo "REQUEST $this->requests\nHTTP/1.1 $status " . self::REASONS[$status] . "\n";
        foreach (self::HEADERS as $name) if (array_key_exists($name, $result['headers'])) echo "$name: {$result['headers'][$name]}\n";
        if (!$head && !in_array($status, [204, 304], true)) echo $result['body'] . "\n";
    }

    private function urlfor(string $line): void
    {
        $words = explode(' ', $line);
        $name = $words[1];
        $arguments = array_slice($words, 2);
        try {
            $route = $this->findRoute($name);
            if ($route === null) throw new UrlFault("unknown route $name");
            $parameterNames = [];
            foreach ($route->pieces as [$kind, $key]) if ($kind !== 'literal') $parameterNames[] = $key;
            $values = [];
            $queries = [];
            foreach ($arguments as $argument) {
                $parts = explode('=', $argument, 2);
                if (count($parts) !== 2 || $parts[0] === '') throw new UrlFault("bad argument $argument");
                [$key, $value] = $parts;
                if (in_array($key, $parameterNames, true)) {
                    if (array_key_exists($key, $values)) throw new UrlFault("duplicate parameter $key");
                    $values[$key] = $value;
                } else {
                    $queries[] = [$key, $value];
                }
            }
            foreach ($route->pieces as [$kind, $key]) {
                if ($kind === 'literal') continue;
                if ($kind !== 'wildcard' && !array_key_exists($key, $values)) throw new UrlFault("missing parameter $key");
                $text = $values[$key] ?? '';
                $valid = match ($kind) {
                    'parameter' => $text !== '' && $text !== '.' && $text !== '..',
                    'int' => (bool)preg_match('/\A[0-9]{1,9}\z/', $text),
                    'slug' => (bool)preg_match('/\A[a-z0-9-]+\z/', $text),
                    default => $text === '' || count(array_filter(explode('/', $text), fn($part) => $part === '' || $part === '.' || $part === '..')) === 0
                };
                if (!$valid) throw new UrlFault("bad value for $key");
            }
            $parts = [];
            foreach ($route->pieces as [$kind, $key]) {
                if ($kind === 'literal') $parts[] = $key;
                elseif ($kind === 'wildcard') {
                    $text = $values[$key] ?? '';
                    if ($text !== '') foreach (explode('/', $text) as $part) $parts[] = $this->encode($part);
                } else $parts[] = $this->encode($values[$key]);
            }
            $url = '/' . implode('/', $parts);
            if ($queries !== []) $url .= '?' . implode('&', array_map(fn($pair) => $this->encode($pair[0]) . '=' . $this->encode($pair[1]), $queries));
            $this->urlOk++;
            echo "URLFOR $name $url\n";
        } catch (UrlFault $error) {
            $this->urlError++;
            echo "URLFOR ERROR {$error->getMessage()}\n";
        }
    }

    public function run(): void
    {
        $input = [];
        while (($line = fgets(STDIN)) !== false) $input[] = rtrim($line, "\r\n");
        $position = 0;
        while ($input[$position] !== 'REQUESTS') {
            $this->configure($input[$position], $position + 1);
            $position++;
        }
        $position++;
        echo 'CONFIG routes=' . count($this->routes) . ' tokens=' . count($this->tokens) . ' redirects=' . count($this->redirects) . ' origins=' . count($this->origins) .
            ' limit=' . ($this->limit === null ? 'none' : implode('/', $this->limit)) . " errors=$this->errors\n";
        foreach ($this->routes as $route) $route->types ??= ['application/json'];
        $this->ordered = $this->routes;
        usort($this->ordered, fn($a, $b) => $this->priority($a) <=> $this->priority($b));
        foreach ($this->ordered as $index => $route) {
            $methods = $route->methods;
            if (in_array('GET', $methods, true)) $methods[] = 'HEAD';
            sort($methods, SORT_STRING);
            echo 'TABLE ' . ($index + 1) . " $route->name " . implode(',', $methods) . " $route->pattern role=" . ($route->role === 'none' ? '-' : $route->role) . ' types=' . implode(',', $route->types) . "\n";
        }
        while ($input[$position] !== 'END') {
            $line = $input[$position++];
            if (str_starts_with($line, 'URLFOR ')) {
                $this->urlfor($line);
            } else {
                $headers = [];
                while ($input[$position] !== '') $headers[] = $input[$position++];
                $position++;
                $this->request($line, $headers);
            }
        }
        echo "SUMMARY requests=$this->requests urlfor_ok=$this->urlOk urlfor_error=$this->urlError\n";
        ksort($this->statuses, SORT_NUMERIC);
        foreach ($this->statuses as $status => $count) echo "STATUS $status $count\n";
        foreach ($this->routes as $route) echo "ROUTE $route->name $route->hits\n";
        ksort($this->clients, SORT_STRING);
        foreach ($this->clients as $client => $record) echo "CLIENT $client allowed=$record->allowed limited=$record->limited\n";
    }
}

(new HttpRouter())->run();
