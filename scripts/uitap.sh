#!/bin/sh
# uitap [-f] <text>  - tap the best-matching view by text/content-desc.
#   exact match beats substring; clickable beats non-clickable; shorter beats longer.
#   -f = find only, print "x y label"
FIND=0
[ "$1" = "-f" ] && { FIND=1; shift; }
pat=$1
[ -z "$pat" ] && { echo "usage: uitap [-f] <text>" >&2; exit 2; }

XML=/data/local/tmp/ui.xml
REAL=/proc/1/root$XML
uidump >/dev/null 2>&1 || { echo "uitap: uidump failed" >&2; exit 1; }

hit=$(grep -o '<node[^>]*>' "$REAL" 2>/dev/null | awk -v pat="$pat" '
function attr(s,n,  re,v){ re=n"=\"[^\"]*\""; if(match(s,re)){v=substr(s,RSTART+length(n)+2,RLENGTH-length(n)-3); return v} return "" }
BEGIN{ best=-1 }
{
  t=attr($0,"text"); d=attr($0,"content-desc"); b=attr($0,"bounds"); cl=attr($0,"clickable")
  hay=(t!="")?t:d
  if(hay==""||b=="") next
  h=tolower(hay); p=tolower(pat)
  if(h==p) s=100; else if(index(h,p)>0) s=50; else next
  if(cl=="true") s+=10
  s -= length(hay)/1000
  if(s<=best) next
  tmp=b; gsub(/[^0-9-]/," ",tmp); n=split(tmp,a," ")
  k=0; for(i=1;i<=n;i++) if(a[i]!=""){k++; v[k]=a[i]}
  if(k<4) next
  best=s; bx=int((v[1]+v[3])/2); by=int((v[2]+v[4])/2); bl=hay
}
END{ if(best>=0) printf "%d %d %s\n", bx, by, bl }')
[ -z "$hit" ] && { echo "uitap: no view matching '$pat'" >&2; exit 3; }
x=$(echo "$hit" | cut -d' ' -f1); y=$(echo "$hit" | cut -d' ' -f2); label=$(echo "$hit" | cut -d' ' -f3-)
if [ "$FIND" = 1 ]; then echo "$x $y $label"; exit 0; fi
input tap "$x" "$y" && echo "tapped '$label' at $x,$y"
