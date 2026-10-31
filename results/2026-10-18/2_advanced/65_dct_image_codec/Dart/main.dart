import 'dart:io';
import 'dart:math';

part 'image_io.dart';
part 'color.dart';
part 'dct.dart';
part 'entropy.dart';
part 'bitstream.dart';

class Component {
  final int id, h, v, tq, td, ta;
  Component(this.id, this.h, this.v, this.tq, this.td, this.ta);
}

class Geometry {
  final int w, h, restart, hmax, vmax, mx, my;
  final List<Component> components;
  Geometry(this.w, this.h, this.restart, this.components)
    : hmax = components.map((c) => c.h).reduce(max),
      vmax = components.map((c) => c.v).reduce(max),
      mx =
          (w + 8 * components.map((c) => c.h).reduce(max) - 1) ~/
          (8 * components.map((c) => c.h).reduce(max)),
      my =
          (h + 8 * components.map((c) => c.v).reduce(max) - 1) ~/
          (8 * components.map((c) => c.v).reduce(max));
}

class Block {
  final int mcu, k, bx, by;
  List<int> z;
  int diff = 0, bits = 0;
  Block(this.mcu, this.k, this.bx, this.by) : z = List.filled(64, 0);
  Block copy() {
    final b = Block(mcu, k, bx, by);
    b.z = List.of(z);
    b.diff = diff;
    b.bits = bits;
    return b;
  }
}

class Symbol {
  final int table, value, extra, n;
  Symbol(this.table, this.value, [this.extra = 0, this.n = 0]);
}

class Interval {
  final int first, count;
  int position = 0, length = 0;
  String state = 'lost';
  Interval(this.first, this.count);
}

class Encoding {
  final Geometry g;
  final List<List<int>> quant;
  final List<Block> blocks;
  final List<Interval> intervals;
  final List<List<int>> counts = List.generate(4, (_) => List.filled(256, 0));
  late List<Huffman> tables;
  late List<int> bytes;
  int header = 0, scan = 0, padding = 0, stuffed = 0;
  List<Plane> source = [];
  Encoding(this.g, this.quant, List<Block> b)
    : blocks = b.map((v) => v.copy()).toList(),
      intervals = intervalOrder(g);
}

class Segment {
  final int position, length;
  final String name;
  Segment(this.position, this.length, this.name);
}

class Decoding {
  late Geometry g;
  final Map<int, List<int>> quant = {};
  final Map<int, Huffman> tables = {};
  final List<Segment> segments = [Segment(0, 0, 'SOI')];
  late List<Block> blocks;
  late List<Interval> intervals;
  late List<Plane> planes, full;
  late Image image;
  int scan = 0;
}

Geometry encodeGeometry(Image im, String s, int ri) =>
    Geometry(im.w, im.h, ri, [
      Component(1, s == '444' ? 1 : 2, s == '420' ? 2 : 1, 0, 0, 0),
      Component(2, 1, 1, 1, 1, 1),
      Component(3, 1, 1, 1, 1, 1),
    ]);
List<Block> blockOrder(Geometry g) {
  final b = <Block>[];
  for (var m = 0; m < g.mx * g.my; m++) {
    for (var k = 0; k < 3; k++) {
      final c = g.components[k];
      for (var v = 0; v < c.v; v++) {
        for (var h = 0; h < c.h; h++) {
          b.add(Block(m, k, c.h * (m % g.mx) + h, c.v * (m ~/ g.mx) + v));
        }
      }
    }
  }
  return b;
}

List<Interval> intervalOrder(Geometry g) {
  final n = g.mx * g.my, ri = g.restart == 0 ? g.mx * g.my : g.restart;
  return [
    for (var first = 0; first < n; first += ri)
      Interval(first, min(ri, n - first)),
  ];
}

