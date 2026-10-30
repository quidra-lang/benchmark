import 'dart:io';
import 'dart:math';
part 'bids_io.dart';
part 'wdp_solver.dart';
part 'payments.dart';
part 'auctions.dart';
part 'report.dart';

class Bidder {
  final String name, language;
  final List<Bid> valid = [], eligible = [];
  Bidder(this.name, this.language);
}

class Rejection {
  final int number;
  final String name, message;
  Rejection(this.number, this.name, this.message);
}

class Auction {
  final String name;
  int offered = 0, total = 0;
  final List<Bidder> bidders = [];
  final List<Bid> valid = [], eligible = [];
  final List<Rejection> rejected = [];
  Auction(this.name);
}

final bidForm = RegExp(r'^[a-z]+(?:\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})$');
final ctrForm = RegExp(r'^[1-9][0-9]*/[1-9][0-9]*$');
int reserve(List<Item> items, int mask) {
  var sum = 0;
  for (var i = 0; i < items.length; i++) {
    if (mask & (1 << i) != 0) sum += items[i].reserve;
  }
  return sum;
}

Auction validate(Input input, RawAuction raw) {
  final a = Auction(raw.name),
      indices = {
        for (var i = 0; i < input.items.length; i++) input.items[i].name: i,
      };
  for (final name in raw.offered) {
    a.offered |= 1 << indices[name]!;
  }
  final seen = <String>{};
  for (final line in raw.lines) {
    var lineError = '';
    if (seen.contains(line.name)) {
      lineError = 'duplicate bidder';
    } else if (line.language != 'XOR' && line.language != 'OR') {
      lineError = 'bad language ${line.language}';
    }
    seen.add(line.name);
    if (lineError.isNotEmpty) {
      for (final _ in line.raw) {
        a.total++;
        a.rejected.add(Rejection(a.total, line.name, lineError));
      }
      continue;
    }
    final k = a.bidders.length,
        bidder = Bidder(line.name, line.language),
        bundles = <int, int>{};
    a.bidders.add(bidder);
    for (final text in line.raw) {
      a.total++;
      var message = '', mask = 0, amount = 0, size = 0;
      if (!bidForm.hasMatch(text)) {
        message = 'malformed bid';
      } else {
        final v = text.split(':'), names = v[0].split('+');
        amount = int.parse(v[1]);
        size = names.length;
        for (final name in names) {
          final i = indices[name];
          if (i == null) {
            message = 'unknown item $name';
            break;
          }
          if (a.offered & (1 << i) == 0) {
            message = 'item not offered $name';
            break;
          }
          if (mask & (1 << i) != 0) {
            message = 'duplicate item $name';
            break;
          }
          mask |= 1 << i;
        }
        if (message.isEmpty) {
          if (size > input.parameters['max_bundle_size']!) {
            message = 'bundle too large';
          } else if (amount == 0) {
            message = 'zero value';
          } else if (bundles.containsKey(mask)) {
            message = 'duplicate bundle ${bundles[mask]}';
          } else if (bidder.valid.length >=
              input.parameters['max_bids_per_bidder']!) {
            message = 'too many bids';
          }
        }
      }
      if (message.isNotEmpty) {
        a.rejected.add(Rejection(a.total, line.name, message));
        continue;
      }
      final b = Bid(
        a.total,
        k,
        mask,
        size,
        amount,
        reserve(input.items, mask),
        line.language == 'XOR',
      );
      bundles[mask] = b.number;
      a.valid.add(b);
      bidder.valid.add(b);
      if (amount >= b.reserve) {
        a.eligible.add(b);
        bidder.eligible.add(b);
      }
    }
  }
  return a;
}

(int, int, int) allocation(List<Item> items, int offered, List<Bid> bids) {
  var accepted = 0, used = 0;
  for (final b in bids) {
    accepted += b.amount;
    used |= b.mask;
  }
  final unsold = offered & ~used;
  return (accepted, reserve(items, unsold), unsold);
}

