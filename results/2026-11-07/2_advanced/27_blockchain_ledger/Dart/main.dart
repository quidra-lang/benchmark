import 'dart:io';
import 'dart:math' as math;
import 'hashing.dart';
import 'wallets.dart';
import 'transactions.dart';
import 'blocks.dart';
import 'chain.dart';

List<String> readLines(String path) => File(path).readAsLinesSync();
String line(List<Object> parts) => parts.join(' ');
String signed(int value) => value >= 0 ? '+$value' : '$value';
void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');

class Settings {
  final Map<String, List<String>> fields;
  Settings()
    : fields = {
        for (final text in readLines('input/params.txt'))
          text.split(' ').first: text.split(' ').skip(1).toList(),
      };
  int number(String key, [int i = 0]) => int.parse(fields[key]![i]);
  int get maturity => number('MATURITY');
  int get maxBlock => number('MAXBLOCK');
  int get minFee => number('MINFEERATE');
  int get maxMempool => number('MEMPOOL');
  int get maxOrphans => number('ORPHANS');
  int get drift => number('DRIFT');
  int get expiry => number('EXPIRY');
  int get maxReorg => number('MAXREORG');
  int get ban => number('BAN');
  int get blockPenalty => number('BAN', 1);
  int get txPenalty => number('BAN', 2);
}

class Peer {
  final String name;
  int acceptedBlocks = 0,
      rejectedBlocks = 0,
      orphans = 0,
      acceptedTxs = 0,
      rejectedTxs = 0,
      ignored = 0,
      score = 0;
  Peer(this.name);
}

class Entry {
  final Transaction transaction;
  final int fee, arrival;
  Entry(this.transaction, this.fee, this.arrival);
}

class Orphan {
  final Block block;
  final Peer peer;
  Orphan(this.block, this.peer);
}

class Reorganization {
  final int time, fork, disconnected, connected;
  final String old, next;
  Reorganization(
    this.time,
    this.fork,
    this.disconnected,
    this.connected,
    this.old,
    this.next,
  );
}

class Acceptance {
  final String? reason;
  final int fee;
  final List<Entry> conflicts;
  Acceptance(this.reason, [this.fee = 0, this.conflicts = const []]);
}

class Node {
  final Settings settings;
  final List<Wallet> wallets;
  late final Map<String, Wallet> named, owners;
  final records = <String, BlockRecord>{};
  final rejected = <String>{};
  final dropped = <String, String>{};
  final peers = <String, Peer>{};
  final rejections = <String, int>{};
  final reorganizations = <Reorganization>[];
  final logs = <String>[];
  var mempool = <Entry>[];
  final orphans = <Orphan>[];
  late BlockRecord tip;
  var mainChain = <BlockRecord>[];
  var confirmed = <String, int>{};
  int now = 0;
  Node(this.settings, this.wallets) {
    named = {for (final w in wallets) w.name: w};
    owners = {for (final w in wallets) w.address: w};
    final distribution = settings.fields['GENESIS']!;
    final outputs = [
      for (var i = 0; i < distribution.length; i += 2)
        (named[distribution[i]]!.address, int.parse(distribution[i + 1])),
    ];
    final t = coinbase(0, outputs);
    final b = Block(0, List.filled(32, '0').join(), t.txid, 0, 0, 0, [t]);
    final u = <Reference, Coin>{};
    applyTransaction(u, t, 0);
    tip = BlockRecord(b, null, u, [], 'genesis');
    records[b.hash] = tip;
    refresh();
  }
  void refresh() {
    mainChain = chainTo(tip);
    confirmed = {
      for (final r in mainChain)
        for (final t in r.block.transactions) t.txid: r.block.height,
    };
  }

  void log(List<Object> parts) => logs.add('$now ${line(parts)}');
  void tally(String category, String reason) {
    final key = '$category $reason';
    rejections[key] = (rejections[key] ?? 0) + 1;
  }

