import 'dart:io';
import 'addresses.dart';
import 'dates.dart';
import 'headers.dart';
import 'mime.dart';
import 'threader.dart';

const checkedFields = [
  'From', 'To', 'Cc', 'Subject', 'Date', 'Message-ID', 'In-Reply-To',
  'References', 'MIME-Version', 'Content-Type', 'Content-Transfer-Encoding',
  'Content-Disposition'
];
const hiddenTags = ['head', 'style', 'script'];
const paragraphTags = [
  'p', 'div', 'ul', 'ol', 'table', 'tr', 'blockquote',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6'
];
const characterReferences = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '
};

List<String> readLines(String path) {
  final lines = File(path).readAsStringSync().split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

List<List<MailLine>> readMailbox(String path) {
  final messages = <List<MailLine>>[];
  final lines = readLines(path);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (line.startsWith('From ')) {
      messages.add([]);
      continue;
    }
    final unquoted = line.replaceFirst(RegExp(r'^>+'), '');
    if (unquoted != line && unquoted.startsWith('From ')) {
      line = line.substring(1);
    }
    if (messages.isNotEmpty) messages.last.add(MailLine(i + 1, line));
  }
  for (final lines in messages) {
    if (lines.isNotEmpty && lines.last.text.isEmpty) lines.removeLast();
  }
  return messages;
}

(List<MailLine>, List<MailLine>) splitSections(List<MailLine> lines) {
  final index = lines.indexWhere((line) => line.text.isEmpty);
  if (index < 0) return (lines, []);
  return (lines.sublist(0, index), lines.sublist(index + 1));
}

bool isMessageID(String text) {
  if (text.length < 3 || !text.startsWith('<') || !text.endsWith('>')) return false;
  final inside = text.substring(1, text.length - 1);
  if ('@'.allMatches(inside).length != 1 ||
      inside.startsWith('@') || inside.endsWith('@')) return false;
  return inside.codeUnits.every((c) =>
      c >= 33 && c <= 126 && !'<>()"\\'.contains(String.fromCharCode(c)));
}

List<String> extractIDs(String value) {
  final ids = <String>[];
  var position = 0;
  while (position < value.length) {
    final start = value.indexOf('<', position);
    if (start < 0) break;
    final end = value.indexOf('>', start + 1);
    if (end < 0) break;
    final id = value.substring(start, end + 1);
    if (isMessageID(id)) ids.add(id);
    position = end + 1;
  }
  return ids;
}

String dateNotation(int? date) => date == null ? 'invalid' : formatUTC(date);
String subjectNotation(String subject) => subject.isEmpty ? '(no subject)' : subject;
String dash(String text) => text.isEmpty ? '-' : text;

class Entity {
  final String number;
  var mainType = 'text';
  var subtype = 'plain';
  Map<String, String> parameters = {};
  String? disposition;
  String? filename;
  List<Entity>? children;
  var content = '';
  Entity(this.number);

  String parameter(String name) => parameters[name] ?? '';
}

class Message {
  final int number;
  final problems = <String>[];
  Mailbox? sender;
  List<String> to = [];
  List<String> cc = [];
  var subject = '';
  var baseSubject = '';
  var reply = false;
  int? date;
  var id = '';
  List<String> references = [];
  late Entity body;
  var thread = 0;
  var depth = 0;
  Message? parent;
  Message(this.number);

