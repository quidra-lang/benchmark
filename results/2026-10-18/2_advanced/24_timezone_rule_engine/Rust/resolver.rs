use crate::day_rules::POS_INFINITY;

#[derive(Clone)]
pub struct Period { pub start: i64, pub offset: i64, pub dst: bool, pub abbreviation: String }
impl Period { pub fn same_state(&self, other: &Self) -> bool { self.offset == other.offset && self.dst == other.dst && self.abbreviation == other.abbreviation } }
pub struct Timeline { pub periods: Vec<Period> }
impl Timeline {
    pub fn index_at(&self, time: i64) -> usize { self.periods.partition_point(|period| period.start <= time) - 1 }
    pub fn period_at(&self, time: i64) -> &Period { &self.periods[self.index_at(time)] }
    pub fn end_of(&self, index: usize) -> i64 { self.periods.get(index + 1).map(|period| period.start).unwrap_or(POS_INFINITY) }
    pub fn nearby(&self, low: i64, high: i64) -> std::ops::RangeInclusive<usize> { self.index_at(low - 57600)..=self.index_at(high + 57600) }
    pub fn candidates(&self, local: i64) -> Vec<usize> {
        self.nearby(local, local).filter(|&index| { let time = local - self.periods[index].offset; self.periods[index].start <= time && time < self.end_of(index) }).collect()
    }
    pub fn skipping_transition(&self, local: i64) -> usize {
        self.nearby(local, local).find(|&index| index > 0 && self.periods[index].start + self.periods[index - 1].offset <= local && local < self.periods[index].start + self.periods[index].offset).unwrap()
    }
}