List<int> blockPixels(Plane p, Block b) => [
  for (var y = 0; y < 8; y++)
    ...p.a.sublist(
      (8 * b.by + y) * p.w + 8 * b.bx,
      (8 * b.by + y) * p.w + 8 * b.bx + 8,
    ),
];
List<Symbol> symbols(List<int> z, int diff, int k) {
  final t = k == 0 ? 0 : 2;
  var n = category(diff), run = 0;
  final a = [Symbol(t, n, extra(diff), n)];
  for (var i = 1; i < 64; i++) {
    final v = z[i];
    if (v == 0) {
      run++;
      continue;
    }
    while (run >= 16) {
      a.add(Symbol(t + 1, 240));
      run -= 16;
    }
    n = category(v);
    a.add(Symbol(t + 1, 16 * run + n, extra(v), n));
    run = 0;
  }
  if (run > 0) a.add(Symbol(t + 1, 0));
  return a;
}

List<int> word(int v) => [v >> 8, v & 255];
void segment(List<int> b, int marker, List<int> a) =>
    b.addAll([255, marker, ...word(a.length + 2), ...a]);
List<int> assembleHeader(Geometry g, List<List<int>> q, List<Huffman> t) {
  final b = [255, 216];
  segment(b, 219, [
    for (var k = 0; k < 2; k++) ...[k, ...ordered(q[k])],
  ]);
  segment(b, 192, [
    8,
    ...word(g.h),
    ...word(g.w),
    3,
    for (final c in g.components) ...[c.id, 16 * c.h + c.v, c.tq],
  ]);
  segment(b, 196, [
    for (var k = 0; k < 4; k++) ...[
      16 * (k % 2) + k ~/ 2,
      ...t[k].bits.skip(1),
      ...t[k].values,
    ],
  ]);
  if (g.restart > 0) segment(b, 221, word(g.restart));
  segment(b, 218, [
    3,
    for (final c in g.components) ...[c.id, 16 * c.td + c.ta],
    0,
    63,
    0,
  ]);
  return b;
}

Encoding encodeCoefficients(
  Geometry g,
  List<List<int>> q,
  List<Block> blocks,
  String mode,
  List<Huffman> standard,
) {
  final e = Encoding(g, q, blocks), seq = <List<Symbol>>[];
  var pred = List.filled(3, 0), lastInterval = -1;
  final ri = g.restart == 0 ? g.mx * g.my : g.restart;
  for (final b in e.blocks) {
    final j = b.mcu ~/ ri;
    if (j != lastInterval) {
      pred = List.filled(3, 0);
      lastInterval = j;
    }
    b.diff = b.z[0] - pred[b.k];
    pred[b.k] = b.z[0];
    final ss = symbols(b.z, b.diff, b.k);
    seq.add(ss);
    for (final s in ss) {
      e.counts[s.table][s.value]++;
    }
  }
  e.tables = mode == 'optimized' ? e.counts.map(optimized).toList() : standard;
  final head = assembleHeader(g, q, e.tables),
      writer = BitWriter(assembleHeader(g, q, e.tables));
  e.header = head.length;
  lastInterval = -1;
  for (var i = 0; i < e.blocks.length; i++) {
    final b = e.blocks[i], j = b.mcu ~/ ri;
    if (j != lastInterval) {
      if (lastInterval >= 0) {
        writer.pad();
        e.intervals[lastInterval].length =
            writer.bytes.length - e.intervals[lastInterval].position;
        writer.marker(208 + lastInterval % 8);
      }
      e.intervals[j].position = writer.bytes.length;
      lastInterval = j;
    }
    for (final s in seq[i]) {
      final t = e.tables[s.table];
      writer.write(t.code[s.value], t.length[s.value]);
      writer.write(s.extra, s.n);
      b.bits += t.length[s.value] + s.n;
    }
  }
  writer.pad();
  e.intervals[lastInterval].length =
      writer.bytes.length - e.intervals[lastInterval].position;
  e.scan = writer.bytes.length - e.header;
  e.padding = writer.padding;
  e.stuffed = writer.stuffed;
  e.bytes = [...writer.bytes, 255, 217];
  return e;
}

