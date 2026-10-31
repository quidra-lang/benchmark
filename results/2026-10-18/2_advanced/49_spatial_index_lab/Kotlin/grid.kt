object Grid {
    class Cell(val x: Int,val y: Int) {
        val points=mutableListOf<Dataset.Obj>()
    }
    class Index(world: Int,val size: Int) {
        val count=world/size;
        val cells=(0 until count).flatMap {
            y->(0 until count).map {
                x->Cell(x,y)
            }
        };
        fun cell(point: Dataset.Obj)=cells[(point.box.y1/size).toInt()*count+(point.box.x1/size).toInt()];
        fun insert(point: Dataset.Obj) {
            val cell=cell(point);
            cell.points+=point;
            cell.points.sortBy {
                it.id
            }
        };
        fun delete(point: Dataset.Obj) {
            cell(point).points.removeAll {
                it.id==point.id
            }
        }
    }
}
