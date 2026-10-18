fn search(p: &mut String, used: &mut[bool; 4], count: &mut i32) {
    if p.len() == 4 {
        * count += 1;
        println!("{}: {}", count, p);
        return;
    }
    for i in 0..4 {
        if !used[i] {
            used[i] = true;
            p.push((b'A' + i as u8) as char);
            search(p, used, count);
            p.pop();
            used[i] = false;
        }
    }
}

fn main() {
    let mut permutation = String::new();
    let mut used = [false; 4];
    let mut count = 0;
    search(&mut permutation, &mut used, &mut count);
}