Encoding encode(
  Image im,
  int quality,
  String sampling,
  String mode,
  int ri,
  InputTables t,
) {
  final g = encodeGeometry(im, sampling, ri), q = quantTables(t.base, quality);
  final p = componentPlanes(im, g), blocks = blockOrder(g);
  for (final b in blocks) {
    b.z = quantize(
      transform(blockPixels(p[b.k], b), t.c),
      q[g.components[b.k].tq],
    );
  }
  final e = encodeCoefficients(g, q, blocks, mode, t.standard);
  e.source = p;
  return e;
}

List<Plane> makePlanes(
  Geometry g,
  List<Block> blocks,
  Map<int, List<int>> quant,
  List<int> c,
) {
  final p = [
    for (final k in g.components) Plane(8 * k.h * g.mx, 8 * k.v * g.my),
  ];
  for (final b in blocks) {
    final a = reconstruct(b.z, quant[g.components[b.k].tq]!, c);
    for (var y = 0; y < 8; y++) {
      p[b.k].a.setRange(
        (8 * b.by + y) * p[b.k].w + 8 * b.bx,
        (8 * b.by + y) * p[b.k].w + 8 * b.bx + 8,
        a,
        y * 8,
      );
    }
  }
  return p;
}

int readWord(List<int> b, int p) => 256 * b[p] + b[p + 1];
Decoding decode(List<int> b, List<int> c) {
  final d = Decoding();
  var p = 2, ri = 0, w = 0, h = 0;
  final components = <Component>[];
  while (true) {
    final m = b[p + 1], ls = readWord(b, p + 2);
    final a = b.sublist(p + 4, p + ls + 2);
    var name = '';
    if (m >= 224 && m <= 239) {
      name = 'APP${m - 224}';
    } else if (m == 254) {
      name = 'COM';
    } else if (m == 219) {
      name = 'DQT';
      for (var j = 0; j < a.length; j += 65) {
        final q = List.filled(64, 0), zz = zigzag();
        for (var k = 0; k < 64; k++) {
          q[zz[k]] = a[j + 1 + k];
        }
        d.quant[a[j]] = q;
      }
    } else if (m == 196) {
      name = 'DHT';
      for (var j = 0; j < a.length;) {
        final key = 4 * (a[j] >> 4) + (a[j] & 15);
        j++;
        final bits = [0, ...a.sublist(j, j + 16)];
        j += 16;
        final n = bits.reduce((a, b) => a + b);
        d.tables[key] = Huffman(bits, a.sublist(j, j + n));
        j += n;
      }
    } else if (m == 192) {
      name = 'SOF0';
      h = readWord(a, 1);
      w = readWord(a, 3);
      for (var k = 0; k < 3; k++) {
        final j = 6 + 3 * k;
        components.add(
          Component(a[j], a[j + 1] >> 4, a[j + 1] & 15, a[j + 2], 0, 0),
        );
      }
    } else if (m == 221) {
      name = 'DRI';
      ri = readWord(a, 0);
    } else if (m == 218) {
      name = 'SOS';
      for (var k = 0; k < 3; k++) {
        final j = 1 + 2 * k;
        for (var v = 0; v < 3; v++) {
          final co = components[v];
          if (co.id == a[j])
            components[v] = Component(
              co.id,
              co.h,
              co.v,
              co.tq,
              a[j + 1] >> 4,
              a[j + 1] & 15,
            );
        }
      }
    }
    d.segments.add(Segment(p, ls, name));
    p += ls + 2;
    if (m == 218) break;
  }
  d.segments.add(Segment(b.length - 2, 0, 'EOI'));
  d.scan = b.length - 2 - p;
  d.g = Geometry(w, h, ri, components);
  d.blocks = blockOrder(d.g);
  d.intervals = intervalOrder(d.g);
  final perMCU = d.blocks.length ~/ (d.g.mx * d.g.my), reader = BitReader(b, p);
  for (var j = 0; j < d.intervals.length;) {
    final iv = d.intervals[j],
        first = iv.first * perMCU,
        end = (iv.first + iv.count) * perMCU;
    final temp = List.generate(end - first, (_) => List.filled(64, 0)),
        pred = List.filled(3, 0);
    var kind = '', mcu = iv.first;
    try {
      for (var bi = first; bi < end; bi++) {
        final bl = d.blocks[bi], co = components[d.blocks[bi].k];
        mcu = bl.mcu;
        final n = reader.symbol(d.tables[co.td]!);
        pred[bl.k] += decodedExtra(reader.read(n), n);
        final z = temp[bi - first];
        z[0] = pred[bl.k];
        for (var i = 1; i < 64;) {
          final a = reader.symbol(d.tables[4 + co.ta]!);
          if (a == 0) break;
          i += a ~/ 16;
          final n = a % 16;
          if (i > 63) throw DecodeError('index');
          if (n > 0) z[i] = decodedExtra(reader.read(n), n);
          i++;
        }
      }
    } on DecodeError catch (e) {
      kind = e.kind;
    }
    reader.left = 0;
    if (kind.isEmpty) {
      final expected = j < d.intervals.length - 1 ? 208 + j % 8 : 217;
      if (reader.pos + 1 < b.length &&
          b[reader.pos] == 255 &&
          b[reader.pos + 1] == expected) {
        for (var bi = first; bi < end; bi++) {
          d.blocks[bi].z = temp[bi - first];
        }
        d.intervals[j].state = 'ok';
        reader.pos += 2;
        j++;
        continue;
      }
      kind = 'sync';
      mcu = iv.first + iv.count - 1;
    }
    final offset = reader.pos, q = resync(b, reader.pos);
    d.intervals[j].state = 'damaged $kind mcu $mcu offset $offset resync $q';
    final marker = b[q + 1];
    reader.pos = q + 2;
    if (marker == 217) break;
    j = j + 1 + (marker - 208 - j) % 8;
  }
  d.planes = makePlanes(d.g, d.blocks, d.quant, c);
  final (full, image) = upsample(d.planes, d.g);
  d.full = full;
  d.image = image;
  return d;
}

