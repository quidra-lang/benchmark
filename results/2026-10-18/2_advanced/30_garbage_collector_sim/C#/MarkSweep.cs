using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Marking {
    public static void Push(CollectionRecord record, Stack<HeapObject> stack, HeapObject item) {
        item.marked = true;
        stack.Push(item);
        record.stack = Math.Max(record.stack, stack.Count);
    }
    public static void Mark(Collector collector, List<int> roots, CollectionRecord record) {
        foreach (HeapObject item in collector.objects)
            item.marked = false;
        record.work += roots.Count;
        Stack<HeapObject> stack = new();
        foreach (int root in roots) {
            if (root == 0 || collector.Lookup(root).marked)
                continue;
            Push(record, stack, collector.Lookup(root));
            while (stack.Count != 0) {
                HeapObject item = stack.Pop();
                record.live.Add(item);
                record.work += 1 + item.fields.Length;
                foreach (int child in item.fields)
                    if (child != 0 && !collector.Lookup(child).marked)
                        Push(record, stack, collector.Lookup(child));
            }
        }
    }
    public static void Sweep(Collector collector, CollectionRecord record) {
        record.work += collector.objects.Count;
        List<HeapObject> survivors = new();
        foreach (HeapObject item in collector.objects) {
            if (item.marked)
                survivors.Add(item);
            else
                record.freed.Add(item);
        }
        collector.objects = survivors;
    }
}
class MarkSweep : Collector {
    public MarkSweep(int size) : base(size) {
    }
    public override List<FreeBlock> FreeList() {
        return Heap.FreeBlocks(objects, 0, size);
    }
    public override bool Allocate(HeapObject item, List<int> roots, int line) {
        int address = Heap.FirstFit(FreeList(), item.size);
        if (address < 0) {
            Collect(roots, line, item.size);
            address = Heap.FirstFit(FreeList(), item.size);
            if (address < 0)
                return false;
        }
        Place(item, address);
        return true;
    }
    public virtual void Collect(List<int> roots, int line, int request) {
        CollectionRecord record = new CollectionRecord(records.Count + 1, line, request, "sweep", FreeList());
        Marking.Mark(this, roots, record);
        Marking.Sweep(this, record);
        record.Finish(FreeList());
        records.Add(record);
    }
}
sealed class MarkCompact : MarkSweep {
    private int top;
    public MarkCompact(int size) : base(size) {
    }
    public override List<FreeBlock> FreeList() {
        return top < size ? [new FreeBlock(top, size - top)] : [];
    }
    public override bool Allocate(HeapObject item, List<int> roots, int line) {
        if (top + item.size > size) {
            Collect(roots, line, item.size);
            if (top + item.size > size)
                return false;
        }
        Place(item, top);
        top += item.size;
        return true;
    }
    public override void Collect(List<int> roots, int line, int request) {
        CollectionRecord record =
            new CollectionRecord(records.Count + 1, line, request, "compact", FreeList());
        Marking.Mark(this, roots, record);
        record.work += objects.Count + roots.Count;
        int destination = 0;
        List<HeapObject> survivors = new();
        foreach (HeapObject item in Heap.ByAddress(objects)) {
            if (!item.marked) {
                record.freed.Add(item);
                continue;
            }
            record.work += item.fields.Length;
            if (item.address != destination) {
                record.moved.Add(item);
                record.work += item.size;
                item.address = destination;
                item.moves++;
            }
            destination += item.size;
            survivors.Add(item);
        }
        objects = survivors;
        top = destination;
        record.Finish(FreeList());
        records.Add(record);
    }
}
