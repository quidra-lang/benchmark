use std::cmp::Reverse;
use std::collections::BinaryHeap;

fn main() {
    let mut queue = BinaryHeap::new();
    let mut sequence = 0;
    for operation in [
        "add email 3",
        "add backup 5",
        "add deploy 1",
        "run",
        "add report 3",
        "add test 2",
        "add lint 3",
        "run",
        "run",
        "add cleanup 5",
        "add review 2",
        "run",
        "add build 1",
        "add docs 4",
        "run",
        "run",
    ] {
        let parts: Vec<&str> = operation.split(' ').collect();
        if parts[0] == "run" {
            let Reverse((priority, _, name)) = queue.pop().unwrap();
            println!("run: {} (priority {})", name, priority);
        } else {
            let priority: i32 = parts[2].parse().unwrap();
            queue.push(Reverse((priority, sequence, parts[1])));
            sequence += 1;
        }
    }
    print!("remaining:");
    while let Some(Reverse((_, _, name))) = queue.pop() {
        print!(" {}", name);
    }
    println!();
}
