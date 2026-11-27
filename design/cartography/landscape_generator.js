// Development-only original vector illustration source, no game runtime dependency.
const ink="#20180f";
const L=(d,w=1.2,extra="")=>`<path d="${d}" fill="none" stroke="${ink}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" ${extra}/>`;
const P=(d,fill="none",w=1.4)=>`<path d="${d}" fill="${fill}" stroke="${ink}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
const C=(x,y,r=1)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${ink}"/>`;
const G=(s,x,y,k=1)=>`<g transform="translate(${x} ${y}) scale(${k})">${s}</g>`;
const seq=(n,f)=>Array.from({length:n},(_,i)=>f(i)).join("");
function grass(v=0){return L(v?"M0 14Q4 6 3 0M7 14Q12 6 16 5M7 14L8 3":"M0 14L5 6 6 14 13 0 11 14 18 7",1.1)+L("M0 16q8 -2 17 0",.65)}
function pine(v=0){let s=P(v?"M18 0L5 19H12L2 31H9L0 43H36L26 31H33L24 19H30Z":"M17 1L4 20 11 18 2 32 10 30 0 44 17 40 36 44 25 30 33 32 23 19 30 20Z")+L("M17 12V49M17 21l-10 8m10 -1l-12 10m12 -4l13 7m-13 -17l9 5",.8);return s+L("M15 49H20M0 46L9 44M29 44L37 46",.7)}
function decid(v=0){return P(v?"M17 5Q8 -1 5 9Q-3 11 2 20Q-4 30 7 34Q9 44 20 38Q31 43 34 33Q44 30 37 20Q40 10 30 8Q26 -2 17 5Z":"M16 4Q9 0 7 9Q0 7 1 18Q-3 27 6 30Q4 41 16 37Q21 45 28 36Q39 39 38 29Q45 22 36 15Q38 7 29 8Q24 0 16 4Z")+L("M19 48V24M19 34L9 24M19 28L29 17M19 39L31 30M12 48H25",1.3)+L("M4 19q2 -4 6 -5m21 5q4 3 5 8M8 33l5 -4",.7)}
function dead(v=0){return L("M20 49L18 22 23 2M18 27L5 16 0 3M5 16L13 8M18 32L31 20 37 5M31 20L39 17M19 43L8 35 4 26M20 49L12 52M20 49L29 52",1.8)+(v?L("M23 2L31 7M18 22L27 11M9 17L1 19",.8):L("M24 27L30 27M4 7L10 3",.8))}
function palm(v=0){return L("M18 49Q25 30 18 12M20 49Q28 29 20 12",1.4)+P("M19 12Q2 0 0 14Q8 6 19 12Q7 15 4 26Q12 18 19 12Q21 -2 34 2Q29 7 19 12Q37 6 40 18Q29 12 19 12Q31 18 29 30Q25 20 19 12Z")+seq(5,i=>L(`M${20+i*.3} ${23+i*5}l4 -1`,.7))}
function peak(v=0){const top=v?43:36;let s=P(`M0 62L14 46 20 49 ${top} 3 57 31 66 24 94 62Z`)+L(`M${top} 3L${top+1} 25 29 43 22 58M${top+1} 25L51 36 48 44 65 58M66 24L69 43 83 58`,1);for(let i=0;i<8;i++)s+=L(`M${top+3+i*2.4} ${28+i*3}l${6+i*.8} ${8+i*.5}`,.75);s+=L("M6 59l7 -6m4 8l6 -8m49 10l6 -7",.65);return s}
function hill(v=0){return L(v?"M0 48Q16 22 32 27Q47 10 63 29Q74 35 91 48":"M0 48Q21 9 41 32Q64 3 92 48",1.5)+L("M15 47q10 -15 20 -12M40 47q11 -16 24 -12M65 46q10 -8 16 -2",.8)+seq(7,i=>L(`M${40+i*4} ${36+i*.7}l4 8`,.65))}
function marks(v,n=12){return seq(n,i=>{let x=5+(i*31+v*17)%115,y=12+(i*19+v*11)%72;return L(`M${x} ${y}q2 -2 5 0`,.65)})}
function waves(v=0,n=8){return seq(n,i=>{let y=10+i*10,x=4+(i*13+v*9)%24;return L(`M${x} ${y}q8 -3 16 0t16 0t16 0m6 0q7 -3 14 0t14 0`,.85)})}
function reeds(v=0){return L("M0 21L5 9 8 21 11 0 13 21 20 8 18 21M11 0V-3M20 8v-3",.9)+P("M10 0V-5H12V0Z M19 7V2H21V7Z",ink,.5)}
function cliff(v=0){let s=P("M3 29L21 11 43 16 55 8 84 15 112 11 125 29 119 75 101 72 84 85 59 77 37 84 16 73 3 75Z")+L("M3 29L24 34 40 26 60 36 85 29 103 35 125 29",1.6);for(let i=0;i<14;i++){let x=8+i*8,y=32+(i*3)%8;s+=L(`M${x} ${y}l${i%2?-3:2} ${32+(i*7)%14}m1 -6l2 8`,.85)}if(v)s+=L("M23 34L19 57 26 73M61 36L56 55 64 77M103 35L98 57 101 72",1.5);return s}
function dune(v=0){return L(v?"M4 55Q34 15 65 36T124 51M9 60Q41 30 62 48T119 55":"M4 52Q28 14 59 29Q83 40 123 48M9 61Q30 33 64 44Q91 54 121 53",1.5)+seq(12,i=>L(`M${22+i*7} ${48+(i*3)%15}l6 2`,.65))}
function rock(v=0){return P(v?"M1 35L8 12 25 2 44 13 50 35Z":"M0 35L11 10 28 1 38 14 50 35Z")+L("M27 4L21 19 32 35M21 19L9 28M38 14L38 32",.85)+seq(5,i=>L(`M${31+i*3} ${18+i*2}l2 8`,.6))}
function forest(v,tree,n=5){let coords=v?[[8,16,.8],[38,3,.95],[68,18,.8],[89,4,.9],[25,42,.75],[64,47,.78]]:[[2,29,.85],[25,4,1],[57,16,.9],[84,5,.95],[93,43,.7],[44,45,.8]];return coords.slice(0,n).map(([x,y,k],i)=>G(tree((v+i)%2),x,y,k)).join("")}
function terrain(kind,v){let s="";
switch(kind){
case "plains":s=marks(v,19)+seq(5,i=>G(grass(v),8+i*23,30+(i*9)%35,.65));break;
case "grasslands":s=seq(11,i=>G(grass((v+i)%2),4+(i*23+v*8)%109,10+(i*17)%62,.65+(i%3)*.16));break;
case "rolling_hills":s=G(hill(v),1,12,1.25)+G(hill(1-v),30,42,1)+marks(v,9);break;
case "mountain_peak":s=G(peak(v),9,6,1.17)+marks(v,8);break;
case "mountain_range":s=G(peak(v),2,10,.86)+G(peak(1-v),46,7,.86)+G(peak(v),29,36,.83);break;
case "snow_mountain":s=G(peak(v),7,5,1.2)+L(v?"M39 44L47 35 54 40 60 33 66 43M56 27L52 22":"M31 42L39 31 46 38 52 30 59 45 65 40",1.3)+seq(7,i=>L(`M${20+i*11} ${79+(i%2)*5}l6 -1`,.6));break;
case "mountain_pass":s=G(peak(v),0,6,.72)+G(peak(1-v),70,5,.6)+L("M61 82Q47 68 63 55T61 29M72 82Q56 67 72 55T68 29",1.1,"stroke-dasharray=\"4 3\"");break;
case "cliff":s=cliff(v);break;
case "valley":s=G(hill(v),0,0,.7)+G(hill(1-v),66,0,.67)+L("M4 39Q31 81 62 85Q92 80 124 39M6 34Q32 64 63 73Q90 65 122 34",1.5)+seq(8,i=>L(`M${7+i*5} ${42+i*3}l-3 9M${120-i*5} ${42+i*3}l3 9`,.7));break;
case "ravine":s=L(v?"M8 4L34 23 21 43 49 63 37 92M35 4L55 21 42 43 70 63 56 92":"M32 3L21 24 51 44 35 68 52 92M51 3L42 24 71 44 55 68 72 92",1.8)+seq(12,i=>L(`M${v?12+(i%3)*7:27+(i%3)*8} ${10+i*7}l8 4`,.8))+G(rock(v),83,43,.65);break;
case "canyon":s=G(cliff(v),0,0,.92)+L("M12 90Q40 62 63 80T124 69M20 93Q43 72 65 88T124 77",1.4)+seq(6,i=>L(`M${15+i*18} 79l4 4`,.7));break;
case "plateau":s=P("M7 39L24 17 101 17 121 39 109 80H19Z")+L("M7 39H121M24 17L34 28H91L101 17",1.3)+seq(13,i=>L(`M${10+i*8} 40l${i%3-1} 32`,.8));if(v)s+=L("M40 19L40 27M70 19L70 28M80 39V78",.9);break;
case "deciduous_forest":s=forest(v,decid,5);break;
case "pine_forest":s=forest(v,pine,5);break;
case "dense_forest":s=forest(v,pine,6)+G(decid(v),48,51,.65)+G(decid(1-v),5,50,.65);break;
case "dead_forest":s=forest(v,dead,5)+marks(v,10);break;
case "jungle":s=forest(v,palm,5)+G(decid(v),40,43,.7)+seq(5,i=>G(grass(v),10+i*24,75,.65));break;
case "swamp":s=waves(v,6)+G(dead(v),15,18,1)+G(decid(v),75,19,.86)+seq(5,i=>G(reeds(v),5+i*24,65+(i%2)*7,.75));break;
case "marsh":s=waves(v,7)+seq(9,i=>G(reeds((v+i)%2),3+(i*23)%109,12+(i*17)%58,.65));break;
case "desert":s=dune(v)+G(rock(v),75,45,.5)+seq(25,i=>C(3+(i*29)%121,10+(i*17)%75,.45));break;
case "dunes":s=G(dune(v),0,0,1)+G(dune(1-v),2,30,.98);break;
case "tundra":s=G(hill(v),9,5,1.1)+seq(6,i=>G(grass(v),5+i*20,67+(i%3)*4,.7))+L("M2 48L17 47M32 54H47M71 55H88M105 58H123",.8);break;
case "glacier":s=P("M10 8L43 4 75 10 113 6 121 45 103 81 77 91 53 82 31 90 4 62Z")+L("M25 8L33 29 25 43 40 67 35 86M67 8L55 31 74 49 59 78M104 8L92 28 103 43 90 65 94 84",1.3)+seq(13,i=>L(`M${13+i*8} ${18+(i*7)%50}l6 -5`,.65));if(v)s+=L("M17 38L49 48M73 58L112 54",.9);break;
case "volcano":s=P("M2 84L22 57 42 21 54 17 72 17 83 23 102 60 126 84Z")+L("M42 21Q63 32 83 23M52 27L43 54 19 80M73 28L70 54 89 82M62 30L64 60 50 83",1.35)+seq(10,i=>L(`M${29+i*7} ${58+(i%3)*4}l${i<5?-6:6} 15`,.8))+L(v?"M58 18Q42 10 52 3Q68 8 74 2Q91 8 79 16":"M59 17Q40 9 49 3Q60 9 65 2Q83 3 84 12Q82 18 72 18",1.1);break;
case "beach":s=L("M9 3Q25 22 37 29T69 50Q95 61 120 92M5 10Q23 29 32 35T65 56Q93 67 112 94",1.4)+seq(8,i=>L(`M${42+i*9} ${9+i*4}q6 -2 11 0`,.7))+seq(20,i=>C(5+(i*17)%80,35+(i*11)%53,.5));break;
case "rocky_coast":s=L("M9 1L20 18 15 29 34 40 27 51 49 56 58 72 86 70 98 93M4 4L12 19 7 29 24 42 19 53 42 61 53 80 80 78 91 95",1.4)+G(rock(v),63,11,.85)+G(rock(1-v),80,55,.8)+L("M30 3l6 4m-1 9l8 4m17 28l12 3",.7);break;
default:throw Error(kind)}
return s}
function boat(v=0){return P("M4 51L81 51 67 67 23 67Z")+L("M36 51V4M60 51V18M36 7L10 47H36M39 13L61 48H39M61 18L77 45H61M9 56H75",1.35)+seq(7,i=>L(`M${22+i*7} 65l4 -12`,.75))+(v?L("M36 4L52 9 36 13M60 18L74 23 60 27"):L("M36 4L24 8 36 12"))}
function water(kind,v){let s="";
switch(kind){
case "ocean":s=waves(v,8)+L("M6 84Q26 65 45 84M79 22Q99 4 121 22",1.2);break;
case "sea":s=waves(v,8)+L("M30 46Q42 32 55 46M72 75Q86 62 101 75",1.2);break;
case "lake":s=P(v?"M9 47Q2 28 22 19Q40 6 58 17Q87 2 108 23Q130 38 115 57Q122 77 93 85Q70 74 49 89Q25 83 17 67Z":"M8 45Q3 26 27 22Q37 4 61 14Q91 6 112 31Q130 57 107 68Q93 89 68 78Q43 94 21 72Q2 67 8 45Z")+L("M20 47q18 -4 35 0t35 0M31 60q14 -3 30 0t29 0M40 32q15 -3 29 0",.9)+G(reeds(v),10,35,.8);break;
case "pond":s=P(v?"M28 55Q18 35 39 26Q62 13 84 27Q110 41 90 58Q69 79 41 65Z":"M25 50Q24 32 49 25Q73 16 96 37Q108 54 84 67Q53 78 25 50Z")+L("M43 45q12 -2 25 0M52 55q10 -2 20 0",.8)+G(reeds(v),12,45,.65)+G(reeds(1-v),96,41,.65);break;
case "river":s=L(v?"M21 0Q52 20 36 43T72 69T109 96M35 0Q67 20 50 43T86 69T123 96":"M4 4Q43 17 30 39T62 66T105 93M17 4Q56 17 43 39T75 66T118 93",1.5)+L("M35 30l4 2M47 53l5 3M79 78l4 2",.7);break;
case "stream":s=L(v?"M10 0Q39 22 29 34T69 65T118 96M15 0Q44 22 34 34T74 65T123 96":"M0 6Q30 15 26 38T57 63T105 94M6 4Q36 15 32 38T63 63T111 94",1)+G(rock(v),69,12,.5)+G(reeds(v),12,65,.6);break;
case "waterfall":s=G(cliff(v),0,0,1)+L("M39 4Q58 19 72 17L73 68Q74 78 88 83M48 4Q65 10 83 12L81 68Q86 79 98 84M55 12L54 67M64 16L63 75M76 19L72 73",1.4)+L("M33 85q12 -7 24 0t25 0t25 0M22 91q18 -5 35 0t37 0",1);break;
case "spring":s=P("M8 44L24 19 44 12 63 27 85 17 117 45 103 59H23Z")+L("M48 37Q59 26 69 37Q75 50 63 54Q47 53 48 37M64 54Q47 67 65 77T108 93M70 54Q55 67 73 77T117 93",1.3)+G(reeds(v),16,64,.75);break;
case "island":s=P(v?"M12 60L25 29 55 16 70 28 98 20 116 57 93 76 57 84 20 75Z":"M10 58Q25 20 51 27L70 12 101 35 118 65 91 82 53 79 23 84Z")+G(palm(v),46,22,.82)+G(rock(v),76,44,.58)+L("M5 69q15 16 35 18M92 85q19 -2 32 -13",.8);break;
case "archipelago":s=G(rock(v),9,13,.75)+G(rock(1-v),75,5,.78)+G(rock(v),48,44,.66)+G(rock(1-v),91,55,.65)+waves(v,5);break;
case "reef":s=waves(v,6)+seq(9,i=>G(rock((i+v)%2),5+(i*27)%100,13+(i*19)%62,.25+(i%3)*.08))+L("M7 80Q39 67 64 84T122 77",.7,"stroke-dasharray=\"2 3\"");break;
case "shipwreck":s=G(boat(v),20,9,.96)+L("M56 24L75 4M60 46L89 27M18 57L52 65 38 74M81 52L105 74M39 77L21 89M80 78L95 89",1.7)+waves(v,2);break;
case "ship":s=G(boat(v),19,8,1.12)+L("M9 87Q30 82 48 87T90 87T120 87",.9);break;
case "boat":s=P(v?"M19 47Q57 27 108 47L87 69 41 69Z":"M13 47L111 47Q98 70 64 74Q30 70 13 47Z")+L("M29 53H95M39 63H85M63 47V18L86 41H63M23 79l63 -62M37 88l63 -62",1.2)+L("M5 83q12 -4 24 0m64 3q12 -4 24 0",.8);break;
default:throw Error(kind)}return s}
export const families={"terrain":["plains","grasslands","rolling_hills","mountain_peak","mountain_range","snow_mountain","mountain_pass","cliff","valley","ravine","canyon","plateau","deciduous_forest","pine_forest","dense_forest","dead_forest","jungle","swamp","marsh","desert","dunes","tundra","glacier","volcano","beach","rocky_coast"],"water":["ocean","sea","lake","pond","river","stream","waterfall","spring","island","archipelago","reef","shipwreck","ship","boat"]};
export {terrain,water};
