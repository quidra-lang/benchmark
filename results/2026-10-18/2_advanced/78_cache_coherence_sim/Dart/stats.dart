part of 'main.dart';

const missNames = ['compulsory', 'capacity', 'conflict', 'coherence'],
    serviceNames = ['l1', 'upgrade', 'through', 'cache', 'l2', 'memory'];

class CoreStats {
  int accesses = 0,
      reads = 0,
      writes = 0,
      hits = 0,
      misses = 0,
      fences = 0,
      trueSharing = 0,
      falseSharing = 0,
      invalidationsSent = 0,
      invalidationsReceived = 0,
      supplied = 0,
      backInvalidations = 0,
      latency = 0,
      fenceStall = 0,
      finish = 0;
  final miss = List.filled(4, 0),
      service = List.filled(6, 0),
      bus = List.filled(5, 0);
  void add(CoreStats a) {
    accesses += a.accesses;
    reads += a.reads;
    writes += a.writes;
    hits += a.hits;
    misses += a.misses;
    fences += a.fences;
    trueSharing += a.trueSharing;
    falseSharing += a.falseSharing;
    invalidationsSent += a.invalidationsSent;
    invalidationsReceived += a.invalidationsReceived;
    supplied += a.supplied;
    backInvalidations += a.backInvalidations;
    latency += a.latency;
    fenceStall += a.fenceStall;
    finish = max(finish, a.finish);
    for (var i = 0; i < 4; i++) {
      miss[i] += a.miss[i];
    }
    for (var i = 0; i < 6; i++) {
      service[i] += a.service[i];
    }
    for (var i = 0; i < 5; i++) {
      bus[i] += a.bus[i];
    }
  }

  List<String> lines(String name) => [
    '$name accesses $accesses reads $reads writes $writes hits $hits misses $misses fences $fences',
    '$name misses ${namedCounts(missNames, miss)} true_sharing $trueSharing false_sharing $falseSharing',
    '$name service ${namedCounts(serviceNames, service)}',
    '$name bus ${namedCounts(busTypes, bus)}',
    '$name snoop invalidations_sent $invalidationsSent invalidations_received $invalidationsReceived supplied $supplied back_invalidations $backInvalidations',
    '$name time latency $latency amat ${fraction(latency, accesses)} ${decimalRatio(latency, accesses)} fence_stall $fenceStall finish $finish',
  ];
}

String fraction(int p, int q) {
  final g = p.gcd(q);
  return '${p ~/ g}/${q ~/ g}';
}

String decimalRatio(int p, int q) {
  final u = (2 * p * 100 + q) ~/ (2 * q);
  return '${u ~/ 100}.${(u % 100).toString().padLeft(2, '0')}';
}

String coreString(int mask) {
  final out = [
    for (var k = 0; k < 8; k++)
      if (((mask >> k) & 1) == 1) k,
  ].join();
  return out.isEmpty ? '-' : out;
}

String namedCounts(List<String> names, List<int> counts) => [
  for (var i = 0; i < names.length; i++) '${names[i]} ${counts[i]}',
].join(' ');
String rangeCounts(List<String> names, List<int> counts) => [
  for (var i = 0; i < names.length; i++) '${names[i]}:${counts[i]}',
].join(' ');