List<Bid> sortedBids(List<Bid> bids) =>
    List<Bid>.of(bids)..sort((a, b) => a.number.compareTo(b.number));
String unsoldText(List<Item> items, int mask) =>
    bundle(items, mask).replaceAll('+', ' ');
List<String> wdpLines(
  Input input,
  Auction a,
  SearchResult r,
  List<Bid> order,
  List<Bid> greedy,
  Map<int, Critical> critical,
) {
  final out = [
    'AUCTION ${a.name} items ${popcount(a.offered)} bidders ${a.bidders.length} bids ${a.total} valid ${a.valid.length} eligible ${a.eligible.length}',
  ];
  for (final b in a.bidders) {
    out.add(
      'BIDDER ${b.name} ${b.language} valid ${b.valid.length} eligible ${b.eligible.length}',
    );
  }
  for (final e in a.rejected) {
    out.add('REJECT ${e.number} ${e.name} ${e.message}');
  }
  for (final b in a.valid) {
    if (b.amount < b.reserve)
      out.add(
        'BELOW_RESERVE ${b.number} ${a.bidders[b.bidder].name} value ${b.amount} reserve ${b.reserve}',
      );
  }
  for (var i = 0; i < input.items.length; i++) {
    if (a.offered & (1 << i) == 0) continue;
    final source = r.sources[i] > 0 ? 'bid ${r.sources[i]}' : 'reserve';
    out.add('SHARE ${input.items[i].name} ${r.shares[i]} $source');
  }
  out.add('ROOT_BOUND ${r.bound}');
  for (final record in r.records) {
    out.add(
      'IMPROVE ${record.node} welfare ${record.welfare} bids ${numberList(record.bids)}',
    );
  }
  final (accepted, retained, unsold) = allocation(
    input.items,
    a.offered,
    r.bids,
  );
  out.add(
    'OPTIMAL welfare ${r.welfare} accepted $accepted retained $retained winners ${r.bids.length}',
  );
  for (final b in r.bids) {
    out.add(
      'WIN ${b.number} ${a.bidders[b.bidder].name} ${bundle(input.items, b.mask)} ${b.amount}',
    );
  }
  out.addAll([
    'UNSOLD ${unsoldText(input.items, unsold)}',
    'SEARCH nodes ${r.nodes} pruned ${r.pruned} leaves ${r.leaves} improvements ${r.improvements}',
    'GREEDY_ORDER ${order.isEmpty ? '-' : order.map((b) => b.number).join(' ')}',
  ]);
  final (ga, gr, gu) = allocation(input.items, a.offered, greedy);
  out.add(
    'GREEDY welfare ${ga + gr} accepted $ga retained $gr winners ${greedy.length} efficiency ${fraction(ga + gr, r.welfare)}',
  );
  for (final b in sortedBids(greedy)) {
    final c = critical[b.number]!, against = c.rival > 0 ? '${c.rival}' : '-';
    out.add(
      'GWIN ${b.number} ${a.bidders[b.bidder].name} ${bundle(input.items, b.mask)} ${b.amount} critical ${c.payment} against $against',
    );
  }
  out.add('GUNSOLD ${unsoldText(input.items, gu)}');
  for (var i = 0; i < input.items.length; i++) {
    if (a.offered & (1 << i) == 0) continue;
    var demand = 0, optimalName = '-', greedyName = '-';
    for (final b in a.eligible) {
      if (b.mask & (1 << i) != 0) demand++;
    }
    for (final b in r.bids) {
      if (b.mask & (1 << i) != 0) optimalName = a.bidders[b.bidder].name;
    }
    for (final b in greedy) {
      if (b.mask & (1 << i) != 0) greedyName = a.bidders[b.bidder].name;
    }
    out.add(
      'ITEM ${input.items[i].name} reserve ${input.items[i].reserve} demand $demand optimal $optimalName greedy $greedyName',
    );
  }
  return out;
}