int sse(List<int> a, List<int> b) {
  var s = 0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i] - b[i];
    s += x * x;
  }
  return s;
}

String psnr(int error, int n) => error == 0
    ? 'inf'
    : (10 * log(65025 * n / error) / ln10).toStringAsFixed(2);

class Metrics {
  final List<String> psnr;
  final int maxError;
  Metrics(this.psnr, this.maxError);
}

Metrics evaluate(Image original, List<Plane> planes, Decoding d) {
  final values = [
    for (var k = 0; k < 3; k++)
      psnr(sse(planes[k].a, d.full[k].a), original.w * original.h),
    psnr(sse(original.rgb, d.image.rgb), original.rgb.length),
  ];
  var error = 0;
  for (var i = 0; i < original.rgb.length; i++) {
    error = max(error, (original.rgb[i] - d.image.rgb[i]).abs());
  }
  return Metrics(values, error);
}

String fraction(int a, int b) {
  final g = a.gcd(b);
  return '${a ~/ g}/${b ~/ g}';
}

int changed(Image a, Image b) {
  var n = 0;
  for (var i = 0; i < a.w * a.h; i++) {
    if (a.rgb[3 * i] != b.rgb[3 * i] ||
        a.rgb[3 * i + 1] != b.rgb[3 * i + 1] ||
        a.rgb[3 * i + 2] != b.rgb[3 * i + 2])
      n++;
  }
  return n;
}

