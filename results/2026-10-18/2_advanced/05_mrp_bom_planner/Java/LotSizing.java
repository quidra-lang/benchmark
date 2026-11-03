final class LotSizing {
    static long size(Item item, int week, long projected, long[] receipts, long[] gross, int horizon) {
        long quantity = item.safety() - projected;
        if (item.rule().equals("LFL")) return quantity;
        if (item.rule().equals("FOQ")) return (quantity + item.first() - 1) / item.first() * item.first();
        if (item.rule().equals("MIN")) return (Math.max(quantity, item.first()) + item.second() - 1) / item.second() * item.second();
        int end = (int) Math.min(week + item.first() - 1, horizon);
        for (int later = week + 1; later <= end; later++) { projected += receipts[later] - gross[later]; quantity = Math.max(quantity, item.safety() - projected); } return quantity;
    }
}
