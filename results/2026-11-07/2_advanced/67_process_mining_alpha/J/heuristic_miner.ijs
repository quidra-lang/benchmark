dependency =: 4 : 0
 'a b' =. y
 ab =. (<a,b){x
 ba =. (<b,a){x
 (x:ab-ba)%x:1+ab+ba
)
loop_measure =: 3 : '(x:y)%x:1+y'
branch_measure =: 3 : 0
 'f a b c join' =. y
 top =. ((<b,c){f)+(<c,b){f
 if. join do. bottom =. 1+((<b,a){f)+(<c,a){f
 else. bottom =. 1+((<a,b){f)+(<a,c){f end.
 (x:top)%x:bottom
)