class AscendingResult {
  final List<String> lines = [];
  final List<int> payment, value, utility;
  int revenue = 0,
      welfare = 0,
      retained = 0,
      exposure = 0,
      exposed = 0,
      rounds = 0;
  String reason = '';
  AscendingResult(int n)
    : payment = List.filled(n, 0),
      value = List.filled(n, 0),
      utility = List.filled(n, 0);
}

AscendingResult ascending(Input input, Auction a, int optimum) {
  final n = a.bidders.length,
      m = input.items.length,
      result = AscendingResult(a.bidders.length),
      candidatesByBidder = List.generate(
        a.bidders.length,
        (_) => <Candidate>[],
      ),
      eligibility = List.filled(a.bidders.length, 0),
      prices = [for (final item in input.items) item.reserve],
      holder = List.filled(input.items.length, -1),
      bidCounts = List.filled(input.items.length, 0),
      roundCounts = List.filled(input.items.length, 0),
      lastRound = List.filled(input.items.length, 0);
  for (var k = 0; k < n; k++) {
    final b = a.bidders[k];
    candidatesByBidder[k] = candidates(b.valid, b.language == 'XOR');
    for (final c in candidatesByBidder[k]) {
      eligibility[k] = max(eligibility[k], popcount(c.mask));
    }
  }
  final increment = input.parameters['saa_increment']!;
  var state = input.parameters['seed']!;
  result.lines.add('AUCTION ${a.name} increment $increment');
  for (var round = 1; ; round++) {
    final newBids = List.filled(n, 0), activity = List.filled(n, 0);
    var demand = 0;
    for (var k = 0; k < n; k++) {
      var held = 0;
      for (var j = 0; j < m; j++) {
        if (holder[j] == k) held |= 1 << j;
      }
      var chosen = 0, best = 0;
      for (final c in candidatesByBidder[k]) {
        if (popcount(c.mask | held) > eligibility[k]) continue;
        var cost = 0;
        for (var j = 0; j < m; j++) {
          if (c.mask & (1 << j) != 0) {
            cost += prices[j];
            if (holder[j] >= 0 && holder[j] != k) cost += increment;
          }
        }
        final surplus = c.value - cost;
        if (surplus > best) {
          best = surplus;
          chosen = c.mask;
        }
      }
      activity[k] = popcount(chosen | held);
      newBids[k] = chosen & ~held;
      demand += popcount(newBids[k]);
    }
    if (demand == 0) {
      result.lines.add('ROUND $round none');
    } else {
      var line = 'ROUND $round demand $demand';
      for (var k = 0; k < n; k++) {
        if (newBids[k] != 0)
          line += ' ${a.bidders[k].name}:${bundle(input.items, newBids[k])}';
      }
      result.lines.add(line);
      for (var j = 0; j < m; j++) {
        if (a.offered & (1 << j) == 0) continue;
        final bidders = [
          for (var k = 0; k < n; k++)
            if (newBids[k] & (1 << j) != 0) k,
        ];
        if (bidders.isEmpty) continue;
        bidCounts[j] += bidders.length;
        roundCounts[j]++;
        lastRound[j] = round;
        var q = 0;
        if (bidders.length > 1) {
          state = 48271 * state % 2147483647;
          q = state % bidders.length;
        }
        if (holder[j] >= 0) prices[j] += increment;
        holder[j] = bidders[q];
      }
      line = 'STANDING';
      for (var j = 0; j < m; j++) {
        if (a.offered & (1 << j) == 0) continue;
        final name = holder[j] >= 0 ? a.bidders[holder[j]].name : '-';
        line += ' ${input.items[j].name}=${prices[j]}@$name';
      }
      result.lines.add(line);
    }
    var changes = '';
    for (var k = 0; k < n; k++) {
      if (activity[k] < eligibility[k]) {
        eligibility[k] = activity[k];
        changes += ' ${a.bidders[k].name}=${eligibility[k]}';
      }
    }
    if (changes.isNotEmpty) result.lines.add('ELIGIBILITY$changes');
    if (demand == 0 || round == input.parameters['round_cap']) {
      result.rounds = round;
      result.reason = demand == 0 ? 'quiet' : 'cap';
      break;
    }
  }
  result.lines.add('END rounds ${result.rounds} ${result.reason}');
  final won = List.filled(n, 0);
  for (var j = 0; j < m; j++) {
    if (a.offered & (1 << j) == 0) continue;
    final item = input.items[j];
    if (holder[j] < 0) {
      result.retained += item.reserve;
      result.lines.add('ITEM ${item.name} unsold reserve ${item.reserve}');
    } else {
      final k = holder[j];
      won[k] |= 1 << j;
      result.payment[k] += prices[j];
      result.revenue += prices[j];
      result.lines.add(
        'ITEM ${item.name} price ${prices[j]} holder ${a.bidders[k].name} bids ${bidCounts[j]} rounds ${roundCounts[j]} last ${lastRound[j]}',
      );
    }
  }
  result.welfare = result.retained;
  for (var k = 0; k < n; k++) {
    result.value[k] = candidateValue(candidatesByBidder[k], won[k]);
    result.utility[k] = result.value[k] - result.payment[k];
    result.welfare += result.value[k];
    var text =
        'BIDDER ${a.bidders[k].name} won ${bundle(input.items, won[k])} paid ${result.payment[k]} value ${result.value[k]} utility ${result.utility[k]} eligibility ${eligibility[k]}';
    if (result.utility[k] < 0) {
      result.exposed++;
      result.exposure -= result.utility[k];
      text += ' exposed';
    }
    result.lines.add(text);
  }
  result.lines.add(
    'TOTAL revenue ${result.revenue} welfare ${result.welfare} efficiency ${fraction(result.welfare, optimum)} exposure ${result.exposure} exposed ${result.exposed}',
  );
  return result;
}

