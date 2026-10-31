use crate::dataset::Point;

pub struct Grid {
    pub side: i64,
    pub count: usize,
    pub cells: Vec<Vec<Point>>,
}

impl Grid {
    pub fn new(world: i64, side: i64) -> Self {
        let count = (world / side) as usize;
        Self { side, count, cells: vec![Vec::new(); count * count] }
    }

    fn index(&self, point: Point) -> usize {
        (point.y / self.side) as usize * self.count + (point.x / self.side) as usize
    }

    pub fn insert(&mut self, point: Point) {
        let i = self.index(point);
        let j = self.cells[i].binary_search_by_key(&point.id, |p| p.id).unwrap_err();
        self.cells[i].insert(j, point);
    }

    pub fn delete(&mut self, point: Point) {
        let i = self.index(point);
        self.cells[i].retain(|p| p.id != point.id);
    }
}