  int get height => tip.block.height + 1;
  int blockReward(int h) =>
      reward(h, settings.number('REWARD'), settings.number('REWARD', 1));
  int difficulty(BlockRecord parent) => requiredDifficulty(
    parent,
    settings.number('DIFFICULTY'),
    settings.number('RETARGET'),
    settings.number('RETARGET', 1),
  );
  bool mature(Coin c) => c.mature(height, settings.maturity);
  int balance(String address) => tip.utxo.values
      .where((c) => c.address == address)
      .fold(0, (total, c) => total + c.amount);
  Set<Reference> locked() => {for (final e in mempool) ...e.transaction.inputs};
  List<Entry> priority() => List<Entry>.of(mempool)
    ..sort((a, b) {
      final left = a.fee * b.transaction.size,
          right = b.fee * a.transaction.size;
      return left == right
          ? a.transaction.txid.compareTo(b.transaction.txid)
          : right.compareTo(left);
    });
  Entry? find(String id) {
    for (final e in mempool) {
      if (e.transaction.txid == id) return e;
    }
    return null;
  }

  Acceptance acceptance(Transaction t) {
    if (t.coinbase) return Acceptance('coinbase');
    if (confirmed.containsKey(t.txid) || find(t.txid) != null)
      return Acceptance('duplicate');
    final (reason, fee) = checkTransaction(
      t,
      tip.utxo,
      {},
      height,
      settings.maturity,
      owners,
    );
    if (reason != null) return Acceptance(reason);
    if (fee * 1000 < settings.minFee * t.size) return Acceptance('low-fee');
    final inputs = t.inputs.toSet();
    final conflicts = mempool
        .where((e) => e.transaction.inputs.any(inputs.contains))
        .toList();
    if (conflicts.isNotEmpty &&
        (fee <= conflicts.fold(0, (sum, e) => sum + e.fee) ||
            conflicts.any((e) => fee * e.transaction.size <= e.fee * t.size)))
      return Acceptance('conflict');
    return Acceptance(null, fee, conflicts);
  }

  void recordDrop(String id, String reason) {
    dropped[id] = reason;
    log(['DROP', short(id), reason]);
  }

  void drop(Entry e, String reason) {
    mempool.remove(e);
    recordDrop(e.transaction.txid, reason);
  }

  void register(Transaction t, Acceptance a, int arrival) {
    for (final e in a.conflicts) {
      drop(e, 'replaced');
    }
    mempool.add(Entry(t, a.fee, arrival));
    if (mempool.length > settings.maxMempool)
      drop(priority().last, 'mempool-full');
  }

  void switchTip(BlockRecord target) {
    final old = tip, fork = forkPoint(tip, target);
    final d = old.block.height - fork.block.height,
        c = target.block.height - fork.block.height;
    if (d > settings.maxReorg) {
      log([
        'REFUSE',
        target.block.height,
        short(target.block.hash),
        'work',
        target.work,
        'fork',
        fork.block.height,
        'depth',
        d,
      ]);
      return;
    }
    final returned = [
      for (final r in mainChain.skip(fork.block.height + 1))
        ...r.block.transactions.skip(1),
    ];
    tip = target;
    refresh();
    if (d == 0) {
      log([
        'TIP',
        target.block.height,
        short(target.block.hash),
        'work',
        target.work,
      ]);
    } else {
      log([
        'REORG',
        target.block.height,
        short(target.block.hash),
        'work',
        target.work,
        'fork',
        fork.block.height,
        'disconnected',
        d,
        'connected',
        c,
      ]);
      reorganizations.add(
        Reorganization(
          now,
          fork.block.height,
          d,
          c,
          old.block.hash,
          target.block.hash,
        ),
      );
    }
    final previous = mempool;
    mempool = [];
    final candidates = [
      for (final t in returned) (t, now, true),
      for (final e in previous) (e.transaction, e.arrival, false),
    ];
    for (final (t, arrival, isReturned) in candidates) {
      if (confirmed.containsKey(t.txid)) continue;
      final a = acceptance(t);
      if (a.reason != null) {
        recordDrop(t.txid, a.reason!);
      } else {
        if (isReturned) log(['RETURN', short(t.txid)]);
        register(t, a, arrival);
      }
    }
  }

  void penalize(Peer p, int points) {
    final before = p.score;
    p.score += points;
    if (before < settings.ban && p.score >= settings.ban)
      log(['BAN', p.name, 'score', p.score]);
  }

