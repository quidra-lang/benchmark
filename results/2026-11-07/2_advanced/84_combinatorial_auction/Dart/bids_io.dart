part of 'main.dart';

class Item {
  final String name;
  final int reserve;
  Item(this.name, this.reserve);
}

class BidLine {
  final String name, language;
  final List<String> raw;
  BidLine(this.name, this.language, this.raw);
}

class RawAuction {
  final String name;
  final List<String> offered;
  final List<BidLine> lines = [];
  RawAuction(this.name, this.offered);
}

class Participant {
  final String name;
  final int value, bid;
  Participant(this.name, this.value, this.bid);
}

class Group {
  final String kind, name;
  final List<String> arguments;
  final List<Participant> participants = [];
  Group(this.kind, this.name, this.arguments);
}

class Input {
  final List<Item> items = [];
  final Map<String, RawAuction> auctions = {};
  final List<Group> groups = [];
  final List<String> runs = [];
  final Map<String, int> parameters = {};
}

class Bid {
  final int number, bidder, mask, size, amount, reserve;
  final bool xor;
  Bid(
    this.number,
    this.bidder,
    this.mask,
    this.size,
    this.amount,
    this.reserve,
    this.xor,
  );
}

List<String> lines(String path) => File(path).readAsLinesSync();
Input readInput() {
  final input = Input();
  for (final line in lines('input/items.txt')) {
    final a = line.split(' ');
    input.items.add(Item(a[0], int.parse(a[1])));
  }
  RawAuction? current;
  for (final line in lines('input/bids.txt')) {
    final a = line.split(' ');
    if (a[0] == 'auction') {
      current = RawAuction(a[1], a.sublist(2));
      input.auctions[current.name] = current;
    } else {
      current!.lines.add(BidLine(a[1], a[2], a.sublist(3)));
    }
  }
  for (final line in lines('input/single_item.txt')) {
    final a = line.split(' ');
    if (a[0] == 'lot' || a[0] == 'slots') {
      input.groups.add(Group(a[0], a[1], a.sublist(2)));
    } else {
      input.groups.last.participants.add(
        Participant(a[1], int.parse(a[2]), int.parse(a[3])),
      );
    }
  }
  for (final line in lines('input/params.txt')) {
    final a = line.split(' ');
    if (a[0] == 'run') {
      input.runs.addAll(a.skip(1));
    } else {
      input.parameters[a[0]] = int.parse(a[1]);
    }
  }
  return input;
}