  void process(List<MailLine> lines, Map<String, int> knownIDs) {
    final (headerLines, bodyLines) = splitSections(lines);
    final header = parseFields(headerLines);
    for (final number in header.invalid) {
      problems.add('bad header line $number');
    }
    for (final name in checkedFields) {
      if (header.count(name) > 1) problems.add('duplicate $name');
    }
    final from = header.value('From');
    if (from == null) {
      problems.add('missing From');
    } else {
      final parsed = parseAddressList(from);
      if (parsed == null || parsed.$1.length != 1 || parsed.$1[0] is! Mailbox) {
        problems.add('bad From');
      } else {
        sender = parsed.$1[0] as Mailbox;
        if (parsed.$2) problems.add('bad encoded word in From');
      }
    }
    to = recipients(header.value('To'), 'To');
    cc = recipients(header.value('Cc'), 'Cc');
    final decoded = decodeUnstructured(header.value('Subject') ?? '');
    subject = decoded.$1;
    if (decoded.$2) problems.add('bad encoded word in Subject');
    baseSubject = subject;
    while (baseSubject.toLowerCase().startsWith('re:')) {
      baseSubject = baseSubject.substring(3).replaceFirst(RegExp(r'^ +'), '');
      reply = true;
    }
    final dateValue = header.value('Date');
    if (dateValue == null) {
      problems.add('missing Date');
    } else {
      final parsed = parseDate(dateValue);
      date = parsed.$1;
      if (parsed.$2.isNotEmpty) problems.add(parsed.$2);
    }
    final idValue = header.value('Message-ID');
    if (idValue == null) {
      problems.add('missing Message-ID');
    } else if (!isMessageID(idValue)) {
      problems.add('bad Message-ID');
    } else if (knownIDs.containsKey(idValue)) {
      problems.add('Message-ID already used by message ${knownIDs[idValue]}');
    } else {
      id = idValue;
      knownIDs[id] = number;
    }
    references = extractIDs(header.value('References') ?? '');
    final replies = extractIDs(header.value('In-Reply-To') ?? '');
    if (replies.isNotEmpty && (references.isEmpty || references.last != replies.first)) {
      references.add(replies.first);
    }
    final version = header.value('MIME-Version');
    var mime = false;
    if (version != null) {
      final text = removeComments(version);
      mime = text != null && text.replaceAll(RegExp(r'[ \t]'), '') == '1.0';
      if (!mime) problems.add('bad MIME-Version');
    }
    body = parseEntity('1', header, bodyLines, mime);
  }

  List<String> recipients(String? value, String name) {
    if (value == null) return [];
    final parsed = parseAddressList(value);
    if (parsed == null) {
      problems.add('bad $name');
      return [];
    }
    final result = <String>[];
    for (final address in parsed.$1) {
      switch (address) {
        case Mailbox():
          result.add(address.address);
        case Group():
          result.addAll(address.mailboxes.map((mailbox) => mailbox.address));
      }
    }
    if (parsed.$2) problems.add('bad encoded word in $name');
    return result;
  }

  Entity parseEntity(String number, Header header, List<MailLine> lines, bool mime) {
    final entity = Entity(number);
    final contentType = header.value('Content-Type');
    if (mime && contentType != null) {
      final parsed = parseParameters(contentType, true);
      if (parsed == null) {
        problems.add('bad Content-Type in part $number');
      } else {
        entity.mainType = parsed.mainType;
        entity.subtype = parsed.subtype;
        entity.parameters = parsed.values;
      }
    }
    final disposition = header.value('Content-Disposition');
    if (mime && disposition != null) {
      final parsed = parseParameters(disposition, false);
      if (parsed == null) {
        problems.add('bad Content-Disposition in part $number');
      } else {
        entity.disposition = parsed.mainType;
        entity.filename = parsed.values['filename'];
      }
    }
    if (entity.filename == null || entity.filename!.isEmpty) {
      entity.filename = entity.parameters['name'];
    }
    final charset = entity.parameters['charset'];
    if (entity.mainType == 'text' && charset != null && charset.toLowerCase() != 'us-ascii') {
      problems.add('unsupported charset "${charset.toLowerCase()}" in part $number');
    }
    if (mime && entity.mainType == 'multipart') {
      final boundary = entity.parameter('boundary');
      if (boundary.isNotEmpty) {
        splitMultipart(entity, lines, boundary);
        return entity;
      }
      problems.add('missing boundary in part $number');
    }
    final original = lines.map((line) => line.text).join('\n');
    final encoding = mime ? (header.value('Content-Transfer-Encoding') ?? '7bit').toLowerCase() : '7bit';
    if (encoding == 'base64') {
      final content = decodeBase64Body(original);
      if (content == null) problems.add('bad base64 in part $number');
      entity.content = content ?? '';
    } else if (encoding == 'quoted-printable') {
      final (content, error) = decodeQuotedPrintable(original);
      if (error) problems.add('bad quoted-printable in part $number');
      entity.content = content;
    } else {
      entity.content = original;
      if (!['7bit', '8bit', 'binary'].contains(encoding)) {
        problems.add('unknown encoding "$encoding" in part $number');
      }
    }
    return entity;
  }