  void process(List<String> f, List<String> texts) {
    now = int.parse(f[0]);
    for (final e in List<Entry>.of(mempool)) {
      if (now - e.arrival >= settings.expiry) drop(e, 'expired');
    }
    switch (f[1]) {
      case 'PAY':
        pay(f);
      case 'BUMP':
        bump(f[2], int.parse(f[3]));
      case 'MINE':
        mine(named[f[2]]!);
      case 'STATUS':
        status(f[2]);
      case 'PRINT':
        printState();
      default:
        final p = peers.putIfAbsent(f[2], () => Peer(f[2]));
        if (p.score >= settings.ban) {
          p.ignored++;
          log(['IGNORE', p.name, f[1]]);
          return;
        }
        if (f[1] == 'TX') {
          receiveTransaction(p, Transaction(f[3]));
        } else {
          receiveBlock(p, parseBlock(f, texts));
        }
    }
  }

  void pay(List<String> f) {
    final sender = named[f[2]]!, fee = int.parse(f[3]);
    final outputs = [
      for (var i = 4; i < f.length; i += 2)
        (named[f[i]]!.address, int.parse(f[i + 1])),
    ];
    final total = outputs.fold(0, (sum, out) => sum + out.$2),
        lockedRefs = locked();
    final prefix = <Object>['PAY', sender.name, 'fee', fee, 'total', total];
    final coins =
        tip.utxo.keys
            .where(
              (ref) =>
                  tip.utxo[ref]!.address == sender.address &&
                  !lockedRefs.contains(ref) &&
                  mature(tip.utxo[ref]!),
            )
            .toList()
          ..sort((a, b) {
            final compared = tip.utxo[b]!.amount.compareTo(tip.utxo[a]!.amount);
            return compared != 0 ? compared : compareReferences(a, b);
          });
    final inputs = <Reference>[];
    var gathered = 0;
    for (final ref in coins) {
      if (gathered >= total + fee) break;
      inputs.add(ref);
      gathered += tip.utxo[ref]!.amount;
    }
    if (gathered < total + fee) {
      log([...prefix, 'rejected', 'insufficient-funds']);
      tally('pay', 'insufficient-funds');
      return;
    }
    if (gathered > total + fee)
      outputs.add((sender.address, gathered - total - fee));
    final t = payment(inputs, outputs, sender.secret);
    final a = acceptance(t);
    prefix.addAll(['tx', short(t.txid)]);
    if (a.reason != null) {
      log([...prefix, 'rejected', a.reason!]);
      tally('pay', a.reason!);
      return;
    }
    log([
      ...prefix,
      'accepted',
      'inputs',
      t.inputs.length,
      'outputs',
      t.outputs.length,
      'size',
      t.size,
    ]);
    register(t, a, now);
  }

  void bump(String id, int fee) {
    final prefix = <Object>['BUMP', short(id), 'fee', fee];
    void reject(String reason) {
      log([...prefix, 'rejected', reason]);
      tally('bump', reason);
    }

    final e = find(id);
    if (e == null) {
      reject('unknown');
      return;
    }
    final original = e.transaction,
        outputs = List<Output>.of(e.transaction.outputs);
    final last = outputs.last, change = outputs.last.$2 - (fee - e.fee);
    if (change < 1 ||
        original.inputs.any((ref) => tip.utxo[ref]!.address != last.$1)) {
      reject('no-change');
      return;
    }
    outputs[outputs.length - 1] = (last.$1, change);
    final t = payment(original.inputs, outputs, owners[last.$1]!.secret);
    final a = acceptance(t);
    prefix.addAll(['tx', short(t.txid)]);
    if (a.reason != null) {
      reject(a.reason!);
      return;
    }
    log([...prefix, 'accepted', 'size', t.size]);
    register(t, a, now);
  }

  void receiveTransaction(Peer p, Transaction t) {
    final a = acceptance(t);
    if (a.reason != null) {
      p.rejectedTxs++;
      tally('tx', a.reason!);
      log(['TX', p.name, short(t.txid), 'rejected', a.reason!]);
      if (['coinbase', 'bad-output', 'bad-sig', 'overspend'].contains(a.reason))
        penalize(p, settings.txPenalty);
      return;
    }
    p.acceptedTxs++;
    log([
      'TX',
      p.name,
      short(t.txid),
      'accepted',
      'fee',
      a.fee,
      'size',
      t.size,
    ]);
    register(t, a, now);
  }

