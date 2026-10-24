void main() {
    const lines = ['date,region,product,quantity,unit_price', '2026-04-01,north,notebook,10,200',
        '2026-04-01,east,marker,6,150', '2026-04-01,south,eraser,25,80', '2026-04-02,west,stapler,4,600',
        '2026-04-02,north,marker,8,150', '2026-04-02,east,notebook,9,200', '2026-04-03,south,stapler,3,600',
        '2026-04-03,west,eraser,15,80', '2026-04-03,north,eraser,20,80', '2026-04-04,east,stapler,5,600',
        '2026-04-04,south,notebook,6,200', '2026-04-04,west,marker,8,150'];
    final regions = <String, int>{}, products = <String, int>{}, dates = <String, int>{};
    var total = 0;
    for (final line in lines.skip(1)) {
        final f = line.split(',');
        final quantity = int.parse(f[3]);
        final sales = quantity * int.parse(f[4]);
        total += sales;
        regions[f[1]] = (regions[f[1]] ?? 0) + sales;
        products[f[2]] = (products[f[2]] ?? 0) + quantity;
        dates[f[0]] = (dates[f[0]] ?? 0) + sales;
    }
    final regionNames = regions.keys.toList()..sort((a, b) {
        final c = regions[b]!.compareTo(regions[a]!);
        return c != 0 ? c : a.compareTo(b);
    }), productNames = products.keys.toList()..sort(), dateNames = dates.keys.toList()..sort();
    print('total: $total');
    for (final name in regionNames)
        print('$name: ${regions[name]}');
    for (final name in productNames)
        print('$name: ${products[name]}');
    final best = dateNames.reduce((a, b) => dates[a]! >= dates[b]! ? a : b);
    print('best day: $best (${dates[best]})');
}
