part of 'main.dart';

class Rating {
  int user, item;
  final int value, time;
  Rating(this.user, this.item, this.value, [this.time = 0]);
}

class RatingPair {
  final int other, value;
  RatingPair(this.other, this.value);
}

class ItemInfo {
  final String title, genreText;
  final List<String> genres;
  ItemInfo(this.title, this.genreText) : genres = genreText.split('|');
}

class Params {
  final int neighbors,
      shrinkage,
      factors,
      epochs,
      alsIterations,
      seed,
      topN,
      buckets,
      listSize;
  final double minSimilarity, itemReg, userReg, rate, regularization, alsReg;
  final List<int> cutoffs,
      neighborGrid,
      userGroups,
      itemGroups,
      recommendUsers,
      similarItems;
  Params(
    this.neighbors,
    this.shrinkage,
    this.minSimilarity,
    this.itemReg,
    this.userReg,
    this.factors,
    this.rate,
    this.regularization,
    this.epochs,
    this.alsReg,
    this.alsIterations,
    this.seed,
    this.topN,
    this.cutoffs,
    this.neighborGrid,
    this.userGroups,
    this.itemGroups,
    this.buckets,
    this.listSize,
    this.recommendUsers,
    this.similarItems,
  );
}

class Ratings {
  final List<Rating> training, test;
  final Map<int, ItemInfo> catalog;
  final Params params;
  late final List<int> users, items, userCounts, itemCounts;
  late final Map<int, int> userIndex, itemIndex;
  late final List<List<RatingPair>> byUser, byItem;
  late final List<List<int>> values;
  late final List<double> userMeans, itemMeans;
  late final double mean;
  Ratings(this.training, this.test, this.catalog, this.params) {
    users = training.map((r) => r.user).toSet().toList()..sort();
    items = training.map((r) => r.item).toSet().toList()..sort();
    userIndex = {for (var u = 0; u < users.length; u++) users[u]: u};
    itemIndex = {for (var i = 0; i < items.length; i++) items[i]: i};
    byUser = List.generate(users.length, (_) => <RatingPair>[]);
    byItem = List.generate(items.length, (_) => <RatingPair>[]);
    values = List.generate(users.length, (_) => List.filled(items.length, 0));
    userCounts = List.filled(users.length, 0);
    itemCounts = List.filled(items.length, 0);
    userMeans = List.filled(users.length, 0.0);
    itemMeans = List.filled(items.length, 0.0);
    var total = 0;
    for (final r in training) {
      r.user = userIndex[r.user]!;
      r.item = itemIndex[r.item]!;
      total += r.value;
      values[r.user][r.item] = r.value;
      byUser[r.user].add(RatingPair(r.item, r.value));
      byItem[r.item].add(RatingPair(r.user, r.value));
    }
    for (final r in test) {
      r.user = userIndex[r.user]!;
      r.item = itemIndex[r.item]!;
    }
    for (var u = 0; u < users.length; u++) {
      final rows = byUser[u]..sort((a, b) => a.other.compareTo(b.other));
      var sum = 0;
      for (final r in rows) {
        sum += r.value;
      }
      userCounts[u] = rows.length;
      userMeans[u] = sum / rows.length;
    }
    for (var i = 0; i < items.length; i++) {
      final rows = byItem[i]..sort((a, b) => a.other.compareTo(b.other));
      var sum = 0;
      for (final r in rows) {
        sum += r.value;
      }
      itemCounts[i] = rows.length;
      itemMeans[i] = sum / rows.length;
    }
    mean = total / training.length;
  }
}

List<String> readLines(String path) => File(path).readAsLinesSync();
List<int> integerList(List<String> values) => values.map(int.parse).toList();
Params readParams() {
  final v = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final f = line.split(' ');
    v[f[0]] = f.sublist(1);
  }
  return Params(
    int.parse(v['NEIGHBORS']![0]),
    int.parse(v['SHRINKAGE']![0]),
    double.parse(v['MIN_SIMILARITY']![0]),
    double.parse(v['BIAS_REG']![0]),
    double.parse(v['BIAS_REG']![1]),
    int.parse(v['FACTORS']![0]),
    double.parse(v['LEARNING_RATE']![0]),
    double.parse(v['REGULARIZATION']![0]),
    int.parse(v['EPOCHS']![0]),
    double.parse(v['ALS_REG']![0]),
    int.parse(v['ALS_ITERATIONS']![0]),
    int.parse(v['SEED']![0]),
    int.parse(v['TOP_N']![0]),
    integerList(v['CUTOFFS']!),
    integerList(v['NEIGHBOR_GRID']!),
    integerList(v['USER_GROUPS']!),
    integerList(v['ITEM_GROUPS']!),
    int.parse(v['TIME_BUCKETS']![0]),
    int.parse(v['LIST_SIZE']![0]),
    integerList(v['RECOMMEND_USERS']!),
    integerList(v['SIMILAR_ITEMS']!),
  );
}

List<Rating> readRatingFile(String path) {
  final rows = <Rating>[];
  for (final line in readLines(path).skip(1)) {
    final f = line.split(',');
    rows.add(
      Rating(
        int.parse(f[0]),
        int.parse(f[1]),
        int.parse(f[2]),
        f.length == 4 ? int.parse(f[3]) : 0,
      ),
    );
  }
  return rows;
}

Ratings readInputs() {
  final catalog = <int, ItemInfo>{};
  for (final line in readLines('input/items.csv').skip(1)) {
    final f = line.split(',');
    catalog[int.parse(f[0])] = ItemInfo(f[1], f[2]);
  }
  return Ratings(
    readRatingFile('input/ratings.csv'),
    readRatingFile('input/test.csv'),
    catalog,
    readParams(),
  );
}
