use crate::dataset::Point;

pub const NAMES: [&str; 4] = ["NW", "NE", "SW", "SE"];

pub struct Node {
    pub x: i64,
    pub y: i64,
    pub size: i64,
    pub points: Vec<Point>,
    pub children: Vec<Node>,
}

impl Node {
    pub fn new(x: i64, y: i64, size: i64) -> Self {
        Self { x, y, size, points: Vec::new(), children: Vec::new() }
    }

    pub fn destination(&self, point: Point) -> usize {
        usize::from(point.x >= self.x + self.size / 2) + 2 * usize::from(point.y >= self.y + self.size / 2)
    }

    pub fn insert(&mut self, point: Point, bucket: usize) {
        if self.children.is_empty() {
            let index = self.points.binary_search_by_key(&point.id, |p| p.id).unwrap_err();
            self.points.insert(index, point);
            if self.points.len() > bucket {
                let h = self.size / 2;
                self.children = vec![Self::new(self.x, self.y, h), Self::new(self.x + h, self.y, h),
                    Self::new(self.x, self.y + h, h), Self::new(self.x + h, self.y + h, h)];
                let points = std::mem::take(&mut self.points);
                for point in points { self.insert(point, bucket); }
            }
        } else {
            let child = self.destination(point);
            self.children[child].insert(point, bucket);
        }
    }

    pub fn delete(&mut self, point: Point, bucket: usize) {
        if self.children.is_empty() {
            self.points.retain(|p| p.id != point.id);
        } else {
            let child = self.destination(point);
            self.children[child].delete(point, bucket);
            if self.children.iter().all(|c| c.children.is_empty()) && self.children.iter().map(|c| c.points.len()).sum::<usize>() <= bucket {
                self.points = self.children.iter().flat_map(|c| c.points.iter().copied()).collect();
                self.points.sort_by_key(|p| p.id);
                self.children.clear();
            }
        }
    }
}
