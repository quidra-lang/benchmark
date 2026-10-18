fn main() {
    for (n, k) in [(7, 3), (10, 2), (41, 3)] {
        let mut people: Vec<usize >= (1..=n).collect();
        let (mut index, mut last) = (0, 0);
        print!("n={} k={}:", n, k);
        while !people.is_empty() {
            index = (index + k - 1) % people.len();
            last = people.remove(index);
            print!(" {}", last);
        }
        println!("\nsurvivor: {}", last);
    }
}