  void mine(Wallet w) {
    final h = height, selected = <Transaction>[], fees = <int>[];
    var size = 0, total = 0;
    for (final e in priority()) {
      if (size + e.transaction.size <= settings.maxBlock) {
        selected.add(e.transaction);
        fees.add(e.fee);
        size += e.transaction.size;
        total += e.fee;
      }
    }
    final txs = [
      coinbase(h, [(w.address, blockReward(h) + total)]),
      ...selected,
    ];
    final b = mineBlock(
      h,
      tip.block.hash,
      txs,
      math.max(now, medianTime(tip) + 1),
      difficulty(tip),
    );
    final u = Utxo.of(tip.utxo);
    for (final t in txs) {
      applyTransaction(u, t, h);
    }
    final r = BlockRecord(b, tip, u, fees, 'local');
    records[b.hash] = r;
    log([
      'MINE',
      w.name,
      h,
      short(b.hash),
      'bits',
      b.difficulty,
      'nonce',
      b.nonce,
      'txs',
      txs.length,
      'size',
      b.size,
      'fees',
      r.fees,
      'work',
      r.work,
    ]);
    switchTip(r);
  }

  void receiveBlock(Peer p, Block b) {
    if (records.containsKey(b.hash) ||
        rejected.contains(b.hash) ||
        orphans.any((o) => o.block.hash == b.hash)) {
      log(['BLOCK', p.name, b.height, short(b.hash), 'rejected', 'duplicate']);
      p.rejectedBlocks++;
      tally('block', 'duplicate');
      return;
    }
    var reason = contextFreeError(b, settings.maxBlock);
    if (reason == null && rejected.contains(b.previous)) reason = 'bad-parent';
    if (reason != null) {
      rejectBlock('BLOCK', b, p, reason);
      resolveOrphans(b.hash);
      return;
    }
    if (!records.containsKey(b.previous)) {
      orphans.add(Orphan(b, p));
      p.orphans++;
      log([
        'BLOCK',
        p.name,
        b.height,
        short(b.hash),
        'orphan',
        'parent',
        short(b.previous),
      ]);
      if (orphans.length > settings.maxOrphans) {
        final evicted = orphans.removeAt(0);
        log(['EVICT', short(evicted.block.hash), 'orphan-limit']);
      }
      return;
    }
    connectBlock('BLOCK', b, p);
    resolveOrphans(b.hash);
  }

  (String?, Utxo?, List<int>?) validateBlock(Block b, BlockRecord p) {
    if (b.height != p.block.height + 1) return ('bad-height', null, null);
    if (b.difficulty != difficulty(p)) return ('bad-difficulty', null, null);
    if (b.timestamp <= medianTime(p)) return ('time-too-old', null, null);
    if (b.timestamp > now + settings.drift) return ('time-too-new', null, null);
    final u = Utxo.of(p.utxo), spent = <Reference>{}, fees = <int>[];
    var total = 0;
    for (var i = 1; i < b.transactions.length; i++) {
      final t = b.transactions[i];
      final (reason, fee) = checkTransaction(
        t,
        u,
        spent,
        b.height,
        settings.maturity,
        owners,
      );
      if (reason != null) return ('$reason tx ${i + 1}', null, null);
      spent.addAll(t.inputs);
      applyTransaction(u, t, b.height);
      fees.add(fee);
      total += fee;
    }
    final cb = b.transactions.first;
    if (cb.outputs.any((out) => !owners.containsKey(out.$1) || out.$2 == 0))
      return ('bad-output tx 1', null, null);
    if (cb.outputTotal > blockReward(b.height) + total)
      return ('bad-coinbase', null, null);
    applyTransaction(u, cb, b.height);
    return (null, u, fees);
  }

