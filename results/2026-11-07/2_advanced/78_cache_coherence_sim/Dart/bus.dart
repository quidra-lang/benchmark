part of 'main.dart';

const busTypes = ['BusRd', 'BusRdX', 'BusUpgr', 'BusWr', 'WB'];

class Transaction {
  int number = 0, start = 0, invalidations = 0, hits = 0;
  final int core, block;
  final String kind;
  String snoop = '', source = '', l2 = '', eviction = '';
  Transaction(this.core, this.block, this.kind);
  String text(int lineSize) {
    var out = '$number $start c$core $kind ${address(block * lineSize)}';
    if (kind == 'WB') return out;
    out += ' snoop $snoop';
    if (kind == 'BusRd' || kind == 'BusRdX') out += ' data $source';
    if (kind != 'BusUpgr') out += ' l2 $l2$eviction';
    return out;
  }
}

class Bus {
  int free = 0, wait = 0, busy = 0;
  final List<Transaction> transactions = [];
  Transaction assign(int request, int latency, Transaction t) {
    t.start = max(request, free);
    wait += t.start - request;
    free = t.start + latency;
    busy += latency;
    t.number = transactions.length + 1;
    return t;
  }
}