  void splitMultipart(Entity entity, List<MailLine> lines, String boundary) {
    final parts = <List<MailLine>>[];
    var closed = false;
    for (final line in lines) {
      final text = stripTrailing(line.text);
      if (text == '--$boundary--') {
        closed = true;
        break;
      }
      if (text == '--$boundary') {
        parts.add([]);
      } else if (parts.isNotEmpty) {
        parts.last.add(line);
      }
    }
    if (parts.isEmpty) {
      problems.add('no parts in part ${entity.number}');
    } else if (!closed) {
      problems.add('unterminated multipart in part ${entity.number}');
    }
    entity.children = [];
    for (var i = 0; i < parts.length; i++) {
      final (headerLines, bodyLines) = splitSections(parts[i]);
      final header = parseFields(headerLines);
      for (final number in header.invalid) {
        problems.add('bad header line $number');
      }
      entity.children!.add(parseEntity('${entity.number}.${i + 1}', header, bodyLines, true));
    }
  }
}

List<Entity> collectTextParts(Entity entity, bool allowHTML) {
  if (entity.children == null) {
    if (entity.disposition == 'attachment' || entity.mainType != 'text') return [];
    if (entity.subtype == 'plain' || entity.subtype == 'html' && allowHTML) return [entity];
    return [];
  }
  if (entity.subtype == 'alternative') {
    for (final html in [false, true]) {
      for (final child in entity.children!) {
        final parts = collectTextParts(child, html);
        if (parts.isNotEmpty) return parts;
      }
    }
    return [];
  }
  return [for (final child in entity.children!) ...collectTextParts(child, allowHTML)];
}

class LogicalLine {
  final int depth;
  String text;
  bool flowing;
  LogicalLine(this.depth, this.text, [this.flowing = false]);
}

String quotePrefix(int depth) =>
    depth > 0 ? '${List.filled(depth, '>').join()} ' : '';

List<String> wrap(String text, String prefix) {
  final lines = <String>[];
  var current = '';
  for (final word in splitWords(text)) {
    if (current.isNotEmpty && current.length + 1 + word.length > 72) {
      lines.add('$prefix$current');
      current = word;
    } else if (current.isNotEmpty) {
      current += ' $word';
    } else {
      current = word;
    }
  }
  lines.add('$prefix$current');
  return lines;
}

List<String> flowedLines(String content, bool deleteSpace) {
  if (content.isEmpty) return [];
  final logical = <LogicalLine>[];
  for (final line in content.split('\n')) {
    var text = line.replaceFirst(RegExp(r'^>+'), '');
    final depth = line.length - text.length;
    if (text.startsWith(' ')) text = text.substring(1);
    final flowing = text.endsWith(' ') && text != '-- ';
    if (logical.isNotEmpty && logical.last.flowing && logical.last.depth == depth) {
      final previous = logical.last;
      if (deleteSpace) previous.text = previous.text.substring(0, previous.text.length - 1);
      previous.text += text;
      previous.flowing = flowing;
    } else {
      logical.add(LogicalLine(depth, text, flowing));
    }
  }
  return [for (final line in logical) ...wrap(line.text, quotePrefix(line.depth))];
}

String tagName(String text) =>
    RegExp(r'^[A-Za-z0-9]*').firstMatch(text)!.group(0)!.toLowerCase();

String replaceReferences(String text) {
  final output = StringBuffer();
  var position = 0;
  while (position < text.length) {
    String? replacement;
    var end = -1;
    if (text[position] == '&') {
      end = text.indexOf(';', position + 1);
      if (end >= 0) {
        final name = text.substring(position + 1, end);
        replacement = characterReferences[name];
        if (replacement == null && name.startsWith('#') && digits(name.substring(1), [1, 2, 3])) {
          final value = int.parse(name.substring(1));
          if (value >= 32 && value <= 126) replacement = String.fromCharCode(value);
        }
      }
    }
    if (replacement == null) {
      output.write(text[position++]);
    } else {
      output.write(replacement);
      position = end + 1;
    }
  }
  return output.toString();
}

