import 'headers.dart';

sealed class Address {}

class Mailbox extends Address {
  final String name;
  final String address;
  Mailbox(this.name, this.address);
}

class Group extends Address {
  final List<Mailbox> mailboxes;
  Group(this.mailboxes);
}

bool dotAtom(List<Token> tokens) {
  if (tokens.length.isEven) return false;
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].kind != (i.isEven ? 'word' : '.')) return false;
  }
  return true;
}

class AddressParser {
  final List<Token> tokens;
  var position = 0;
  var encodingError = false;
  var failed = false;
  AddressParser(this.tokens);

  String get peek => position < tokens.length ? tokens[position].kind : '';

  void expect(String kind) {
    if (peek != kind) {
      failed = true;
    } else {
      position++;
    }
  }

  List<Token> run(bool phrase) {
    final start = position;
    while (peek == 'word' || peek == '.' || phrase && peek == 'quoted') {
      position++;
    }
    return tokens.sublist(start, position);
  }

  String displayName(List<Token> phrase) {
    final output = StringBuffer();
    var previous = false;
    for (var i = 0; i < phrase.length; i++) {
      final token = phrase[i];
      var text = token.text;
      var decoded = false;
      if (token.kind == 'word') {
        final result = decodeWord(text);
        text = result.$1;
        decoded = result.$2;
        encodingError = encodingError || result.$3;
      }
      if (i > 0 && token.spaced && !(decoded && previous)) output.write(' ');
      output.write(text);
      previous = decoded;
    }
    return collapseWhitespace(output.toString());
  }

  Mailbox? mailbox(List<Token> phrase, List<Token> local,
      List<Token> domain, bool named) {
    if (!dotAtom(local) || !dotAtom(domain)) {
      failed = true;
      return null;
    }
    final text = '${local.map((t) => t.text).join()}@'
        '${domain.map((t) => t.text).join()}';
    return Mailbox(named ? displayName(phrase) : '', text.toLowerCase());
  }

  Address? address(bool inGroup) {
    final phrase = run(true);
    if (peek == '<') {
      position++;
      final local = run(false);
      expect('@');
      final domain = run(false);
      expect('>');
      return mailbox(phrase, local, domain, true);
    }
    if (peek == '@') {
      position++;
      final domain = run(false);
      return mailbox([], phrase, domain, false);
    }
    if (peek == ':' && phrase.isNotEmpty && !inGroup) {
      position++;
      final mailboxes = <Mailbox>[];
      if (peek != ';') {
        while (true) {
          final entry = address(true);
          if (failed || entry is! Mailbox) {
            failed = true;
            return null;
          }
          mailboxes.add(entry);
          if (peek != ',') break;
          position++;
        }
      }
      expect(';');
      return Group(mailboxes);
    }
    failed = true;
    return null;
  }
}

(List<Address>, bool)? parseAddressList(String value) {
  final tokens = tokenize(value, false);
  if (tokens == null || tokens.isEmpty) return null;
  final parser = AddressParser(tokens);
  final addresses = <Address>[];
  while (true) {
    final address = parser.address(false);
    if (parser.failed || address == null) return null;
    addresses.add(address);
    if (parser.peek != ',') break;
    parser.position++;
  }
  if (parser.position != tokens.length) return null;
  return (addresses, parser.encodingError);
}
