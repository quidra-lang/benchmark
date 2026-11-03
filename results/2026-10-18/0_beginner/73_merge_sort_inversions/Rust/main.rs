fn merge_sort(a: &mut [i32], l: usize, r: usize) -> usize {
    if l == r {
        return 0;
    }
    let m = (l + r) / 2;
    let mut count = merge_sort(a, l, m);
    count += merge_sort(a, m + 1, r);
    let mut temp = Vec::new();
    let (mut i, mut j) = (l, m + 1);
    while i <= m && j <= r {
        if a[i] < a[j] {
            temp.push(a[i]);
            i += 1;
        } else {
            temp.push(a[j]);
            j += 1;
            count += m - i + 1;
        }
    }
    temp.extend_from_slice(&a[i..m + 1]);
    temp.extend_from_slice(&a[j..r + 1]);
    a[l..=r].copy_from_slice(&temp);
    print!("merge [{}..{}]:", l, r);
    for n in &a[l..=r] {
        print!(" {}", n);
    }
    println!();
    count
}

fn main() {
    let mut a = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14];
    let inversions = merge_sort(&mut a, 0, 9);
    print!("sorted:");
    for n in a {
        print!(" {}", n);
    }
    println!("\ninversions: {}", inversions);
}
