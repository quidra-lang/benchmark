part of 'main.dart';

class Image {
  final int w, h;
  final List<int> pixels;
  Image(this.w, this.h, this.pixels);
}

class Params {
  int min = 0,
      max = 0,
      textureWindow = 0,
      textureThreshold = 0,
      uniqueness = 0,
      lr = 0,
      sgmWindow = 0,
      paths = 0,
      p1 = 0,
      p2 = 0,
      gamma = 0,
      speckleSize = 0,
      speckleRange = 0,
      fusionVotes = 0,
      objectRange = 0,
      objectSize = 0,
      focal = 0,
      baseline = 0;
  String wtaCost = '', sgmCost = '';
  final windows = <String, List<int>>{}, samples = <(int, int)>[];
}

List<String> lines(String path) => File(path).readAsLinesSync();
Image readPGM(String path) {
  final a = lines(path), header = a[1].split(' ');
  return Image(
    int.parse(header[0]),
    int.parse(header[1]),
    a.skip(3).expand((s) => s.split(' ')).map(int.parse).toList(),
  );
}

Params readParams() {
  final p = Params();
  for (final line in lines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'disparity_min':
        p.min = int.parse(a[1]);
      case 'disparity_max':
        p.max = int.parse(a[1]);
      case 'sad_windows':
      case 'ssd_windows':
      case 'census_windows':
        p.windows[a[0].substring(0, a[0].length - 8)] = a
            .sublist(1)
            .map(int.parse)
            .toList();
      case 'texture_window':
        p.textureWindow = int.parse(a[1]);
      case 'texture_threshold':
        p.textureThreshold = int.parse(a[1]);
      case 'uniqueness':
        p.uniqueness = int.parse(a[1]);
      case 'lr_max_diff':
        p.lr = int.parse(a[1]);
      case 'wta_cost':
        p.wtaCost = a[1];
      case 'sgm_cost':
        p.sgmCost = a[1];
      case 'sgm_window':
        p.sgmWindow = int.parse(a[1]);
      case 'sgm_paths':
        p.paths = int.parse(a[1]);
      case 'p1':
        p.p1 = int.parse(a[1]);
      case 'p2':
        p.p2 = int.parse(a[1]);
      case 'p2_gamma':
        p.gamma = int.parse(a[1]);
      case 'speckle_size':
        p.speckleSize = int.parse(a[1]);
      case 'speckle_range':
        p.speckleRange = int.parse(a[1]);
      case 'fusion_min_votes':
        p.fusionVotes = int.parse(a[1]);
      case 'object_range':
        p.objectRange = int.parse(a[1]);
      case 'object_min_size':
        p.objectSize = int.parse(a[1]);
      case 'focal_length':
        p.focal = int.parse(a[1]);
      case 'baseline':
        p.baseline = int.parse(a[1]);
      case 'sample':
        p.samples.add((int.parse(a[1]), int.parse(a[2])));
    }
  }
  return p;
}

void writeLines(String name, List<String> a) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${a.join('\n')}\n');
}

void writePGM(String name, int w, int h, List<int> pixels) => writeLines(name, [
  'P2',
  '$w $h',
  '255',
  for (var y = 0; y < h; y++) pixels.sublist(y * w, (y + 1) * w).join(' '),
]);
