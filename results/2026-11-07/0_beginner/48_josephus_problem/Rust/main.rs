fn main() {
    for (n, k) in [(7, 3), (10, 2), (41, 3)] {
        let mut people: Vec<usize> = (1..=n).collect();
        let mut index = 0;
        let mut removed = Vec::new();
        while !people.is_empty() {
            index = (index + k - 1) % people.len();
            removed.push(people.remove(index));
        }
        print!("n={} k={}:", n, k);
        for person in &removed {
            print!(" {}", person);
        }
        println!("\nsurvivor: {}", removed.last().unwrap());
    }
}