String coalitionName(Auction a, Coalition c) =>
    c.members.isEmpty ? '-' : c.members.map((i) => a.bidders[i].name).join('+');

class Laboratory {
  final Input input;
  final List<String> wdp = [],
      vcg = [],
      core = [],
      ascendingLines = [],
      single = [],
      summary = ['mechanism,revenue,welfare,efficiency'];
  int bidTotal = 0,
      validTotal = 0,
      eligibleTotal = 0,
      nodeTotal = 0,
      greedyOptimal = 0,
      checked = 0,
      skipped = 0,
      roundTotal = 0,
      capped = 0,
      exposed = 0,
      exposure = 0,
      lots = 0,
      slotGroups = 0,
      errors = 0,
      envyFree = 0,
      nash = 0,
      equilibria = 0;
  final List<int> coreCounts = [0, 0, 0, 0], revenueTotals = [0, 0, 0, 0, 0];
  Laboratory(this.input);
  void summaryRow(
    String name,
    String format,
    Fraction revenue,
    Fraction welfare,
    Fraction efficiency,
  ) => summary.add('$name/$format,$revenue,$welfare,$efficiency');
  void processAuction(Auction a) {
    final opt = solveWDP(input.items, a.offered, a.eligible),
        order = greedyOrder(a.eligible);
    final greedy = greedySelect(order, 0),
        critical = criticalPayments(order, greedy),
        payments = vcgPayments(
          input.items,
          a.offered,
          a.bidders.length,
          a.eligible,
          opt.bids,
          opt.welfare,
        ),
        saa = ascending(input, a, opt.welfare);
    final (accepted, retained, _) = allocation(
      input.items,
      a.offered,
      opt.bids,
    );
    final (ga, gr, _) = allocation(input.items, a.offered, greedy);
    final gw = ga + gr,
        n = a.bidders.length,
        vcgPay = List.filled(a.bidders.length, 0),
        vcgUtility = List.filled(a.bidders.length, 0),
        greedyPay = List.filled(a.bidders.length, 0),
        critPay = List.filled(a.bidders.length, 0),
        critUtility = List.filled(a.bidders.length, 0);
    var vcgRevenue = 0, critRevenue = 0, utilitySum = 0;
    for (var k = 0; k < n; k++) {
      final v = payments[k];
      vcgPay[k] = v.payment;
      vcgUtility[k] = v.utility;
      vcgRevenue += v.payment;
      utilitySum += v.utility;
    }
    for (final b in greedy) {
      greedyPay[b.bidder] += b.amount;
      critPay[b.bidder] += critical[b.number]!.payment;
      critUtility[b.bidder] += b.amount - critical[b.number]!.payment;
      critRevenue += critical[b.number]!.payment;
    }
    wdp.addAll(wdpLines(input, a, opt, order, greedy, critical));
    bidTotal += a.total;
    validTotal += a.valid.length;
    eligibleTotal += a.eligible.length;
    nodeTotal += opt.nodes;
    if (gw == opt.welfare) greedyOptimal++;
    vcg.add('AUCTION ${a.name} welfare ${opt.welfare}');
    for (var k = 0; k < n; k++) {
      final b = a.bidders[k], v = payments[k];
      vcg.add(
        v.won.isEmpty
            ? 'BIDDER ${b.name} lost'
            : 'BIDDER ${b.name} won ${numberList(v.won)} value ${v.value} without ${v.without} alternative ${numberList(v.alternative)} payment ${v.payment} utility ${v.utility}',
      );
    }
    vcg.add(
      'TOTAL revenue $vcgRevenue pay_as_bid $accepted retained $retained seller ${vcgRevenue + retained} bidders $utilitySum',
    );
    for (var k = 0; k < n; k++) {
      vcg.add(
        'PAYMENTS ${a.bidders[k].name} vcg ${vcgPay[k]} pay_as_bid ${payments[k].value} greedy ${greedyPay[k]} critical ${critPay[k]} saa ${saa.payment[k]}',
      );
    }
    for (var k = 0; k < n; k++) {
      vcg.add(
        'UTILITIES ${a.bidders[k].name} vcg ${vcgUtility[k]} critical ${critUtility[k]} saa ${saa.utility[k]}',
      );
    }
    core.add('AUCTION ${a.name} bidders $n');
    if (n > input.parameters['core_max_bidders']!) {
      skipped++;
      core.add('SKIPPED');
    } else {
      checked++;
      final cs = coalitions(input.items, a.offered, n, a.eligible),
          names = ['vcg', 'greedy', 'critical', 'saa'],
          sellers = [
            vcgRevenue + retained,
            gw,
            critRevenue + gr,
            saa.revenue + saa.retained,
          ],
          utilities = [vcgUtility, List.filled(n, 0), critUtility, saa.utility];
      core.add('COALITIONS ${cs.length}');
      for (var i = 0; i < 4; i++) {
        core.add(
          'OUTCOME ${names[i]} seller ${sellers[i]} utilities ${utilities[i].join(' ')}',
        );
        final blocked = blockers(cs, sellers[i], utilities[i]);
        var minimal = 0;
        for (final b in blocked) {
          if (b.minimal) {
            minimal++;
            core.add(
              'BLOCK ${coalitionName(a, b.coalition)} welfare ${b.coalition.welfare} payoff ${b.payoff} deficit ${b.deficit} bids ${numberList(b.coalition.bids)}',
            );
          }
        }
        if (blocked.isEmpty) {
          coreCounts[i]++;
          core.add('RESULT core');
        } else {
          var best = blocked.first;
          for (final b in blocked.skip(1)) {
            if (b.deficit > best.deficit) best = b;
          }
          core.add(
            'RESULT blocked ${blocked.length} minimal $minimal max_deficit ${best.deficit} by ${coalitionName(a, best.coalition)}',
          );
        }
      }
    }
    ascendingLines.addAll(saa.lines);
    roundTotal += saa.rounds;
    if (saa.reason == 'cap') capped++;
    exposed += saa.exposed;
    exposure += saa.exposure;
    final revenues = [vcgRevenue, accepted, ga, critRevenue, saa.revenue],
        welfares = [opt.welfare, opt.welfare, gw, gw, saa.welfare],
        formats = ['vcg', 'pay_as_bid', 'greedy', 'critical', 'saa'];
    for (var i = 0; i < 5; i++) {
      revenueTotals[i] += revenues[i];
      summaryRow(
        a.name,
        formats[i],
        whole(revenues[i]),
        whole(welfares[i]),
        fraction(welfares[i], opt.welfare),
      );
    }
  }

