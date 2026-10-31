<?php

require_once __DIR__ . '/protocol.php';
require_once __DIR__ . '/masks.php';
require_once __DIR__ . '/clients.php';
require_once __DIR__ . '/channels.php';
require_once __DIR__ . '/modes.php';

function readInputs(): array
{
    $settings = ['MOTD' => []];
    foreach (file('input/server.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $separator = strpos($line, ' ');
        $key = substr($line, 0, $separator);
        $value = substr($line, $separator + 1);
        if ($key === 'MOTD') $settings['MOTD'][] = $value;
        elseif (in_array($key, ['NAME', 'VERSION', 'CREATED', 'DESCRIPTION'], true)) $settings[$key] = $value;
        else $settings[$key] = (int) $value;
    }
    $traffic = [];
    foreach (file('input/traffic.txt', FILE_IGNORE_NEW_LINES) as $line) {
        $first = strpos($line, ' ');
        $second = strpos($line, ' ', $first + 1);
        $body = substr($line, $second + 1);
        $kind = str_starts_with($body, 'CONNECT ') ? 'connect' : ($body === 'DISCONNECT' ? 'disconnect' : 'messages');
        $traffic[] = (object) ['time' => (int) substr($line, 0, $first),
            'id' => substr($line, $first + 1, $second - $first - 1), 'body' => $body, 'kind' => $kind];
    }
    return [$settings, $traffic];
}

class Simulator
{
    private array $settings;
    private array $traffic;
    private int $endTime;
    private int $time = 0;
    private array $clients = [];
    private array $channels = [];
    private array $sent = [];
    private array $commands = [];
    private array $numerics = [];
    private array $gone = [];
    private array $lines;
    private array $messages = ['dropped' => 0, 'queued' => 0, 'processed' => 0, 'discarded' => 0, 'empty' => 0];
    private array $sentCounts = ['numerics' => 0, 'pings' => 0, 'errors' => 0];
    private array $disconnections = ['quit' => 0, 'closed' => 0, 'flood' => 0, 'timeout' => 0];
    private int $registeredCount = 0;
    private array $connectionPeak = ['count' => 0, 'time' => 0];
    private array $registrationPeak = ['count' => 0, 'time' => 0];

    public function __construct(array $settings, array $traffic)
    {
        $this->settings = $settings;
        $this->traffic = $traffic;
        $this->endTime = $traffic[count($traffic) - 1]->time;
        $this->lines = ['total' => count($traffic), 'connect' => 0, 'disconnect' => 0, 'messages' => 0];
        foreach ($traffic as $record) $this->lines[$record->kind]++;
    }

    public function run()
    {
        $next = 0;
        for ($this->time = 0; $this->time <= $this->endTime; $this->time++) {
            foreach (array_values($this->clients) as $client) {
                $client->refill($this->time, $this->settings);
                while ($client->active && count($client->queue) > 0 && $client->tokens >= 1) {
                    $client->useToken($this->time, $this->settings);
                    $this->process($client, array_shift($client->queue));
                }
            }
            while ($next < count($this->traffic) && $this->traffic[$next]->time === $this->time) {
                $this->arrive($this->traffic[$next++]);
            }
            foreach (array_values($this->clients) as $client) {
                if ($client->pingSent && $this->time - $client->pingTime >= $this->settings['TIMEOUT']) {
                    $this->disconnect($client, 'Ping timeout: ' . ($this->time - $client->lastReceived) . ' seconds', 'timeout');
                } elseif (!$client->pingSent && $this->time - $client->lastReceived >= $this->settings['PINGFREQ']) {
                    $this->send($client, 'PING :' . $this->settings['NAME']);
                    $this->sentCounts['pings']++;
                    $client->pingSent = true;
                    $client->pingTime = $this->time;
                }
            }
        }
    }

    private function arrive(object $record)
    {
        if ($record->kind === 'connect') {
            $client = new Client($record->id, substr($record->body, 8), $this->time, $this->settings['BUCKET']);
            $this->clients[$client->id] = $client;
            if (count($this->clients) > $this->connectionPeak['count']) {
                $this->connectionPeak = ['count' => count($this->clients), 'time' => $this->time];
            }
            return;
        }
        $client = $this->clients[$record->id] ?? null;
        if ($record->kind === 'disconnect') {
            if ($client !== null) $this->disconnect($client, 'Remote host closed the connection', 'closed');
            return;
        }
        if ($client === null) { $this->messages['dropped']++; return; }
        $client->received++;
        $client->lastReceived = $this->time;
        $client->pingSent = false;
        if (count($client->queue) === 0 && $client->tokens >= 1) {
            $client->useToken($this->time, $this->settings);
            $this->process($client, $record->body);
        } elseif (count($client->queue) >= $this->settings['QUEUE']) {
            $this->messages['discarded']++;
            $this->disconnect($client, 'Excess Flood', 'flood');
        } else {
            $client->queue[] = $record->body;
            $this->messages['queued']++;
        }
    }

    private function send(Client $client, string $line)
    {
        $this->sent[] = $this->time . ' ' . $client->id . ' ' . $line;
        $client->sent++;
    }

    private function numeric(Client $client, int $number, array $context = [])
    {
        $target = $context['target'] ?? null;
        $channel = $context['channel'] ?? null;
        $user = $context['user'] ?? null;
        $command = $context['command'] ?? null;
        $character = $context['character'] ?? null;
        $ban = $context['ban'] ?? null;
        $names = $context['names'] ?? null;
        $motd = $context['motd'] ?? null;
        $server = $this->settings;
        switch ($number) {
            case 1: $content = ':Welcome to the Internet Relay Network ' . $client->prefix(); break;
            case 2: $content = ':Your host is ' . $server['NAME'] . ', running version ' . $server['VERSION']; break;
            case 3: $content = ':This server was created ' . $server['CREATED']; break;
            case 4: $content = $server['NAME'] . ' ' . $server['VERSION'] . ' i biklmnotv'; break;
            case 5: $content = 'CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=' . $server['NICKLEN']
                . ' CHANNELLEN=' . $server['CHANNELLEN'] . ' TOPICLEN=' . $server['TOPICLEN']
                . ' CHANLIMIT=#:' . $server['MAXCHANNELS'] . ' CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server'; break;
            case 221: $content = $client->mode(); break;
            case 301: $content = $user->nickname . ' :' . $user->away; break;
            case 305: $content = ':You are no longer marked as being away'; break;
            case 306: $content = ':You have been marked as being away'; break;
            case 311: $content = $user->nickname . ' ' . $user->username . ' ' . $user->host . ' * :' . $user->realName; break;
            case 312: $content = $user->nickname . ' ' . $server['NAME'] . ' :' . $server['DESCRIPTION']; break;
            case 317: $content = $user->nickname . ' ' . ($this->time - $user->lastSpeaking) . ' ' . $user->registrationTime . ' :seconds idle, signon time'; break;
            case 318: $content = $target . ' :End of /WHOIS list.'; break;
            case 319: $content = $user->nickname . ' :' . implode(' ', array_map(fn($ch) => $ch->labelFor($user), $user->channels)); break;
            case 324: $content = $channel->name . ' ' . $channel->modeDisplay($channel->member($client) !== null); break;
            case 329: $content = $channel->name . ' ' . $channel->creationTime; break;
            case 331: $content = $channel->name . ' :No topic is set'; break;
            case 332: $content = $channel->name . ' :' . $channel->topic; break;
            case 333: $content = $channel->name . ' ' . $channel->topicSetter . ' ' . $channel->topicTime; break;
            case 341: $content = $user->nickname . ' ' . $channel->name; break;
            case 353: $content = '= ' . $channel->name . ' :' . $names; break;
            case 366: $content = $target . ' :End of /NAMES list.'; break;
            case 367: $content = $channel->name . ' ' . $ban->mask . ' ' . $ban->setter . ' ' . $ban->time; break;
            case 368: $content = $channel->name . ' :End of channel ban list'; break;
            case 372: $content = ':- ' . $motd; break;
            case 375: $content = ':- ' . $server['NAME'] . ' Message of the day -'; break;
            case 376: $content = ':End of /MOTD command.'; break;
            case 401: $content = $target . ' :No such nick/channel'; break;
            case 403: $content = $target . ' :No such channel'; break;
            case 404: $content = $channel->name . ' :Cannot send to channel'; break;
            case 405: $content = $target . ' :You have joined too many channels'; break;
            case 409: $content = ':No origin specified'; break;
            case 411: $content = ':No recipient given (' . $command . ')'; break;
            case 412: $content = ':No text to send'; break;
            case 421: $content = $command . ' :Unknown command'; break;
            case 431: $content = ':No nickname given'; break;
            case 432: $content = $target . ' :Erroneous nickname'; break;
            case 433: $content = $target . ' :Nickname is already in use'; break;
            case 441: $content = $user->nickname . ' ' . $channel->name . " :They aren't on that channel"; break;
            case 442: $content = $channel->name . " :You're not on that channel"; break;
            case 443: $content = $user->nickname . ' ' . $channel->name . ' :is already on channel'; break;
            case 451: $content = ':You have not registered'; break;
            case 461: $content = $command . ' :Not enough parameters'; break;
            case 462: $content = ':You may not reregister'; break;
            case 467: $content = $channel->name . ' :Channel key already set'; break;
            case 471: $content = $channel->name . ' :Cannot join channel (+l)'; break;
            case 472: $content = $character . ' :is unknown mode char to me for ' . $channel->name; break;
            case 473: $content = $channel->name . ' :Cannot join channel (+i)'; break;
            case 474: $content = $channel->name . ' :Cannot join channel (+b)'; break;
            case 475: $content = $channel->name . ' :Cannot join channel (+k)'; break;
            case 482: $content = $channel->name . " :You're not channel operator"; break;
            case 501: $content = ':Unknown MODE flag'; break;
            case 502: $content = ':Cannot change mode for other users'; break;
        }
        $this->send($client, ':' . $server['NAME'] . ' ' . sprintf('%03d', $number) . ' ' . $client->addressee() . ' ' . $content);
        $this->sentCounts['numerics']++;
        $this->numerics[$number] = ($this->numerics[$number] ?? 0) + 1;
    }

    private function broadcast(Channel $channel, string $line, ?Client $except = null)
    {
        foreach ($channel->members as $member) if ($member->client !== $except) $this->send($member->client, $line);
    }

    private function sendPeers(Client $client, string $line)
    {
        foreach ($this->clients as $peer) {
            if ($peer === $client) continue;
            foreach ($client->channels as $channel) {
                if ($channel->member($peer) !== null) { $this->send($peer, $line); break; }
            }
        }
    }

    private function removeMember(Channel $channel, Client $client)
    {
        if (!$channel->remove($client)) return;
        unset($this->channels[fold($channel->name)]);
        foreach ($this->clients as $other) {
            $other->invites = array_values(array_filter($other->invites, fn($invite) => $invite !== $channel));
        }
    }

    private function disconnect(Client $client, string $reason, string $kind)
    {
        if ($kind !== 'closed') {
            $this->send($client, 'ERROR :Closing Link: ' . $client->addressee() . '[' . $client->host . '] (' . $reason . ')');
            $this->sentCounts['errors']++;
        }
        if ($client->registered) $this->sendPeers($client, ':' . $client->prefix() . ' QUIT :' . $reason);
        foreach (array_values($client->channels) as $channel) $this->removeMember($channel, $client);
        $this->messages['discarded'] += count($client->queue);
        $client->queue = [];
        unset($this->clients[$client->id]);
        $client->active = false;
        if ($client->registered) $this->registeredCount--;
        $this->gone[] = (object) ['time' => $this->time, 'id' => $client->id, 'addressee' => $client->addressee(), 'reason' => $reason];
        $this->disconnections[$kind]++;
    }

    private function register(Client $client)
    {
        if ($client->registered || $client->nickname === null || $client->username === null) return;
        $client->registered = true;
        $client->registrationTime = $client->lastSpeaking = $this->time;
        $this->registeredCount++;
        if ($this->registeredCount > $this->registrationPeak['count']) {
            $this->registrationPeak = ['count' => $this->registeredCount, 'time' => $this->time];
        }
        foreach ([1, 2, 3, 4, 5, 375] as $number) $this->numeric($client, $number);
        foreach ($this->settings['MOTD'] as $motd) $this->numeric($client, 372, ['motd' => $motd]);
        $this->numeric($client, 376);
        if ($client->invisible) $this->send($client, ':' . $client->nickname . ' MODE ' . $client->nickname . ' :+i');
    }

    private function findUser(string $name): ?Client
    {
        $folded = fold($name);
        foreach ($this->clients as $client) {
            if ($client->registered && fold($client->nickname) === $folded) return $client;
        }
        return null;
    }

    private function findChannel(string $name): ?Channel
    {
        return $this->channels[fold($name)] ?? null;
    }

    private function namesReply(Client $client, Channel $channel)
    {
        $names = $channel->nameList($client);
        if ($names !== '') $this->numeric($client, 353, ['channel' => $channel, 'names' => $names]);
        $this->numeric($client, 366, ['target' => $channel->name]);
    }

    private function topicReply(Client $client, Channel $channel)
    {
        $this->numeric($client, 332, ['channel' => $channel]);
        $this->numeric($client, 333, ['channel' => $channel]);
    }

    private function process(Client $client, string $raw)
    {
        $this->messages['processed']++;
        $parsed = parseMessage($raw);
        if ($parsed === null) { $this->messages['empty']++; return; }
        [$command, $parameters] = $parsed;
        $this->commands[$command] = ($this->commands[$command] ?? 0) + 1;
        if (!$client->registered && !in_array($command, ['NICK', 'USER', 'PING', 'PONG', 'QUIT'], true)) {
            return $this->numeric($client, 451);
        }
        switch ($command) {
            case 'NICK': return $this->nick($client, $parameters);
            case 'USER': return $this->user($client, $parameters);
            case 'PING':
                if (count($parameters) === 0 || $parameters[0] === '') return $this->numeric($client, 409);
                return $this->send($client, ':' . $this->settings['NAME'] . ' PONG ' . $this->settings['NAME'] . ' :' . $parameters[0]);
            case 'PONG': return;
            case 'QUIT':
                $reason = isset($parameters[0]) && $parameters[0] !== '' ? 'Quit: ' . $parameters[0] : 'Client Quit';
                return $this->disconnect($client, $reason, 'quit');
            case 'JOIN': return $this->join($client, $parameters);
            case 'PART': return $this->part($client, $parameters);
            case 'PRIVMSG':
            case 'NOTICE': return $this->message($client, $command, $parameters);
            case 'TOPIC': return $this->topic($client, $parameters);
            case 'NAMES':
                if (count($parameters) === 0) return $this->numeric($client, 366, ['target' => '*']);
                foreach (explode(',', $parameters[0]) as $target) {
                    $channel = $this->findChannel($target);
                    if ($channel !== null) $this->namesReply($client, $channel);
                    else $this->numeric($client, 366, ['target' => $target]);
                }
                return;
            case 'WHOIS': return $this->whois($client, $parameters);
            case 'AWAY':
                $client->away = $parameters[0] ?? '';
                return $this->numeric($client, $client->away !== '' ? 306 : 305);
            case 'INVITE': return $this->invite($client, $parameters);
            case 'KICK': return $this->kick($client, $parameters);
            case 'MODE':
                if (count($parameters) === 0) return $this->numeric($client, 461, ['command' => $command]);
                return str_starts_with($parameters[0], '#')
                    ? $this->channelMode($client, $parameters) : $this->userMode($client, $parameters);
            default: return $this->numeric($client, 421, ['command' => $command]);
        }
    }

    private function nick(Client $client, array $parameters)
    {
        if (count($parameters) === 0 || $parameters[0] === '') return $this->numeric($client, 431);
        $target = substr($parameters[0], 0, $this->settings['NICKLEN']);
        if (!validNickname($target)) return $this->numeric($client, 432, ['target' => $target]);
        if ($target === $client->nickname) return;
        foreach ($this->clients as $other) {
            if ($other !== $client && $other->nickname !== null && fold($other->nickname) === fold($target)) {
                return $this->numeric($client, 433, ['target' => $target]);
            }
        }
        if ($client->registered) {
            $line = ':' . $client->prefix() . ' NICK :' . $target;
            $this->send($client, $line);
            $this->sendPeers($client, $line);
        }
        $client->nickname = $target;
        if (!$client->registered) $this->register($client);
    }

    private function user(Client $client, array $parameters)
    {
        if ($client->username !== null) return $this->numeric($client, 462);
        if (count($parameters) < 4) return $this->numeric($client, 461, ['command' => 'USER']);
        $client->username = $parameters[0];
        $client->realName = $parameters[3];
        $client->invisible = strlen($parameters[1]) <= 3 && digits($parameters[1]) && intdiv((int) $parameters[1], 8) % 2 === 1;
        $this->register($client);
    }

    private function join(Client $client, array $parameters)
    {
        if (count($parameters) === 0) return $this->numeric($client, 461, ['command' => 'JOIN']);
        if ($parameters[0] === '0') {
            foreach (array_values($client->channels) as $channel) {
                $this->broadcast($channel, ':' . $client->prefix() . ' PART ' . $channel->name);
                $this->removeMember($channel, $client);
            }
            return;
        }
        $names = explode(',', $parameters[0]);
        $keys = isset($parameters[1]) ? explode(',', $parameters[1]) : [];
        foreach ($names as $index => $target) {
            if (!validChannel($target, $this->settings['CHANNELLEN'])) {
                $this->numeric($client, 403, ['target' => $target]);
                continue;
            }
            $channel = $this->findChannel($target);
            if ($channel !== null && $channel->member($client) !== null) continue;
            if (count($client->channels) >= $this->settings['MAXCHANNELS']) {
                $this->numeric($client, 405, ['target' => $target]);
                continue;
            }
            if ($channel === null) {
                $channel = new Channel($target, $this->time);
                $this->channels[fold($target)] = $channel;
            } else {
                $invited = in_array($channel, $client->invites, true);
                $error = 0;
                if ($channel->banned($client) && !$invited) $error = 474;
                elseif (isset($channel->flags['i']) && !$invited) $error = 473;
                elseif ($channel->key !== '' && ($keys[$index] ?? '') !== $channel->key) $error = 475;
                elseif ($channel->limit !== 0 && count($channel->members) >= $channel->limit) $error = 471;
                if ($error !== 0) {
                    $this->numeric($client, $error, ['channel' => $channel]);
                    continue;
                }
            }
            $client->invites = array_values(array_filter($client->invites, fn($invite) => $invite !== $channel));
            $channel->add($client);
            $this->broadcast($channel, ':' . $client->prefix() . ' JOIN ' . $channel->name);
            if ($channel->topic !== '') $this->topicReply($client, $channel);
            $this->namesReply($client, $channel);
        }
    }

    private function part(Client $client, array $parameters)
    {
        if (count($parameters) === 0) return $this->numeric($client, 461, ['command' => 'PART']);
        $suffix = isset($parameters[1]) && $parameters[1] !== '' ? ' :' . $parameters[1] : '';
        foreach (explode(',', $parameters[0]) as $target) {
            $channel = $this->findChannel($target);
            if ($channel === null) $this->numeric($client, 403, ['target' => $target]);
            elseif ($channel->member($client) === null) $this->numeric($client, 442, ['channel' => $channel]);
            else {
                $this->broadcast($channel, ':' . $client->prefix() . ' PART ' . $channel->name . $suffix);
                $this->removeMember($channel, $client);
            }
        }
    }

    private function message(Client $client, string $command, array $parameters)
    {
        $reply = function (int $number, array $context = []) use ($client, $command) {
            if ($command === 'PRIVMSG') $this->numeric($client, $number, $context);
        };
        if ($command === 'PRIVMSG') $client->lastSpeaking = $this->time;
        if (count($parameters) === 0 || $parameters[0] === '') return $reply(411, ['command' => $command]);
        if (count($parameters) < 2 || $parameters[1] === '') return $reply(412);
        foreach (explode(',', $parameters[0]) as $target) {
            if (str_starts_with($target, '#')) {
                $channel = $this->findChannel($target);
                if ($channel === null) $reply(401, ['target' => $target]);
                elseif (!$channel->canSpeak($client)) $reply(404, ['channel' => $channel]);
                else {
                    $channel->messages++;
                    $this->broadcast($channel, ':' . $client->prefix() . ' ' . $command . ' ' . $channel->name . ' :' . $parameters[1], $client);
                }
            } else {
                $user = $this->findUser($target);
                if ($user === null) $reply(401, ['target' => $target]);
                else {
                    $this->send($user, ':' . $client->prefix() . ' ' . $command . ' ' . $user->nickname . ' :' . $parameters[1]);
                    if ($user->away !== '') $reply(301, ['user' => $user]);
                }
            }
        }
    }

    private function topic(Client $client, array $parameters)
    {
        if (count($parameters) === 0) return $this->numeric($client, 461, ['command' => 'TOPIC']);
        $channel = $this->findChannel($parameters[0]);
        if ($channel === null) return $this->numeric($client, 403, ['target' => $parameters[0]]);
        $member = $channel->member($client);
        if ($member === null) return $this->numeric($client, 442, ['channel' => $channel]);
        if (count($parameters) === 1) {
            if ($channel->topic !== '') $this->topicReply($client, $channel);
            else $this->numeric($client, 331, ['channel' => $channel]);
            return;
        }
        if (isset($channel->flags['t']) && !$member->operator) return $this->numeric($client, 482, ['channel' => $channel]);
        $channel->topic = substr($parameters[1], 0, $this->settings['TOPICLEN']);
        $channel->topicSetter = $client->nickname;
        $channel->topicTime = $this->time;
        $this->broadcast($channel, ':' . $client->prefix() . ' TOPIC ' . $channel->name . ' :' . $channel->topic);
    }

    private function whois(Client $client, array $parameters)
    {
        if (count($parameters) === 0) return $this->numeric($client, 431);
        $user = $this->findUser($parameters[0]);
        if ($user === null) {
            $this->numeric($client, 401, ['target' => $parameters[0]]);
            $this->numeric($client, 318, ['target' => $parameters[0]]);
            return;
        }
        $this->numeric($client, 311, ['user' => $user]);
        if (count($user->channels) > 0) $this->numeric($client, 319, ['user' => $user]);
        $this->numeric($client, 312, ['user' => $user]);
        if ($user->away !== '') $this->numeric($client, 301, ['user' => $user]);
        $this->numeric($client, 317, ['user' => $user]);
        $this->numeric($client, 318, ['target' => $user->nickname]);
    }

    private function invite(Client $client, array $parameters)
    {
        if (count($parameters) < 2) return $this->numeric($client, 461, ['command' => 'INVITE']);
        $user = $this->findUser($parameters[0]);
        if ($user === null) return $this->numeric($client, 401, ['target' => $parameters[0]]);
        $channel = $this->findChannel($parameters[1]);
        if ($channel === null) return $this->numeric($client, 403, ['target' => $parameters[1]]);
        $member = $channel->member($client);
        if ($member === null) return $this->numeric($client, 442, ['channel' => $channel]);
        if ($channel->member($user) !== null) return $this->numeric($client, 443, ['channel' => $channel, 'user' => $user]);
        if (isset($channel->flags['i']) && !$member->operator) return $this->numeric($client, 482, ['channel' => $channel]);
        if (!in_array($channel, $user->invites, true)) $user->invites[] = $channel;
        $this->numeric($client, 341, ['channel' => $channel, 'user' => $user]);
        if ($user->away !== '') $this->numeric($client, 301, ['user' => $user]);
        $this->send($user, ':' . $client->prefix() . ' INVITE ' . $user->nickname . ' :' . $channel->name);
    }

    private function kick(Client $client, array $parameters)
    {
        if (count($parameters) < 2) return $this->numeric($client, 461, ['command' => 'KICK']);
        $channel = $this->findChannel($parameters[0]);
        if ($channel === null) return $this->numeric($client, 403, ['target' => $parameters[0]]);
        $member = $channel->member($client);
        if ($member === null) return $this->numeric($client, 442, ['channel' => $channel]);
        if (!$member->operator) return $this->numeric($client, 482, ['channel' => $channel]);
        $user = $this->findUser($parameters[1]);
        if ($user === null) return $this->numeric($client, 401, ['target' => $parameters[1]]);
        if ($channel->member($user) === null) return $this->numeric($client, 441, ['channel' => $channel, 'user' => $user]);
        $reason = isset($parameters[2]) && $parameters[2] !== '' ? $parameters[2] : $client->nickname;
        $this->broadcast($channel, ':' . $client->prefix() . ' KICK ' . $channel->name . ' ' . $user->nickname . ' :' . $reason);
        $this->removeMember($channel, $user);
    }

    private function userMode(Client $client, array $parameters)
    {
        $user = $this->findUser($parameters[0]);
        if ($user === null) return $this->numeric($client, 401, ['target' => $parameters[0]]);
        if ($user !== $client) return $this->numeric($client, 502);
        if (count($parameters) === 1) return $this->numeric($client, 221);
        $sign = '+';
        $unknown = false;
        $changes = [];
        foreach (str_split($parameters[1]) as $character) {
            if ($character === '+' || $character === '-') $sign = $character;
            elseif ($character !== 'i') $unknown = true;
            elseif ($client->invisible !== ($sign === '+')) {
                $client->invisible = $sign === '+';
                $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => null];
            }
        }
        if (count($changes) > 0) {
            $this->send($client, ':' . $client->nickname . ' MODE ' . $client->nickname . ' :' . changeString($changes));
        }
        if ($unknown) $this->numeric($client, 501);
    }

    private function channelMode(Client $client, array $parameters)
    {
        $channel = $this->findChannel($parameters[0]);
        if ($channel === null) return $this->numeric($client, 403, ['target' => $parameters[0]]);
        if (count($parameters) === 1) {
            $this->numeric($client, 324, ['channel' => $channel]);
            $this->numeric($client, 329, ['channel' => $channel]);
            return;
        }
        $items = modeItems($parameters[1], array_slice($parameters, 2));
        $operator = $channel->member($client)?->operator === true;
        $listedBans = $denied = false;
        $changes = [];
        foreach ($items as $item) {
            $sign = $item->sign;
            $character = $item->character;
            $argument = $item->argument;
            if (!str_contains('biklmnotv', $character)) {
                $this->numeric($client, 472, ['channel' => $channel, 'character' => $character]);
            } elseif ($character === 'b' && $argument === null) {
                if ($sign === '+' && !$listedBans) {
                    foreach ($channel->bans as $ban) $this->numeric($client, 367, ['channel' => $channel, 'ban' => $ban]);
                    $this->numeric($client, 368, ['channel' => $channel]);
                    $listedBans = true;
                }
            } elseif ($argument === null && (str_contains('ov', $character) || ($sign === '+' && str_contains('kl', $character)))) {
                continue;
            } elseif (!$operator) {
                if (!$denied) $this->numeric($client, 482, ['channel' => $channel]);
                $denied = true;
            } elseif ($character === 'o' || $character === 'v') {
                $user = $this->findUser($argument);
                if ($user === null) $this->numeric($client, 401, ['target' => $argument]);
                else {
                    $member = $channel->member($user);
                    if ($member === null) $this->numeric($client, 441, ['channel' => $channel, 'user' => $user]);
                    else {
                        $field = $character === 'o' ? 'operator' : 'voice';
                        if ($member->$field !== ($sign === '+')) {
                            $member->$field = $sign === '+';
                            $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => $user->nickname];
                        }
                    }
                }
            } elseif ($character === 'b') {
                $mask = normalizeMask($argument);
                $index = -1;
                foreach ($channel->bans as $i => $ban) {
                    if (fold($ban->mask) === fold($mask)) { $index = $i; break; }
                }
                if ($sign === '+' && $index < 0) {
                    $channel->bans[] = (object) ['mask' => $mask, 'setter' => $client->nickname, 'time' => $this->time];
                    $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => $mask];
                } elseif ($sign === '-' && $index >= 0) {
                    $removed = array_splice($channel->bans, $index, 1)[0];
                    $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => $removed->mask];
                }
            } elseif ($character === 'k') {
                if ($sign === '+') {
                    if ($channel->key !== '') $this->numeric($client, 467, ['channel' => $channel]);
                    else {
                        $channel->key = $argument;
                        $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => $argument];
                    }
                } elseif ($channel->key !== '') {
                    $channel->key = '';
                    $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => '*'];
                }
            } elseif ($character === 'l') {
                $limit = $sign === '+' ? (int) $argument : 0;
                if ($channel->limit !== $limit) {
                    $channel->limit = $limit;
                    $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => $sign === '+' ? (string) $limit : null];
                }
            } elseif (isset($channel->flags[$character]) !== ($sign === '+')) {
                if ($sign === '+') $channel->flags[$character] = true;
                else unset($channel->flags[$character]);
                $changes[] = (object) ['sign' => $sign, 'character' => $character, 'argument' => null];
            }
        }
        if (count($changes) > 0) {
            $this->broadcast($channel, ':' . $client->prefix() . ' MODE ' . $channel->name . ' ' . changeString($changes));
        }
    }

    private function channelReport(): array
    {
        $lines = [];
        $members = $bans = 0;
        foreach ($this->channels as $channel) {
            $lines[] = 'CHANNEL ' . $channel->name . ' created ' . $channel->creationTime . ' members ' . count($channel->members)
                . ' peak ' . $channel->peak . ' messages ' . $channel->messages . ' modes ' . $channel->modeDisplay(true);
            $lines[] = $channel->topic !== '' ? 'TOPIC ' . $channel->topicSetter . ' ' . $channel->topicTime . ' ' . $channel->topic : 'TOPIC none';
            foreach ($channel->bans as $ban) $lines[] = 'BAN ' . $ban->mask . ' ' . $ban->setter . ' ' . $ban->time;
            $lines[] = 'MEMBERS ' . $channel->nameList();
            $members += count($channel->members);
            $bans += count($channel->bans);
        }
        $lines[] = 'TOTAL channels ' . count($this->channels) . ' members ' . $members . ' bans ' . $bans;
        return $lines;
    }

    private function clientReport(): array
    {
        $lines = [];
        $registered = $invisible = $away = 0;
        foreach ($this->clients as $client) {
            $username = $client->username ?? '*';
            $signon = $client->registered ? $client->registrationTime : '-';
            $channels = array_map(fn($channel) => $channel->labelFor($client), $client->channels);
            $invites = array_map(fn($channel) => $channel->name, $client->invites);
            $lines[] = 'CLIENT ' . $client->id . ' ' . $client->addressee() . ' ' . $username . ' ' . $client->host . ' ' . $client->mode()
                . ' connected ' . $client->connectionTime . ' signon ' . $signon . ' received ' . $client->received . ' sent ' . $client->sent
                . ' tokens ' . $client->tokens . ' queue ' . count($client->queue) . ' channels ' . (count($channels) ? implode(',', $channels) : 'none')
                . ' invites ' . (count($invites) ? implode(',', $invites) : 'none');
            if ($client->away !== '') $lines[] = 'AWAY ' . $client->id . ' ' . $client->away;
            if ($client->registered) $registered++;
            if ($client->invisible) $invisible++;
            if ($client->away !== '') $away++;
        }
        $lines[] = 'TOTAL clients ' . count($this->clients) . ' registered ' . $registered . ' invisible ' . $invisible . ' away ' . $away;
        return $lines;
    }

    private function statsReport(): array
    {
        $pending = 0;
        foreach ($this->clients as $client) $pending += count($client->queue);
        $counts = $this->messages;
        $lines = [
            'END ' . $this->endTime,
            'LINES total ' . $this->lines['total'] . ' connect ' . $this->lines['connect'] . ' disconnect ' . $this->lines['disconnect'] . ' messages ' . $this->lines['messages'],
            'MESSAGES dropped ' . $counts['dropped'] . ' queued ' . $counts['queued'] . ' processed ' . $counts['processed']
                . ' discarded ' . $counts['discarded'] . ' pending ' . $pending . ' empty ' . $counts['empty'],
            'SENT lines ' . count($this->sent) . ' numerics ' . $this->sentCounts['numerics'] . ' pings ' . $this->sentCounts['pings'] . ' errors ' . $this->sentCounts['errors']
        ];
        $commands = $this->commands;
        ksort($commands, SORT_STRING);
        foreach ($commands as $command => $count) $lines[] = 'COMMAND ' . $command . ' ' . $count;
        $numerics = $this->numerics;
        ksort($numerics, SORT_NUMERIC);
        foreach ($numerics as $number => $count) $lines[] = 'NUMERIC ' . sprintf('%03d', $number) . ' ' . $count;
        $lines[] = 'PEAK connections ' . $this->connectionPeak['count'] . ' at ' . $this->connectionPeak['time'];
        $lines[] = 'PEAK registered ' . $this->registrationPeak['count'] . ' at ' . $this->registrationPeak['time'];
        $lines[] = 'DISCONNECTS quit ' . $this->disconnections['quit'] . ' closed ' . $this->disconnections['closed']
            . ' flood ' . $this->disconnections['flood'] . ' timeout ' . $this->disconnections['timeout'];
        foreach ($this->gone as $record) $lines[] = 'GONE ' . $record->time . ' ' . $record->id . ' ' . $record->addressee . ' ' . $record->reason;
        return $lines;
    }

    public function writeReports()
    {
        if (!is_dir('output')) mkdir('output', 0777, true);
        $reports = ['sent' => $this->sent, 'channels' => $this->channelReport(),
            'clients' => $this->clientReport(), 'stats' => $this->statsReport()];
        foreach ($reports as $name => $lines) {
            file_put_contents('output/' . $name . '.txt', count($lines) > 0 ? implode("\n", $lines) . "\n" : '');
        }
    }
}

[$settings, $traffic] = readInputs();
$simulation = new Simulator($settings, $traffic);
$simulation->run();
$simulation->writeReports();