void main() {
  final im = readImage('input/image.ppm'),
      params = readParameters(),
      t = readTables();
  Directory('output').createSync(recursive: true);
  final orig = colors(im),
      csv = StringBuffer(
        'quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error\n',
      );
  late Encoding ref;
  late Decoding decoded;
  for (var i = 0; i < params.qualities.length; i++) {
    final q = params.qualities[i],
        standard = encode(
          im,
          params.qualities[i],
          params.sampling,
          'standard',
          params.restart,
          t,
        ),
        opt = encode(
          im,
          params.qualities[i],
          params.sampling,
          'optimized',
          params.restart,
          t,
        );
    final e = params.mode == 'optimized' ? opt : standard,
        d = decode(
          params.mode == 'optimized' ? opt.bytes : standard.bytes,
          t.c,
        );
    final m = evaluate(im, orig, d);
    csv.writeln(
      '$q,${standard.bytes.length},${opt.bytes.length},${fraction(8 * e.bytes.length, im.w * im.h)},${m.psnr.join(',')},${m.maxError}',
    );
    if (i == 0) {
      ref = e;
      decoded = d;
    }
  }
  writeText('output/rate_distortion.csv', csv.toString());
  writeImage('output/decoded.ppm', decoded.image);
  writeHex('output/bitstream.hex', ref.bytes);
  final tw = (im.w + 7) ~/ 8, th = (im.h + 7) ~/ 8;
  final thumb = Image(tw, th, List.filled(3 * tw * th, 0)),
      dc = <(int, int, int), int>{};
  for (final b in ref.blocks) {
    dc[(b.k, b.bx, b.by)] = b.z[0];
  }
  for (var y = 0; y < th; y++) {
    for (var x = 0; x < tw; x++) {
      final a = <int>[];
      for (var k = 0; k < 3; k++) {
        final c = ref.g.components[k],
            bx = x * ref.g.components[k].h ~/ ref.g.hmax,
            by = y * ref.g.components[k].v ~/ ref.g.vmax;
        a.add(clamp(floor(dc[(k, bx, by)]! * ref.quant[c.tq][0] + 4, 8) + 128));
      }
      thumb.rgb.setRange(
        3 * (y * tw + x),
        3 * (y * tw + x) + 3,
        toRgb(a[0], a[1], a[2]),
      );
    }
  }
  writeImage('output/thumbnail.ppm', thumb);
  final names = ['dc_luma', 'ac_luma', 'dc_chroma', 'ac_chroma'],
      ht = StringBuffer();
  for (var k = 0; k < 4; k++) {
    final table = ref.tables[k];
    var coded = 0, bits = 0;
    for (var v = 0; v < 256; v++) {
      coded += ref.counts[k][v];
      bits += ref.counts[k][v] * table.length[v];
    }
    ht.writeln(
      'table ${names[k]} class ${k % 2} id ${k ~/ 2} symbols ${table.values.length} coded $coded bits $bits',
    );
    ht.writeln('counts ${joined(table.bits.skip(1))}');
    for (final v in table.values) {
      ht.writeln(
        'symbol ${v.toRadixString(16).padLeft(2, '0')} length ${table.length[v]} code ${table.code[v].toRadixString(2).padLeft(table.length[v], '0')} count ${ref.counts[k][v]}',
      );
    }
  }
  writeText('output/huffman_tables.txt', ht.toString());
  final bs = StringBuffer('blocks ${ref.blocks.length}\n'),
      nonzero = List.filled(64, 0),
      componentBits = List.filled(3, 0),
      componentNZ = List.filled(3, 0),
      componentSSE = List.filled(3, 0),
      componentNames = ['Y', 'Cb', 'Cr'];
  var zeroAC = 0;
  for (var i = 0; i < ref.blocks.length; i++) {
    final b = ref.blocks[i];
    var n = 0, last = 0;
    for (var k = 0; k < 64; k++) {
      if (b.z[k] != 0) {
        nonzero[k]++;
        componentNZ[b.k]++;
        if (k > 0) {
          n++;
          last = k;
        }
      }
    }
    if (n == 0) zeroAC++;
    componentBits[b.k] += b.bits;
    final error = sse(
      blockPixels(ref.source[b.k], b),
      blockPixels(decoded.planes[b.k], b),
    );
    componentSSE[b.k] += error;
    bs.writeln(
      'block $i ${componentNames[b.k]} ${b.bx} ${b.by} dc ${b.z[0]} diff ${b.diff} nonzero $n last $last bits ${b.bits} sse $error',
    );
  }
  writeText('output/blocks.txt', bs.toString());
  final stream = decode(readHex('input/stream.hex'), t.c);
  writeImage('output/stream_decoded.ppm', stream.image);
  final repairComponents = [
        for (var k = 0; k < 3; k++)
          Component(
            k + 1,
            stream.g.components[k].h,
            stream.g.components[k].v,
            k == 0 ? 0 : 1,
            k == 0 ? 0 : 1,
            k == 0 ? 0 : 1,
          ),
      ],
      repairQuant = [
        stream.quant[stream.g.components[0].tq]!,
        stream.quant[stream.g.components[1].tq]!,
      ];
  final repairGeometry = Geometry(
    stream.g.w,
    stream.g.h,
    stream.g.restart,
    repairComponents,
  );
  final repaired = encodeCoefficients(
    repairGeometry,
    repairQuant,
    stream.blocks,
    'optimized',
    t.standard,
  );
  writeHex('output/repaired.hex', repaired.bytes);
  final check = decode(repaired.bytes, t.c);
  var identical = 'yes';
  for (var i = 0; i < stream.image.rgb.length; i++) {
    if (stream.image.rgb[i] != check.image.rgb[i]) identical = 'no';
  }
  final report = StringBuffer(), g = ref.g;
  report.writeln('image ${im.w} ${im.h}');
  report.writeln(
    'sampling ${params.sampling} mcu ${8 * g.hmax} ${8 * g.vmax} grid ${g.mx} ${g.my}',
  );
  report.writeln('padded ${8 * g.hmax * g.mx} ${8 * g.vmax * g.my}');
  report.writeln(
    'blocks ${g.components[0].h * g.components[0].v * g.mx * g.my} ${g.mx * g.my} ${g.mx * g.my}',
  );
  report.writeln(
    'restart_interval ${params.restart} markers ${ref.intervals.length - 1}',
  );
  report.writeln('huffman ${params.mode}');
  report.writeln('quality ${params.qualities[0]}');
  for (var k = 0; k < 2; k++) {
    report.writeln('quant $k ${joined(ordered(ref.quant[k]))}');
  }
  final counts = [for (final a in ref.counts) a.reduce((a, b) => a + b)];
  report.writeln('symbols ${joined(counts)}');
  report.writeln(
    'eob ${ref.counts[1][0] + ref.counts[3][0]} zrl ${ref.counts[1][240] + ref.counts[3][240]}',
  );
  report.writeln('zero_ac_blocks $zeroAC');
  report.writeln('nonzero ${joined(nonzero)}');
  for (var k = 0; k < 3; k++) {
    report.writeln(
      'component ${componentNames[k]} bits ${componentBits[k]} nonzero ${componentNZ[k]} sse ${componentSSE[k]}',
    );
  }
  report.writeln('padding_bits ${ref.padding}');
  report.writeln('stuffed_bytes ${ref.stuffed}');
  report.writeln('header_bytes ${ref.header}');
  report.writeln('scan_bytes ${ref.scan}');
  report.writeln('total_bytes ${ref.bytes.length}');
  for (var j = 0; j < ref.intervals.length; j++) {
    final iv = ref.intervals[j];
    report.writeln(
      'interval $j ${iv.first} ${iv.count} ${iv.position} ${iv.length}',
    );
  }
  final histogram = List.filled(8, 0);
  for (var i = 0; i < im.rgb.length; i++) {
    final e = (im.rgb[i] - decoded.image.rgb[i]).abs();
    final bin = e == 0
        ? 0
        : e == 1
        ? 1
        : e <= 3
        ? 2
        : e <= 7
        ? 3
        : e <= 15
        ? 4
        : e <= 31
        ? 5
        : e <= 63
        ? 6
        : 7;
    histogram[bin]++;
  }
  report.writeln('error_histogram ${joined(histogram)}');
  for (final keep in params.truncate) {
    final blocks = decoded.blocks.map((v) => v.copy()).toList();
    for (final b in blocks) {
      if (b.k == 0) {
        for (var k = keep; k < 64; k++) {
          b.z[k] = 0;
        }
      }
    }
    final p = makePlanes(decoded.g, blocks, decoded.quant, t.c);
    final (a, _) = upsample(p, decoded.g);
    report.writeln(
      'truncate $keep ${psnr(sse(orig[0].a, a[0].a), im.w * im.h)}',
    );
  }
  for (final s in ['444', '422', '420']) {
    final e = encode(
      im,
      params.qualities[0],
      s,
      params.mode,
      params.restart,
      t,
    );
    final m = evaluate(im, orig, decode(e.bytes, t.c));
    report.writeln(
      'sampling_compare $s ${e.bytes.length} ${m.psnr[1]} ${m.psnr[2]} ${m.psnr[3]}',
    );
  }
  var previous = im;
  for (var generation = 1; generation <= params.generations; generation++) {
    final e = encode(
      previous,
      params.qualities[0],
      params.sampling,
      params.mode,
      params.restart,
      t,
    );
    final d = decode(e.bytes, t.c);
    report.writeln(
      'generation $generation ${e.bytes.length} ${psnr(sse(im.rgb, d.image.rgb), im.rgb.length)} ${changed(previous, d.image)}',
    );
    previous = d.image;
  }
  var lo = 1, hi = 100;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2,
        e = encode(
          im,
          (lo + hi + 1) ~/ 2,
          params.sampling,
          params.mode,
          params.restart,
          t,
        );
    report.writeln('rate_control_step $mid ${e.bytes.length}');
    if (e.bytes.length <= params.target) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  final chosen = encode(
    im,
    lo,
    params.sampling,
    params.mode,
    params.restart,
    t,
  );
  report.writeln(
    'rate_control $lo ${chosen.bytes.length} ${chosen.bytes.length <= params.target ? 'yes' : 'no'} ${psnr(sse(im.rgb, decode(chosen.bytes, t.c).image.rgb), im.rgb.length)}',
  );
  for (final s in stream.segments) {
    report.writeln('stream_segment ${s.position} ${s.name} ${s.length}');
  }
  report.writeln('stream_image ${stream.g.w} ${stream.g.h}');
  for (final c in stream.g.components) {
    report.writeln(
      'stream_component ${c.id} ${c.h} ${c.v} ${c.tq} ${c.td} ${c.ta}',
    );
  }
  final quantKeys = stream.quant.keys.toList()..sort();
  for (final k in quantKeys) {
    report.writeln('stream_quant $k ${joined(ordered(stream.quant[k]!))}');
  }
  final tableKeys = stream.tables.keys.toList()..sort();
  for (final k in tableKeys) {
    final table = stream.tables[k]!;
    var longest = 0;
    for (var l = 1; l <= 16; l++) {
      if (table.bits[l] > 0) longest = l;
    }
    report.writeln(
      'stream_huffman ${k ~/ 4} ${k % 4} symbols ${table.values.length} longest $longest',
    );
  }
  var ok = 0, damaged = 0, lost = 0;
  for (final iv in stream.intervals) {
    if (iv.state == 'ok') {
      ok++;
    } else if (iv.state == 'lost') {
      lost++;
    } else {
      damaged++;
    }
  }
  report.writeln(
    'stream_restart ${stream.g.restart} intervals ${stream.intervals.length} ok $ok damaged $damaged lost $lost',
  );
  for (var j = 0; j < stream.intervals.length; j++) {
    final iv = stream.intervals[j];
    report.writeln('stream_interval $j ${iv.first} ${iv.count} ${iv.state}');
  }
  report.writeln('stream_scan_bytes ${stream.scan}');
  report.writeln(
    'repair ${repaired.bytes.length} ${repaired.header} ${repaired.scan} identical $identical',
  );
  writeText('output/report.txt', report.toString());
}
