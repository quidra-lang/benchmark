using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class Copying : Collector {
    public readonly int half;
    public int baseAddress, top;
    public Copying(int size) : base(size) {
        half = size / 2;
    }
    public override List<FreeBlock> FreeList() {
        return top < baseAddress + half ? [new FreeBlock(top, baseAddress + half - top)] : [];
    }
    public override int[] Inactive() {
        return new int[] { half - baseAddress, 2 * half - baseAddress };
    }
    public override bool Allocate(HeapObject item, List<int> roots, int line) {
        if (top + item.size > baseAddress + half) {
            Collect(roots, line, item.size);
            if (top + item.size > baseAddress + half)
                return false;
        }
        Place(item, top);
        top += item.size;
        return true;
    }
    public void Copy(int number, CollectionRecord record, HashSet<int> copied, List<HeapObject> queue) {
        if (number == 0 || !copied.Add(number))
            return;
        HeapObject item = Lookup(number);
        item.address = top;
        top += item.size;
        item.moves++;
        record.live.Add(item);
        record.moved.Add(item);
        queue.Add(item);
    }
    public void Collect(List<int> roots, int line, int request) {
        CollectionRecord record = new CollectionRecord(records.Count + 1, line, request, "copy", FreeList());
        baseAddress = half - baseAddress;
        top = baseAddress;
        HashSet<int> copied = new();
        List<HeapObject> queue = new();
        record.work += roots.Count;
        foreach (int root in roots)
            Copy(root, record, copied, queue);
        for (int i = 0; i < queue.Count; i++) {
            HeapObject item = queue[i];
            record.work += item.size + item.fields.Length;
            foreach (int child in item.fields)
                Copy(child, record, copied, queue);
        }
        foreach (HeapObject item in objects)
            if (!copied.Contains(item.number))
                record.freed.Add(item);
        objects = queue;
        record.Finish(FreeList());
        records.Add(record);
    }
}