  void processLot(Group g) {
    lots++;
    final message = lotError(g);
    if (message.isNotEmpty) {
      errors++;
      single.add('LOT ${g.name} ERROR $message');
      return;
    }
    final participants = g.participants,
        n = g.participants.length,
        reserve = int.parse(g.arguments[0]);
    var efficient = 0;
    for (var i = 0; i < n; i++) {
      if (participants[i].value > participants[efficient].value) efficient = i;
    }
    final optimum = max(reserve, participants[efficient].value),
        efficientName = participants[efficient].value >= reserve
            ? participants[efficient].name
            : '-';
    single.add(
      'LOT ${g.name} reserve $reserve bidders $n efficient $efficientName optimum $optimum',
    );
    var first = -1;
    for (var i = 0; i < n; i++) {
      final p = participants[i];
      if (p.bid >= reserve && (first < 0 || p.bid > participants[first].bid))
        first = i;
    }
    var second = -1, secondPrice = reserve;
    if (participants[efficient].value >= reserve) {
      second = efficient;
      for (var i = 0; i < n; i++) {
        if (i != second && participants[i].value >= reserve)
          secondPrice = max(secondPrice, participants[i].value);
      }
    }
    final eng = english(
          participants,
          reserve,
          input.parameters['english_increment']!,
        ),
        dut = dutch(
          participants,
          reserve,
          input.parameters['dutch_start']!,
          input.parameters['dutch_decrement']!,
        ),
        winners = [first, second, eng.winner, dut.winner, first],
        firstPrice = first >= 0 ? participants[first].bid : 0,
        results = <LotResult>[],
        labels = ['FIRST_PRICE', 'SECOND_PRICE', 'ENGLISH', 'DUTCH', 'ALL_PAY'],
        formats = [
          'first_price',
          'second_price',
          'english',
          'dutch',
          'all_pay',
        ];
    final prices = [firstPrice, secondPrice, eng.price, dut.price, firstPrice];
    for (var j = 0; j < 5; j++) {
      final r = LotResult(winners[j], prices[j], reserve, n);
      if (j == 2) r.steps = eng.steps;
      if (j == 3) r.steps = dut.steps;
      if (r.winner >= 0) {
        r.revenue = r.price;
        r.welfare = participants[r.winner].value;
        r.utilities[r.winner] = r.welfare - r.price;
      }
      if (j == 4) {
        r.revenue = 0;
        for (var i = 0; i < n; i++) {
          final p = participants[i];
          if (p.bid >= reserve) {
            r.revenue += p.bid;
            if (i != r.winner) r.utilities[i] = -p.bid;
          }
        }
      }
      var text = labels[j];
      if (r.winner >= 0) {
        text +=
            ' winner ${participants[r.winner].name} price ${r.price} utility ${r.utilities[r.winner]}';
      } else {
        text += ' unsold';
      }
      if (j == 2 || j == 3) text += ' steps ${r.steps}';
      text +=
          ' revenue ${r.revenue} welfare ${r.welfare} efficiency ${fraction(r.welfare, optimum)}';
      single.add(text);
      if (j == 2) {
        var line = 'ENGLISH_DROPS';
        for (var i = 0; i < n; i++) {
          line +=
              ' ${participants[i].name}=${eng.drops[i] >= 0 ? '${eng.drops[i]}' : '-'}';
        }
        single.add(line);
      }
      summaryRow(
        g.name,
        formats[j],
        whole(r.revenue),
        whole(r.welfare),
        fraction(r.welfare, optimum),
      );
      results.add(r);
    }
    for (var i = 0; i < n; i++) {
      single.add(
        'UTILITY ${participants[i].name} ${results.map((r) => r.utilities[i]).join(' ')}',
      );
    }
    final ranking = [0, 1, 2, 3, 4]
      ..sort((a, b) {
        final c = results[b].revenue.compareTo(results[a].revenue);
        return c != 0 ? c : a.compareTo(b);
      });
    single.add('RANKING ${ranking.map((i) => formats[i]).join(' ')}');
  }