List<String> htmlLines(String content) {
  final blocks = <LogicalLine>[];
  var depth = 0;
  var position = 0;
  var text = '';
  String? hide;
  while (position < content.length) {
    final close = content[position] == '<' ? content.indexOf('>', position + 1) : -1;
    if (close < 0) {
      if (hide == null) text += content[position];
      position++;
      continue;
    }
    var inside = content.substring(position + 1, close);
    position = close + 1;
    final endTag = inside.startsWith('/');
    if (endTag) inside = inside.substring(1);
    final name = tagName(inside);
    if (hide != null) {
      if (endTag && name == hide) hide = null;
    } else if (!endTag && hiddenTags.contains(name)) {
      hide = name;
    } else if (name == 'br' || name == 'li' && !endTag) {
      blocks.add(LogicalLine(depth, text));
      text = name == 'li' ? '* ' : '';
    } else if (paragraphTags.contains(name)) {
      blocks.addAll([LogicalLine(depth, text), LogicalLine(depth, '')]);
      text = '';
      if (name == 'blockquote') {
        if (!endTag) {
          depth++;
        } else if (depth > 0) {
          depth--;
        }
      }
    }
  }
  blocks.add(LogicalLine(depth, text));
  final lines = <String>[];
  for (final block in blocks) {
    text = collapseWhitespace(block.text.replaceAll('\n', ' '));
    text = replaceReferences(text).replaceFirst(RegExp(r'^ +'), '').replaceFirst(RegExp(r' +$'), '');
    if (text.isNotEmpty) {
      lines.addAll(wrap(text, quotePrefix(block.depth)));
    } else if (lines.isNotEmpty && lines.last.isNotEmpty) {
      lines.add('');
    }
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

(String, List<String>) displayLines(Entity entity) {
  if (entity.subtype == 'html') return ('html', htmlLines(entity.content));
  if (entity.parameter('format').toLowerCase() == 'flowed') {
    return ('flowed', flowedLines(entity.content, entity.parameter('delsp').toLowerCase() == 'yes'));
  }
  return ('plain', entity.content.isEmpty ? [] : entity.content.split('\n'));
}

class ThreadEntry {
  final Container container;
  final String prefix;
  final int depth;
  ThreadEntry(this.container, this.prefix, this.depth);
}

class Thread {
  final int number;
  final Container root;
  final entries = <ThreadEntry>[];
  final messages = <Message>[];
  Thread(this.number, this.root) {
    walk(root, '', '', 0);
  }

  void walk(Container container, String prefix, String stem, int depth) {
    entries.add(ThreadEntry(container, prefix, depth));
    final message = container.message;
    if (message != null) {
      messages.add(message);
      message.thread = number;
      message.depth = depth;
      message.parent = container.parent?.message;
    }
    for (var i = 0; i < container.children.length; i++) {
      if (i < container.children.length - 1) {
        walk(container.children[i], '$stem+- ', '$stem|  ', depth + 1);
      } else {
        walk(container.children[i], '$stem`- ', '$stem   ', depth + 1);
      }
    }
  }

  List<String> report() {
    final depth = entries.map((entry) => entry.depth).reduce((a, b) => a > b ? a : b);
    final senders = messages.where((m) => m.sender != null).map((m) => m.sender!.address).toSet();
    final dates = messages.map((m) => m.date).whereType<int>().toList()..sort();
    final lines = <String>[
      'thread $number messages ${messages.length} depth $depth senders ${senders.length}',
      dates.isEmpty ? 'span -' : 'span ${formatUTC(dates.first)} .. ${formatUTC(dates.last)}',
      'subject ${subjectNotation(root.subject ?? rootSubject(root))}',
    ];
    for (final entry in entries) {
      lines.add('${entry.prefix}${containerNotation(entry.container)}');
    }
    return lines;
  }
}

String containerNotation(Container container) {
  final message = container.message;
  if (message != null) {
    return '[${message.number}] ${dateNotation(message.date)} '
        '${message.sender?.address ?? '-'} ${subjectNotation(message.subject)}';
  }
  return container.subject != null ? '[subject] ${container.subject}' : '[missing] ${container.id}';
}

String senderNotation(Mailbox? sender) {
  if (sender == null) return '-';
  return sender.name.isEmpty ? sender.address : '${sender.name} <${sender.address}>';
}

List<String> entityLines(Entity entity) {
  var line = 'part ${entity.number} ${entity.mainType}/${entity.subtype}';
  if (entity.children != null) {
    return [line, for (final child in entity.children!) ...entityLines(child)];
  }
  line += ' ${entity.content.length}';
  if (entity.disposition != null) line += ' ${entity.disposition}';
  if (entity.filename != null && entity.filename!.isNotEmpty) line += ' "${entity.filename}"';
  return [line];
}

List<String> messageReport(Message message) => [
  'message ${message.number}',
  'id ${dash(message.id)}',
  'date ${dateNotation(message.date)}',
  'from ${senderNotation(message.sender)}',
  'to ${dash(message.to.join(', '))}',
  'cc ${dash(message.cc.join(', '))}',
  'subject ${subjectNotation(message.subject)}',
  'refs ${dash(message.references.join(' '))}',
  'thread ${message.thread} depth ${message.depth} parent ${message.parent?.number ?? '-'}',
  ...entityLines(message.body),
];

List<String> bodyReport(String request, Map<String, Message> messages) {
  final lines = ['request $request'];
  final message = messages[request];
  if (message == null) return [...lines, 'not found'];
  final parts = collectTextParts(message.body, true);
  lines.add('message ${message.number} text parts ${parts.length}');
  for (final part in parts) {
    final (format, display) = displayLines(part);
    var quoted = 0;
    var signature = 0;
    for (var i = 0; i < display.length; i++) {
      final line = stripTrailing(display[i]);
      if (line.startsWith('>')) quoted++;
      if (line == '--') signature = display.length - i - 1;
    }
    lines.add('part ${part.number} $format lines ${display.length} quoted $quoted signature $signature');
    for (final text in display) {
      final line = stripTrailing(text);
      lines.add(line.isEmpty ? '|' : '| $line');
    }
  }
  return lines;
}

class SenderStats {
  final String address;
  var name = '';
  var count = 0;
  final threads = <int>{};
  int? first;
  int? last;
  SenderStats(this.address);

  void add(Message message) {
    count++;
    threads.add(message.thread);
    final date = message.date;
    if (date != null) {
      if (first == null || date < first!) first = date;
      if (last == null || date > last!) last = date;
    }
    if (message.sender!.name.isNotEmpty) name = message.sender!.name;
  }
}

String csvField(String text) => text.contains(',') || text.contains('"')
    ? '"${text.replaceAll('"', '""')}"' : text;

List<String> sendersReport(List<Message> messages) {
  final stats = <String, SenderStats>{};
  for (final message in messages) {
    final sender = message.sender;
    if (sender == null) continue;
    stats.putIfAbsent(sender.address, () => SenderStats(sender.address)).add(message);
  }
  final entries = stats.values.toList()..sort((a, b) {
    final countOrder = b.count.compareTo(a.count);
    return countOrder != 0 ? countOrder : a.address.compareTo(b.address);
  });
  return [
    'address,name,messages,threads,first,last',
    for (final entry in entries)
      '${entry.address},${csvField(entry.name)},${entry.count},${entry.threads.length},'
      '${entry.first == null ? '-' : formatUTC(entry.first!)},'
      '${entry.last == null ? '-' : formatUTC(entry.last!)}',
  ];
}

List<String> malformedReport(List<Message> messages) {
  final flagged = messages.where((message) => message.problems.isNotEmpty).length;
  final total = messages.fold<int>(0, (total, message) => total + message.problems.length);
  return [
    'messages ${messages.length} malformed $flagged problems $total',
    for (final message in messages)
      for (final problem in message.problems) 'message ${message.number}: $problem',
  ];
}

List<String> joinBlocks(Iterable<List<String>> blocks) {
  final lines = <String>[];
  for (final block in blocks) {
    if (lines.isNotEmpty) lines.add('');
    lines.addAll(block);
  }
  return lines;
}

void writeOutput(String name, List<String> lines) {
  File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}

void main() {
  final messages = <Message>[];
  final knownIDs = <String, int>{};
  final mailbox = readMailbox('input/mailbox.mbox');
  for (var i = 0; i < mailbox.length; i++) {
    messages.add(Message(i + 1)..process(mailbox[i], knownIDs));
  }
  final roots = buildThreads(messages);
  final threads = [for (var i = 0; i < roots.length; i++) Thread(i + 1, roots[i])];
  for (final message in messages) {
    final parent = message.parent;
    if (parent != null && message.date != null && parent.date != null && message.date! < parent.date!) {
      message.problems.add('dated before parent message ${parent.number}');
    }
  }
  final byID = {for (final message in messages) if (message.id.isNotEmpty) message.id: message};
  final requests = readLines('input/requests.txt');
  Directory('output').createSync(recursive: true);
  writeOutput('threads.txt', joinBlocks(threads.map((thread) => thread.report())));
  writeOutput('messages.txt', joinBlocks(messages.map(messageReport)));
  writeOutput('bodies.txt', joinBlocks(requests.map((request) => bodyReport(request, byID))));
  writeOutput('senders.csv', sendersReport(messages));
  writeOutput('malformed.txt', malformedReport(messages));
}
