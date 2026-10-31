package main

import (
 "bufio"
 "fmt"
 "os"
)
func writePPM(image []RGB,width,height int) {
 file,e:=os.Create("output/image.ppm"); if e!=nil { panic(e) }; writer:=bufio.NewWriter(file); fmt.Fprintf(writer,"P3\n%d %d\n255\n",width,height)
 for y:=0;y<height;y++ { for x:=0;x<width;x++ { if x>0 { fmt.Fprint(writer," ") }; p:=image[y*width+x]; fmt.Fprintf(writer,"%d %d %d",p[0],p[1],p[2]) }; fmt.Fprintln(writer) }; if e:=writer.Flush(); e!=nil { panic(e) }; file.Close()
}
func writePreview(image []RGB,width,height int) { file,e:=os.Create("output/preview.txt"); if e!=nil { panic(e) }; writer:=bufio.NewWriter(file); ramp:="@%#*+=-:,."; for y:=0;y<height;y+=4 { for x:=0;x<width;x+=2 { total:=0; for j:=0;j<4;j++ { for i:=0;i<2;i++ { p:=image[(y+j)*width+x+i]; total+=299*p[0]+587*p[1]+114*p[2] } }; writer.WriteByte(ramp[(total/8000)*10/256]) }; writer.WriteByte('\n') }; if e:=writer.Flush(); e!=nil { panic(e) }; file.Close() }
