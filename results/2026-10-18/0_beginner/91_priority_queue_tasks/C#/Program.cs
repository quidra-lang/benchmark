using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

string[] operations = { "add email 3", "add backup 5", "add deploy 1", "run", "add report 3", "add test 2",
    "add lint 3", "run", "run", "add cleanup 5", "add review 2", "run", "add build 1",
    "add docs 4", "run", "run" };
var queue = new PriorityQueue<string,(int priority,int sequence)>();
int sequence = 0;
foreach (string operation in operations) {
    string[] parts = operation.Split(' ');
    if (parts[0] == "add") queue.Enqueue(parts[1],(int.Parse(parts[2],CultureInfo.InvariantCulture),sequence++));
    else {
        queue.TryDequeue(out string? name,out var priority);
        Console.WriteLine($"run: {name} (priority {priority.priority})");
    }
}
var remaining = new List<string>();
while (queue.Count > 0) remaining.Add(queue.Dequeue());
Console.WriteLine($"remaining: {string.Join(" ",remaining)}");
