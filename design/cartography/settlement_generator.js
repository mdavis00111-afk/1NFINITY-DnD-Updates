// Development-only original vector illustration source. No runtime dependency.
const ink="#20180f";
const line=(d,w=1.25,extra="")=>`<path d="${d}" fill="none" stroke="${ink}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" ${extra}/>`;
const poly=(d,fill="none",w=1.3)=>`<path d="${d}" fill="${fill}" stroke="${ink}" stroke-width="${w}" stroke-linejoin="round"/>`;
const dot=(x,y,r=1)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${ink}"/>`;
const tr=(s,x,y,k=1)=>`<g transform="translate(${x} ${y}) scale(${k})">${s}</g>`;
function house(v=0){let s=poly("M3 20L21 4 40 19 40 43 3 43Z")+poly("M21 4L48 10 59 24 40 19Z")+poly("M40 19L59 24 59 39 40 43Z")+line("M0 21L21 2 43 21M21 7L21 17M9 43V30H18V43M25 25H33V33H25Z M45 28L52 27 52 34 45 35Z");
for(let i=0;i<5;i++)s+=line(`M${25+i*4} ${7+i*.8}l10 13`,.65);for(let i=0;i<5;i++)s+=line(`M${43+i*3} 37l0 4`,.6);if(v%2)s+=poly("M43 9V0H49V11")+line("M42 1H50M6 22H36M5 37H8M20 37H37",.8);else s+=line("M7 25L36 41M7 41L36 25M21 22V43",.65);return s}
function tower(v=0){let s=poly("M8 14L33 14 33 50 8 50Z")+poly("M33 14L42 20 42 46 33 50Z")+poly("M5 14V7H11V11H16V5H22V11H27V6H33V11H36V14Z")+line("M17 50V39Q21 32 25 39V50M18 22H24V30H18Z M35 23L39 25V32L35 31Z");for(let i=0;i<5;i++)s+=line(`M${35+i} 34v${10-i*.5}`,.6);if(v%2)s+=line("M22 5V-5L34 -1 22 2",1);else s+=line("M9 35H15M26 35H33M9 20H14M27 20H32",.7);return s}
function spire(v=0){return poly("M4 28L18 7 32 28 32 61 4 61Z")+line("M18 7V0M14 3H22M9 28H27M15 35H21V44H15Z M12 61V51Q18 41 24 51V61")+poly("M32 43L48 33 63 43V61H32Z")+line("M48 33V61M38 48H44V54H38Z M52 48H58V54H52Z")+Array.from({length:5},(_,i)=>line(`M${35+i*5} ${42-i*.4}l4 7`,.65)).join("")+(v?line("M4 49H10M26 49H32M3 58H9M25 58H32",.8):"")}
function wall(w=112){let d=`M5 70V53`;for(let x=5;x<w-9;x+=9)d+=`h4v-5h5v5`;d+=`V72L5 72Z`;return poly(d)+line("M45 72V61Q53 48 61 61V72")+Array.from({length:11},(_,i)=>line(`M${8+i*8} 65l3 0m-1 3h4`,.65)).join("")}
function trees(v=0){return line("M8 26V8M8 4L0 16H4L0 22H16L12 16H16Z")+line("M27 28V6M27 1L17 14H22L16 23H38L33 14H37Z")}
function ground(v){let s="";for(let i=0;i<12;i++){let x=8+i*10+(v?i%3:0);let y=83+(i*7+v*3)%6;s+=line(`M${x} ${y}q4 -2 8 0`,.65)}return s}
function wave(y,x=4,w=118){let d=`M${x} ${y}`;for(let i=0;i<w/12;i++)d+="q3 -2 6 0t6 0";return line(d,.9)}
function boat(v){return poly("M4 32L55 32 46 42 15 42Z")+line("M27 32V1L9 27H27M29 5L49 29H29M8 36H51")+line("M10 44Q30 47 54 44M15 40L19 33M26 41L30 33M38 41L42 33",.65)}
function mill(v){let s=poly("M47 30L79 30 86 75H41Z")+line("M50 75V60Q62 47 73 60V75M48 30L63 18 78 30M63 13V47M46 30H81");let angle=v?30:43;for(let i=0;i<4;i++)s+=`<g transform="translate(63 30) rotate(${angle+i*90})">${poly("M-2 0L-5 -28 5 -28 3 0Z")}${line("M-3 -8H3M-4 -16H4M-5 -24H5M0 -28V0",.65)}</g>`;return s}
function farm(v){let s=tr(house(v),7,11,.75)+line("M52 41L111 20 123 65 60 79Z");for(let i=0;i<8;i++)s+=line(`M${54+i*7} ${40-i*2.5}l10 37`,.9);for(let i=0;i<4;i++)s+=line(`M${59+i*2} ${50+i*7}l58 -21`,.65);return s}
function bridge(v){let s=line("M5 61L28 43 98 43 123 61M5 66L29 50 97 50 123 66M16 61V76M112 61V76")+poly("M23 74V55L103 55V74H89V68Q78 52 67 68V74H56V68Q45 52 34 68V74Z");for(let x=29;x<102;x+=8)s+=line(`M${x} 56v5`,.8);if(v)s+=line("M29 43V33M98 43V33M29 33Q63 28 98 33M40 33V43M53 31V43M76 31V43M88 32V43");return s+wave(79)+wave(88)}
function dock(v){let s=tr(house(v),6,9,.78)+poly("M54 45L121 34 121 43 54 55Z")+poly("M75 48L85 48 85 83 75 83Z")+line("M53 55V70M121 43V61M78 52L82 52M77 61L84 61M77 70L84 70");for(let x=58;x<121;x+=8)s+=line(`M${x} ${44-(x-54)*.16}v9`,.7);return s+tr(boat(v),90,51,.55)+wave(88)}
function build(kind,v){let s="",H=(x,y,k=1)=>tr(house(v),x,y,k),T=(x,y,k=1)=>tr(tower(v),x,y,k),S=(x,y,k=1)=>tr(spire(v),x,y,k);switch(kind){
case "house":s=H(v?32:28,23,1.35)+(v?line("M13 81L26 66M102 77L116 65",.8):"");break;
case "cottage":s=H(22,29,1.15)+line("M20 54Q56 12 89 55M21 55Q55 19 87 56",1.2)+tr(trees(v),89,46,.7);break;
case "hamlet":s=v?H(6,29,.95)+H(62,22,.8)+H(47,52,.65):H(18,36,.8)+H(64,26,1)+tr(trees(v),2,49,.6);break;
case "village":s=v?H(5,28,.77)+H(52,12,.82)+H(77,38,.76)+H(29,51,.65):H(8,21,.8)+H(48,32,.9)+H(75,11,.7)+H(9,49,.6);break;
case "town":s=H(6,22,.78)+H(47,13,.8)+H(82,28,.7)+H(14,50,.65)+H(58,46,.74)+(v?T(92,8,.58):S(49,8,.64));break;
case "walled_town":s=H(10,15,.85)+H(62,17,.8)+T(2,32,.7)+T(93,30,.7)+wall(120)+(v?H(42,7,.7):S(41,0,.65));break;
case "city":s=H(3,24,.7)+H(33,10,.7)+H(69,25,.75)+H(83,12,.7)+H(11,47,.8)+H(53,43,.77)+H(85,47,.64)+(v?T(47,1,.75):S(47,1,.75));break;
case "capital":s=H(4,35,.8)+T(4,20,1)+T(85,17,1)+S(43,1,.9)+H(73,42,.75)+wall(120)+(v?line("M63 7V0L80 4 63 6"):T(29,23,.7));break;
case "port":case "harbour":s=dock(v)+H(6,2,.56)+(kind==="harbour"?tr(boat(v),58,58,.58)+line("M4 78L23 64 44 64",1.5):T(43,8,.55));break;
case "castle":s=T(8,20,1.02)+T(80,20,1.02)+T(43,0,1.12)+wall(120)+(v?line("M20 18V2L37 9 20 12"):line("M63 5L63 0 79 3 63 5"));break;
case "keep":s=T(38,10,1.4)+poly("M25 80V44L40 44V80Z")+poly("M86 44L101 44V80H86Z")+(v?line("M28 44V35H36V44M91 44V35H99V44"):line("M38 25L84 25"));break;
case "fortress":s=T(1,29,1)+T(85,29,1)+wall(120)+T(42,7,1.05)+(v?line("M1 83L21 78 111 78 127 83"):line("M21 55H42M83 55H91"));break;
case "watchtower":s=T(43,7,1.5)+line("M23 80L39 69M96 69L111 80")+(v?line("M51 7L66 -1 82 7"):line("M54 6H91"));break;
case "guard_post":s=T(45,19,1.1)+H(v?4:75,42,.7)+line("M8 82H120");break;
case "inn":case "tavern":s=H(10,23,1.4)+line("M93 37V75M93 38H117")+poly("M98 41H118V57H98Z")+line(kind==="inn"?"M101 49H114M101 46V53M113 46V53":"M102 44H112V53H102Z M112 46Q120 46 115 50")+(v?H(72,40,.75):"");break;
case "church":s=S(26,11,1.15);break;
case "cathedral":s=S(10,7,1.05)+S(55,3,1.1)+line("M49 53H74M45 75H80M61 46a8 8 0 1 0 .1 0M61 46V62M53 54H69")+(v?line("M8 72H119M8 77H119"):"");break;
case "temple":s=poly("M13 32L64 8 115 32Z")+poly("M15 36H113V41H15Z M12 76H116V82H12Z M8 82H120V87H8Z")+line("M24 41V76M31 41V76M43 41V76M50 41V76M63 41V76M70 41V76M83 41V76M90 41V76M101 41V76M108 41V76")+(v?line("M48 27L64 19 80 27M58 41V76"):dot(64,26,4));break;
case "shrine":s=poly("M40 47L64 22 88 47V75H40Z")+line("M64 22V11M57 15H71M51 75V58Q64 43 77 58V75M30 76H99M37 81H91")+(v?tr(trees(v),7,49,.65):line("M17 74L28 54 34 74M100 73L111 53 119 73"));break;
case "monastery":s=S(39,5,.95)+H(4,30,.78)+H(83,27,.7)+wall(120)+(v?line("M10 78H118M26 72V83M101 72V83"):"");break;
case "windmill":s=mill(v);break;
case "watermill":s=H(7,17,1.2)+`<circle cx="89" cy="64" r="23" fill="none" stroke="${ink}" stroke-width="1.8"/>`+`<circle cx="89" cy="64" r="16" fill="none" stroke="${ink}"/>`+Array.from({length:v?10:8},(_,i)=>line(`M89 64L${(89+23*Math.cos(i*2*Math.PI/(v?10:8))).toFixed(2)} ${(64+23*Math.sin(i*2*Math.PI/(v?10:8))).toFixed(2)}`,.9)).join("")+wave(87);break;
case "farm":s=farm(v);break;
case "fields":s=line("M7 33L72 15 119 39 57 76Z M7 33L57 76M72 15L57 76");for(let i=1;i<8;i++)s+=line(`M${7+i*8} ${33-i*2.3}L${57+i*7} ${76-i*4.7}`,.9);if(v)s+=line("M11 44L51 80M79 13L122 35");break;
case "blacksmith":s=H(7,21,1.15)+poly("M79 59H119L111 65H102L101 74H111V79H83V74H94V65H86Z")+line("M91 51L106 37M100 34L112 43M37 16V5H45V16")+(v?line("M41 4q-10 -7 0 -11"):line("M43 2q7 -8 -2 -10"));break;
case "trading_post":s=H(8,20,1.1)+poly("M75 45L112 45 121 60H66Z")+line("M71 60V79M116 60V79M70 69H117M80 46L75 60M90 46L89 60M101 46L105 60")+(v?line("M82 72h22v8H82Z"):line("M73 72h10v8H73Z M96 72h12v8H96Z"));break;
case "bridge":s=bridge(v);break;
case "dock":s=dock(v);break;
case "lighthouse":s=poly("M47 29H81L88 74H40Z")+poly("M43 29V13H85V29Z M37 13L64 3 91 13Z")+line("M49 13V29M59 13V29M70 13V29M80 13V29M60 74V60H69V74M49 40H56V48H49Z M73 40H80V48H73Z M32 17L9 9M93 17L119 9")+poly("M26 83L41 74 88 74 104 83Z")+(v?wave(88):line("M47 33L81 33M46 53L84 53"));break;
default:throw Error(kind)}
return s+ground(v)}
export const kinds=["house","cottage","hamlet","village","town","walled_town","city","capital","port","harbour","castle","keep","fortress","watchtower","guard_post","inn","tavern","church","cathedral","temple","shrine","monastery","windmill","watermill","farm","fields","blacksmith","trading_post","bridge","dock","lighthouse"];
export {build};
