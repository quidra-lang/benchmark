use std::collections::BTreeSet;

fn main() {
    let a = BTreeSet::from([12, 5, 8, 21, 5, 17, 3, 12, 9]);
    let b = BTreeSet::from([8, 14, 21, 6, 14, 3, 25, 6]);
    let results = [
        ("union", a.union(&b).copied().collect::<Vec<_>>()),
        ("intersection", a.intersection(&b).copied().collect()),
        ("difference", a.difference(&b).copied().collect()),
        (
            "symmetric difference",
            a.symmetric_difference(&b).copied().collect(),
        ),
    ];
    for (label, values) in results {
        println!(
            "{}: {}",
            label,
            values
                .iter()
                .map(i32::to_string)
                .collect::<Vec<_>>()
                .join(" ")
        );
    }
}