  void connectBlock(String kind, Block b, Peer p) {
    final parent = records[b.previous]!;
    final (reason, u, fees) = validateBlock(b, parent);
    if (reason != null) {
      rejectBlock(kind, b, p, reason);
      return;
    }
    final r = BlockRecord(b, parent, u!, fees!, p.name);
    records[b.hash] = r;
    p.acceptedBlocks++;
    log([kind, p.name, b.height, short(b.hash), 'accepted', 'work', r.work]);
    if (r.work > tip.work) switchTip(r);
  }

  void rejectBlock(String kind, Block b, Peer p, String reason) {
    rejected.add(b.hash);
    p.rejectedBlocks++;
    tally('block', reason.split(' ').first);
    log([kind, p.name, b.height, short(b.hash), 'rejected', reason]);
    if (reason != 'time-too-new') penalize(p, settings.blockPenalty);
  }

  void resolveOrphans(String start) {
    final queue = [start];
    for (var i = 0; i < queue.length; i++) {
      final parent = queue[i],
          children = orphans
              .where((o) => o.block.previous == queue[i])
              .toList();
      for (final o in children) {
        orphans.remove(o);
        if (rejected.contains(parent)) {
          rejectBlock('UNORPHAN', o.block, o.peer, 'bad-parent');
        } else {
          connectBlock('UNORPHAN', o.block, o.peer);
        }
        queue.add(o.block.hash);
      }
    }
  }

  void status(String id) {
    if (confirmed.containsKey(id)) {
      final h = confirmed[id]!;
      log(['STATUS', short(id), 'confirmed', h, 'confirmations', height - h]);
      return;
    }
    final order = priority();
    for (var i = 0; i < order.length; i++) {
      if (order[i].transaction.txid == id) {
        log([
          'STATUS',
          short(id),
          'mempool',
          'rank',
          i + 1,
          'of',
          order.length,
        ]);
        return;
      }
    }
    if (dropped.containsKey(id)) {
      log(['STATUS', short(id), 'dropped', dropped[id]!]);
    } else if (records.values.any((r) => r.block.txids.contains(id))) {
      log(['STATUS', short(id), 'stale']);
    } else {
      log(['STATUS', short(id), 'unknown']);
    }
  }

  void printState() {
    final order = priority();
    log([
      'PRINT',
      'height',
      tip.block.height,
      'tip',
      short(tip.block.hash),
      'work',
      tip.work,
      'bits',
      difficulty(tip),
      'reward',
      blockReward(height),
      'mempool',
      order.length,
      'size',
      order.fold(0, (sum, e) => sum + e.transaction.size),
      'orphans',
      orphans.length,
    ]);
    for (var i = 0; i < order.length; i++) {
      final e = order[i];
      log([
        'MEMPOOL',
        i + 1,
        short(e.transaction.txid),
        'fee',
        e.fee,
        'size',
        e.transaction.size,
      ]);
    }
    for (final w in wallets) {
      log(['BALANCE', w.name, balance(w.address)]);
    }
  }