  void processSlots(Group g) {
    slotGroups++;
    final (ctr, message) = slotValidation(g);
    if (message.isNotEmpty) {
      errors++;
      single.add('SLOTS ${g.name} ERROR $message');
      return;
    }
    final participants = g.participants,
        n = g.participants.length,
        k = ctr.length,
        gsp = List.generate(g.participants.length, (i) => i),
        vcg = List.generate(g.participants.length, (i) => i);
    gsp.sort((a, b) {
      final c = participants[b].bid.compareTo(participants[a].bid);
      return c != 0 ? c : a.compareTo(b);
    });
    vcg.sort((a, b) {
      final c = participants[b].value.compareTo(participants[a].value);
      return c != 0 ? c : a.compareTo(b);
    });
    Fraction rate(int rank) => rank >= k ? whole(0) : ctr[rank];
    int bid(int rank) => rank >= n ? 0 : participants[gsp[rank]].bid;
    single.add('SLOTS ${g.name} slots $k advertisers $n');
    var gspRevenue = whole(0),
        gspWelfare = whole(0),
        vcgRevenue = whole(0),
        optimum = whole(0);
    for (var s = 0; s < min(n, k); s++) {
      final p = participants[gsp[s]],
          price = gspPrice(participants, gsp, s),
          payment = ctr[s].mul(whole(price)),
          utility = ctr[s].mul(whole(p.value - price));
      gspRevenue = gspRevenue.add(payment);
      gspWelfare = gspWelfare.add(ctr[s].mul(whole(p.value)));
      optimum = optimum.add(ctr[s].mul(whole(participants[vcg[s]].value)));
      single.add(
        'GSP ${s + 1} ${p.name} ctr ${ctr[s]} bid ${p.bid} price $price payment $payment utility $utility',
      );
    }
    single.add(
      'GSP_TOTAL revenue $gspRevenue welfare $gspWelfare efficiency ${gspWelfare.div(optimum)}',
    );
    for (var s = 0; s < min(n, k); s++) {
      final p = participants[vcg[s]],
          payment = slotVCG(participants, vcg, ctr, s),
          utility = ctr[s].mul(whole(p.value)).sub(payment);
      vcgRevenue = vcgRevenue.add(payment);
      single.add(
        'VCG ${s + 1} ${p.name} ctr ${ctr[s]} value ${p.value} payment $payment price ${payment.div(ctr[s])} utility $utility',
      );
    }
    single.add('VCG_TOTAL revenue $vcgRevenue welfare $optimum efficiency 1');
    var violations = 0;
    for (var s = 1; s < min(n, k + 1); s++) {
      final p = participants[gsp[s]],
          stay = rate(s).mul(whole(p.value - bid(s + 1))),
          swap = rate(s - 1).mul(whole(p.value - bid(s)));
      var judgment = 'ok';
      if (stay.compare(swap) < 0) {
        judgment = 'violated';
        violations++;
      }
      single.add('ENVY ${s + 1} ${p.name} stay $stay swap $swap $judgment');
    }
    if (violations == 0) {
      envyFree++;
      single.add('ENVY_FREE yes');
    } else {
      single.add('ENVY_FREE no violations $violations');
    }
    var deviations = 0;
    for (var s = 0; s < n; s++) {
      final p = participants[gsp[s]],
          current = rate(s).mul(whole(p.value - bid(s + 1)));
      for (var t = 0; t < k; t++) {
        if (t == s) continue;
        final price = t < s ? bid(t) : bid(t + 1),
            payoff = rate(t).mul(whole(p.value - price));
        if (payoff.compare(current) > 0) {
          deviations++;
          single.add(
            'DEVIATE ${p.name} from ${s + 1} to ${t + 1} gain ${payoff.sub(current)}',
          );
        }
      }
    }
    if (deviations == 0) {
      nash++;
      single.add('NASH yes');
    } else {
      single.add('NASH no deviations $deviations');
    }
    if (deviations == 0 && violations == 0) {
      equilibria++;
      single.add('EQUILIBRIUM yes');
    } else {
      single.add('EQUILIBRIUM no');
    }
    summaryRow(g.name, 'gsp', gspRevenue, gspWelfare, gspWelfare.div(optimum));
    summaryRow(g.name, 'vcg', vcgRevenue, optimum, whole(1));
  }
}

