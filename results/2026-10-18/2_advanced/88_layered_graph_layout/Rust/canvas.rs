pub struct Canvas{
    pub main:usize,
    pub direction:String,
    pub rows:usize,
    pub columns:usize,
    lines:Vec<Vec<u8>>,
    arrows:Vec<Vec<Option<char>>>,
    boxes:Vec<Vec<Option<char>>>,
    highlight:Vec<Vec<bool>>
}
impl Canvas{
    pub fn new(main:usize,secondary:usize,direction:&str)->Self{
        let vertical=direction=="TB"||direction=="BT";
        let(rows,columns)=if vertical{
            (main,secondary)
        }else{
            (secondary,main)
        };
        Self{
            main,
            direction:direction.into(),
            rows,
            columns,
            lines:vec![vec![0;columns];rows],
            arrows:vec![vec![None;columns];rows],
            boxes:vec![vec![None;columns];rows],
            highlight:vec![vec![false;columns];rows]
        }
    }
    pub fn map(&self,m:usize,c:usize)->(usize,usize){
        let m=if self.direction=="BT"||self.direction=="RL"{
            self.main-1-m
        }else{
            m
        };
        if self.direction=="TB"||self.direction=="BT"{
            (m,c)
        }else{
            (c,m)
        }
    }
    pub fn line(&mut self,m:usize,c:usize,main:bool){
        let(row,column)=self.map(m,c);
        let vertical=self.direction=="TB"||self.direction=="BT";
        self.lines[row][column]|=if main==vertical{
            1
        }else{
            2
        };
    }
    pub fn corner(&mut self,m:usize,c:usize){
        let(row,column)=self.map(m,c);
        self.lines[row][column]|=4;
    }
    pub fn arrow(&mut self,m:usize,c:usize,reversed:bool){
        let(row,column)=self.map(m,c);
        let a=match(self.direction.as_str(),reversed){
            ("TB",false)|("BT",true)=>'v',("TB",true)|("BT",false)=>'^',("LR",false)|("RL",true)=>'>',_=>'<'
        };
        self.arrows[row][column]=Some(a);
    }
    pub fn highlight(&mut self,row:usize,column:usize){
        self.highlight[row][column]=true;
    }
    pub fn label(&mut self,row:usize,column:usize,label:&str){
        for(i,c)in label.chars().enumerate(){
            self.boxes[row][column+i]=Some(c);
        }
    }
    pub fn crossings(&self)->usize{
        self.lines.iter().flat_map(|r|r.iter()).filter(|&&c|c&3==3).count()
    }
    pub fn report(&self)->Vec<String>{
        let mut lines=vec![format!("    {}",(0..self.columns).map(|c|(b'0'+(c%10)as u8)as char).collect::<String>())];
        for row in 0..self.rows{
            let mut line=format!("{:3} ",row);
            for column in 0..self.columns{
                let bits=self.lines[row][column];
                let c=if let Some(c)=self.boxes[row][column]{
                    c
                }else if let Some(c)=self.arrows[row][column]{
                    c
                }else if self.highlight[row][column]{
                    '#'
                }else{
                    match bits{
                        0=>' ',1=>'|',2=>'-',_=>'+'
                    }
                };
                line.push(c);
            }
            lines.push(line.trim_end().to_string());
        }
        lines
    }
}