  String miner(BlockRecord r) =>
      owners[r.block.transactions.first.outputs.first.$1]!.name;
  List<String> chainLines() {
    final lines = [
      line([
        'TIP',
        tip.block.height,
        tip.block.hash,
        'work',
        tip.work,
        'stored',
        records.length,
        'orphans',
        orphans.length,
      ]),
    ];
    for (final r in mainChain) {
      final b = r.block;
      lines.add(
        line([
          'BLOCK',
          b.height,
          b.hash,
          'prev',
          short(b.previous),
          'time',
          b.timestamp,
          'bits',
          b.difficulty,
          'nonce',
          b.nonce,
          'txs',
          b.transactions.length,
          'size',
          b.size,
          'fees',
          r.fees,
          'miner',
          b.height == 0 ? '-' : miner(r),
          'source',
          r.source,
          'work',
          r.work,
        ]),
      );
      for (var i = 0; i < b.transactions.length; i++) {
        final t = b.transactions[i];
        lines.add(
          t.coinbase
              ? line([
                  'TX',
                  i + 1,
                  t.txid,
                  category(true, b.height),
                  'out',
                  t.outputs.length,
                  'amount',
                  t.outputTotal,
                ])
              : line([
                  'TX',
                  i + 1,
                  t.txid,
                  'payment',
                  'in',
                  t.inputs.length,
                  'out',
                  t.outputs.length,
                  'size',
                  t.size,
                  'fee',
                  r.transactionFees[i - 1],
                ]),
        );
      }
    }
    final main = mainChain.map((r) => r.block.hash).toSet();
    final stale =
        records.values.where((r) => !main.contains(r.block.hash)).toList()
          ..sort((a, b) {
            final order = a.block.height.compareTo(b.block.height);
            return order != 0 ? order : a.block.hash.compareTo(b.block.hash);
          });
    for (final r in stale) {
      lines.add(
        line([
          'STALE',
          r.block.height,
          r.block.hash,
          'prev',
          short(r.block.previous),
          'source',
          r.source,
          'work',
          r.work,
        ]),
      );
    }
    for (final o in orphans) {
      lines.add(
        line([
          'ORPHAN',
          o.block.height,
          o.block.hash,
          'prev',
          short(o.block.previous),
          'source',
          o.peer.name,
        ]),
      );
    }
    for (final r in reorganizations) {
      lines.add(
        line([
          'REORG',
          r.time,
          'fork',
          r.fork,
          'disconnected',
          r.disconnected,
          'connected',
          r.connected,
          'old',
          short(r.old),
          'new',
          short(r.next),
        ]),
      );
    }
    final mined = mainChain.skip(1).toList();
    for (final w in wallets) {
      final own = mined.where((r) => miner(r) == w.name).toList();
      if (own.isNotEmpty)
        lines.add(
          line([
            'MINER',
            w.name,
            'blocks',
            own.length,
            'coinbase',
            own.fold(
              0,
              (sum, r) => sum + r.block.transactions.first.outputTotal,
            ),
            'fees',
            own.fold(0, (sum, r) => sum + r.fees),
          ]),
        );
    }
    for (var i = 0; i < mined.length;) {
      var j = i;
      while (j + 1 < mined.length &&
          mined[j + 1].block.difficulty == mined[i].block.difficulty) {
        j++;
      }
      lines.add(
        line([
          'BITS',
          mined[i].block.difficulty,
          'heights',
          '${mined[i].block.height}-${mined[j].block.height}',
          'blocks',
          j - i + 1,
        ]),
      );
      i = j + 1;
    }
    for (final name in peers.keys.toList()..sort()) {
      final p = peers[name]!;
      lines.add(
        line([
          'PEER',
          name,
          'blocks',
          p.acceptedBlocks,
          'rejected',
          p.rejectedBlocks,
          'orphans',
          p.orphans,
          'txs',
          p.acceptedTxs,
          'rejected',
          p.rejectedTxs,
          'ignored',
          p.ignored,
          'score',
          p.score,
          p.score >= settings.ban ? 'banned' : 'ok',
        ]),
      );
    }
    final order = priority();
    for (var i = 0; i < order.length; i++) {
      final e = order[i];
      lines.add(
        line([
          'MEMPOOL',
          i + 1,
          e.transaction.txid,
          'fee',
          e.fee,
          'size',
          e.transaction.size,
          'time',
          e.arrival,
        ]),
      );
    }
    for (final key in rejections.keys.toList()..sort()) {
      lines.add('REJECT $key ${rejections[key]}');
    }
    final rewards = mined.fold(
      0,
      (sum, r) => sum + blockReward(r.block.height),
    );
    final fees = mined.fold(0, (sum, r) => sum + r.fees),
        minted = mined.fold(
          0,
          (sum, r) => sum + r.block.transactions.first.outputTotal,
        );
    lines.add(
      line([
        'SUPPLY',
        'genesis',
        mainChain.first.block.transactions.first.outputTotal,
        'rewards',
        rewards,
        'fees',
        fees,
        'burned',
        rewards + fees - minted,
        'utxo',
        tip.utxo.values.fold(0, (sum, c) => sum + c.amount),
      ]),
    );
    return lines;
  }