class LotResult {
  final int winner, price;
  int steps = 0, revenue = 0, welfare;
  final List<int> utilities;
  LotResult(this.winner, this.price, this.welfare, int n)
    : utilities = List.filled(n, 0);
}

String lotError(Group g) {
  if (g.participants.isEmpty) return 'no bidders';
  final seen = <String>{};
  for (final p in g.participants) {
    if (!seen.add(p.name)) return 'duplicate bidder ${p.name}';
  }
  for (final p in g.participants) {
    if (p.bid > p.value) return 'bid above value ${p.name}';
  }
  return '';
}

(List<Fraction>, String) slotValidation(Group g) {
  final ctr = <Fraction>[];
  for (final text in g.arguments) {
    if (!ctrForm.hasMatch(text)) return ([], 'bad ctr $text');
    final a = text.split('/'),
        value = fraction(int.parse(a[0]), int.parse(a[1]));
    if (value.compare(whole(1)) > 0 ||
        (ctr.isNotEmpty && value.compare(ctr.last) >= 0))
      return ([], 'bad ctr $text');
    ctr.add(value);
  }
  if (g.participants.isEmpty) return ([], 'no advertisers');
  final seen = <String>{};
  for (final p in g.participants) {
    if (!seen.add(p.name)) return ([], 'duplicate advertiser ${p.name}');
  }
  return (ctr, '');
}

void main() {
  final input = readInput(), l = Laboratory(input);
  for (final name in input.runs) {
    l.processAuction(validate(input, input.auctions[name]!));
  }
  for (final g in input.groups) {
    if (g.kind == 'lot') {
      l.processLot(g);
    } else {
      l.processSlots(g);
    }
  }
  l.wdp.add(
    'TOTAL auctions ${input.runs.length} bids ${l.bidTotal} valid ${l.validTotal} eligible ${l.eligibleTotal} nodes ${l.nodeTotal} greedy_optimal ${l.greedyOptimal}',
  );
  l.vcg.add(
    'OVERALL vcg ${l.revenueTotals[0]} pay_as_bid ${l.revenueTotals[1]} greedy ${l.revenueTotals[2]} critical ${l.revenueTotals[3]} saa ${l.revenueTotals[4]}',
  );
  l.core.add(
    'SUMMARY checked ${l.checked} skipped ${l.skipped} vcg ${l.coreCounts[0]} greedy ${l.coreCounts[1]} critical ${l.coreCounts[2]} saa ${l.coreCounts[3]}',
  );
  l.ascendingLines.add(
    'SUMMARY auctions ${input.runs.length} rounds ${l.roundTotal} capped ${l.capped} exposed ${l.exposed} exposure ${l.exposure}',
  );
  l.single.add(
    'SUMMARY lots ${l.lots} slot_groups ${l.slotGroups} errors ${l.errors} envy_free ${l.envyFree} nash ${l.nash} equilibria ${l.equilibria}',
  );
  Directory('output').createSync(recursive: true);
  writeLines('wdp.txt', l.wdp);
  writeLines('vcg.txt', l.vcg);
  writeLines('core_check.txt', l.core);
  writeLines('ascending_log.txt', l.ascendingLines);
  writeLines('single_item.txt', l.single);
  writeLines('summary.csv', l.summary);
}