  List<String> balanceLines() {
    final lines = ['wallet,address,balance,immature,locked,incoming,utxos'],
        lockedRefs = locked();
    for (final w in wallets) {
      var balance = 0, immature = 0, amount = 0, incoming = 0, count = 0;
      for (final entry in tip.utxo.entries) {
        final c = entry.value;
        if (c.address == w.address) {
          balance += c.amount;
          count++;
          if (!mature(c)) immature += c.amount;
          if (lockedRefs.contains(entry.key)) amount += c.amount;
        }
      }
      for (final e in mempool) {
        for (final out in e.transaction.outputs) {
          if (out.$1 == w.address) incoming += out.$2;
        }
      }
      lines.add(
        '${w.name},${w.address},$balance,$immature,$amount,$incoming,$count',
      );
    }
    return lines;
  }

  List<String> utxoLines() {
    final refs = tip.utxo.keys.toList()..sort(compareReferences),
        lockedRefs = locked(),
        lines = <String>[];
    var total = 0;
    for (final ref in refs) {
      final c = tip.utxo[ref]!;
      final state = !mature(c)
          ? 'immature'
          : lockedRefs.contains(ref)
          ? 'locked'
          : 'free';
      lines.add(
        line([
          referenceText(ref),
          owners[c.address]!.name,
          c.amount,
          'height',
          c.height,
          category(c.coinbase, c.height),
          state,
        ]),
      );
      total += c.amount;
    }
    final root = merkleRoot(lines.map(digest));
    return [...lines, 'TOTAL ${refs.length} $total', 'ROOT $root'];
  }

  List<String> historyLines() {
    final transactions = {
          for (final r in mainChain)
            for (final t in r.block.transactions) t.txid: t,
        },
        lines = <String>[];
    for (final w in wallets) {
      lines.add('WALLET ${w.name} ${w.address}');
      var count = 0,
          spentTotal = 0,
          receivedTotal = 0,
          balance = 0,
          pending = 0;
      for (final r in mainChain) {
        for (final t in r.block.transactions) {
          var spent = 0, received = 0, involved = false;
          for (final ref in t.inputs) {
            final out = transactions[ref.$1]!.outputs[ref.$2];
            if (out.$1 == w.address) {
              spent += out.$2;
              involved = true;
            }
          }
          for (final out in t.outputs) {
            if (out.$1 == w.address) {
              received += out.$2;
              involved = true;
            }
          }
          if (involved) {
            count++;
            spentTotal += spent;
            receivedTotal += received;
            balance += received - spent;
            lines.add(
              line([
                r.block.height,
                short(t.txid),
                category(t.coinbase, r.block.height),
                'spent',
                spent,
                'received',
                received,
                'net',
                signed(received - spent),
                'balance',
                balance,
              ]),
            );
          }
        }
      }
      for (final e in priority()) {
        var spent = 0, received = 0;
        for (final ref in e.transaction.inputs) {
          final c = tip.utxo[ref]!;
          if (c.address == w.address) spent += c.amount;
        }
        for (final out in e.transaction.outputs) {
          if (out.$1 == w.address) received += out.$2;
        }
        if (spent != 0 || received != 0) {
          pending++;
          lines.add(
            line([
              'pending',
              short(e.transaction.txid),
              'spent',
              spent,
              'received',
              received,
              'net',
              signed(received - spent),
            ]),
          );
        }
      }
      lines.add(
        line([
          'END',
          w.name,
          'txs',
          count,
          'spent',
          spentTotal,
          'received',
          receivedTotal,
          'balance',
          balance,
          'pending',
          pending,
        ]),
      );
    }
    return lines;
  }
}

String category(bool coinbase, int height) => height == 0
    ? 'genesis'
    : coinbase
    ? 'coinbase'
    : 'payment';
void main() {
  final node = Node(Settings(), readWallets()),
      events = readLines('input/events.txt');
  for (var i = 0; i < events.length; i++) {
    final f = events[i].split(' '),
        count = events[i].split(' ')[1] == 'BLOCK'
            ? int.parse(events[i].split(' ')[9])
            : 0;
    node.process(f, events.sublist(i + 1, i + 1 + count));
    i += count;
  }
  Directory('output').createSync(recursive: true);
  writeLines('log.txt', node.logs);
  writeLines('chain.txt', node.chainLines());
  writeLines('balances.csv', node.balanceLines());
  writeLines('utxo.txt', node.utxoLines());
  writeLines('history.txt', node.historyLines());
}
