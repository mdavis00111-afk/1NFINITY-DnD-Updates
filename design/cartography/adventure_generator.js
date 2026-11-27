// Development-only original vector illustration source, no game runtime dependency.
const ink="#20180f";
const L=(d,w=1.3,extra="")=>`<path d="${d}" fill="none" stroke="${ink}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" ${extra}/>`;
const P=(d,fill="none",w=1.3)=>`<path d="${d}" fill="${fill}" stroke="${ink}" stroke-width="${w}" stroke-linejoin="round"/>`;
const C=(x,y,r=1,fill=ink)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}"/>`;
const G=(s,x,y,k=1)=>`<g transform="translate(${x} ${y}) scale(${k})">${s}</g>`;
const seq=(n,f)=>Array.from({length:n},(_,i)=>f(i)).join("");
function base(v){return seq(13,i=>L(`M${4+i*9} ${84+(i*7+v*2)%6}q3 -2 7 0`,.65))}
function rock(v){return P(v?"M2 30L12 7 24 3 40 12 49 30Z":"M2 30L10 10 28 1 39 13 49 30Z")+L("M26 5L19 18 31 29M19 18L9 23M38 15L40 29",.9)+seq(5,i=>L(`M${30+i*3} ${16+(i%3)*4}l3 7`,.6))}
function arch(v=0){let s=P(v?"M6 67V30Q9 2 40 3Q71 2 76 30V67H57V31Q56 19 40 18Q24 19 24 31V67Z":"M5 67V31Q5 4 40 3Q75 4 75 31V67H56V33Q55 20 40 19Q25 20 25 33V67Z");s+=L("M6 52H24M6 41H24M6 30H24M56 52H75M56 41H75M56 30H75M13 12L24 24M28 5L33 19M51 5L47 19M67 13L57 24",.8)+seq(5,i=>L(`M${8+i*3} 58v7M${59+i*3} 58v7`,.55));return s}
function cave(v=0){let s=P(v?"M2 77L13 54 20 28 35 14 49 18 67 3 84 14 92 37 107 42 125 77Z":"M2 77L15 43 32 20 45 13 62 4 79 15 93 24 107 53 126 77Z")+P(v?"M41 77Q32 57 50 41L64 29Q85 38 87 57L91 77Z":"M34 77Q29 56 47 34Q62 21 76 32Q94 46 92 77Z",ink)+L("M15 43L30 54 19 72M32 20L45 36M62 6L59 24M79 15L75 28M93 25L85 42 104 58M107 53L111 73",1)+seq(12,i=>L(`M${7+i*10} ${64+(i%3)*3}l${i%2?4:-4} 9`,.7));return s}
function tent(v=0){let s=P(v?"M2 45L31 2 61 45Z M31 2L76 19 89 46H61Z":"M3 45L31 2 60 45Z M31 2L73 16 88 45H60Z")+L("M31 2V45M31 20L18 45M31 20L45 45M4 45L0 50M86 44L91 50M42 8L72 42",1.1)+seq(5,i=>L(`M${48+i*6} ${18+i*2}l-4 18`,.65));return s}
function grave(v=0){return P(v?"M5 28V9Q14 -4 24 9V28Z":"M5 28V7H24V28Z")+L("M14 5V21M8 12H20M0 29H29M4 33H24",1)+L("M7 25l3 -4m11 0l2 4",.65)}
function obelisk(v=0){return P(v?"M14 1L25 14 28 65H2L6 14Z":"M14 0L24 13 28 65H2L5 13Z")+L("M14 2V64M5 13H24M5 43H27",.8)+seq(5,i=>L(`M${16+i*.8} ${22+i*7}l6 4`,.7))}
function tower(v=0){let s=P(v?"M5 66V17L9 17V6H16V16H23V9H29V14H35V66Z":"M5 66V17L5 9H12V16H19V5H25V15H34V8H40V66Z")+L("M14 66V53Q20 43 26 53V66M13 28H23V40H13Z M6 46H13M28 46H35",1)+seq(6,i=>L(`M${30+i*.8} ${21+i*6}l2 4`,.6));return s}
function broken_house(v=0){return P(v?"M5 65V38L20 19 29 33 44 24 56 38V65Z":"M4 65V38L29 14 35 23 39 21 56 39V65Z")+L("M12 65V48H23V65M33 45H45V55H33Z M6 40L56 40M28 14L28 33M10 38L20 28M38 31L50 39",.9)+seq(6,i=>L(`M${8+i*8} 58l4 3`,.65))}
function circleRing(v){let s=L("M13 56Q11 32 64 22Q111 30 115 55Q112 82 64 87Q15 81 13 56Z",.8,"stroke-dasharray=\"3 5\"");let pts=v?[[15,43],[34,25],[63,20],[89,26],[108,46],[92,69],[63,76],[32,68]]:[[13,49],[31,29],[61,20],[92,29],[112,49],[91,69],[61,77],[29,69]];for(let i=0;i<pts.length;i++)s+=G(obelisk(i%2),pts[i][0]-5,pts[i][1]-14,.32+(i%3)*.04);return s}
function fire(v=0){return L("M0 28L31 28M4 32L26 24M7 24L28 32",1.4)+P(v?"M7 23Q3 13 14 7Q12 18 20 14Q25 7 20 0Q34 12 24 23Z":"M7 23Q3 10 14 3Q12 16 18 17Q23 13 24 5Q33 16 24 23Z")+L("M14 22Q13 17 19 13Q23 19 21 23",.8)}
function well(v=0){let s=P("M15 48Q15 32 64 32Q113 32 113 48V74Q110 87 64 87Q18 87 15 74Z")+L("M15 48Q17 62 64 62Q111 62 113 48M23 48Q28 39 64 39Q100 39 106 48Q99 54 64 54Q29 54 23 48M29 58V78M47 62V85M81 61V85M98 58V78",1.05);if(v)s+=L("M28 32V8M100 32V8M22 8H106M64 8V37M58 36H70V43H58Z",1.5);else s+=P("M18 26L63 3 110 26Z")+L("M28 26V40M99 26V40M64 27V39M30 16L100 26",1);return s}
function adventure(kind,v){let s="";switch(kind){
case "cave":s=cave(v);break;
case "cavern":s=cave(v)+L("M15 46L25 35M24 43L33 29M93 45L100 58M47 80l5 -10m12 10l4 -8m14 8l2 -11",1.05);break;
case "mine":s=cave(v)+L("M27 77V43H100V77M35 77V50H92V77M28 43L35 50M100 43L92 50M51 80L40 94M73 80L84 94M49 85H77M45 90H81",1.5)+(v?P("M3 80H23L20 89H7Z")+C(8,91,2)+C(19,91,2):L("M102 8L119 24M110 9L102 16M105 27L121 13",1.4));break;
case "crypt":s=G(arch(v),28,12,.95)+P("M15 78H112V86H15Z")+L("M42 78V42H88V78M47 44H83V75H47Z M65 46V74M48 55H83",1.1)+(v?L("M8 78L14 64M115 64L121 78"):G(grave(v),4,53,.75));break;
case "tomb":s=P(v?"M17 67L36 27 90 27 112 67Z M8 67H120V81H8Z":"M19 69L64 11 111 69Z M8 69H120V82H8Z")+P("M49 69V50H79V69Z",ink)+L("M25 62H45M84 62H104M40 44H49M80 44H91M12 75H116",.9)+seq(5,i=>L(`M${86+i*4} ${49+i*4}l4 7`,.65));break;
case "graveyard":s=G(grave(v),12,33,1.1)+G(grave(1-v),47,11,1.05)+G(grave(v),88,37,1.1)+G(grave(1-v),42,53,.9)+L("M4 85L22 78M106 79L124 85M5 74V82M124 73V83",1);break;
case "ruins":case "ancient_ruins":s=G(arch(v),28,7,.88)+G(obelisk(1-v),8,26,.58)+G(obelisk(v),104,34,.5)+G(rock(v),3,63,.4)+G(rock(1-v),103,66,.4)+L("M28 78L49 73M78 75L103 81",1);if(kind==="ancient_ruins")s+=L("M12 83H118M36 76l4 7M61 75l3 8M83 76l2 7",.8);else s+=L("M40 19L48 25M81 32L89 29",1.3);break;
case "abandoned_village":s=G(broken_house(v),3,15,.95)+G(broken_house(1-v),69,22,.93)+G(broken_house(v),37,43,.62)+L("M5 81L14 75M108 81L121 76M46 9L52 15M88 8L93 13",.9);break;
case "ruined_castle":s=G(tower(v),4,11,.95)+G(tower(1-v),88,18,.85)+G(tower(v),46,0,.95)+P("M33 74V43L46 43 50 36 61 43 71 34 84 44 99 43V74H78V60Q66 48 54 60V74Z")+L("M36 52H45M82 59H94M59 44l5 6m7 -5l-4 5",.9);break;
case "dungeon":s=G(arch(v),26,9,.98)+P("M46 76V40Q63 24 82 40V76Z",ink)+L("M45 78H83L95 91H34Z M41 83H88M38 87H92",1.2)+(v?L("M49 44V76M57 37V76M65 34V76M74 37V76M81 44V76",.8,"stroke=\"#f4dfbb\""):L("M18 60H31M98 60H111M18 63H31M98 63H111",.9));break;
case "standing_stones":s=G(obelisk(v),47,8,1)+G(obelisk(1-v),15,30,.72)+G(obelisk(v),94,38,.6)+G(rock(v),70,65,.42);break;
case "stone_circle":s=circleRing(v);break;
case "magical_portal":s=G(arch(v),25,4,1)+`<ellipse cx="65" cy="44" rx="19" ry="24" fill="none" stroke="${ink}" stroke-width="1.4" stroke-dasharray="3 2"/>`+L(v?"M48 44Q64 16 81 44Q65 70 48 44M65 23V65":"M65 21L70 39 82 44 70 48 65 66 61 48 48 44 61 39Z",1.15)+seq(8,i=>{let a=i*Math.PI/4;return C((65+30*Math.cos(a)).toFixed(1),(44+34*Math.sin(a)).toFixed(1),.8)});break;
case "camp":s=G(tent(v),22,12,1)+G(fire(v),48,51,.85);break;
case "bandit_camp":s=G(tent(v),4,22,.8)+G(tent(1-v),69,12,.62)+G(fire(v),48,52,.83)+L("M7 76L15 70M115 73L122 80M96 9V36M96 9L112 15 96 20",1.2)+P("M99 13L110 15 99 18Z",ink,.5);break;
case "military_camp":s=G(tent(v),3,13,.67)+G(tent(1-v),67,13,.67)+G(tent(v),35,46,.68)+L("M4 83V72M16 83V72M28 83V72M100 83V72M112 83V72M124 83V72M4 77H28M100 77H124M63 5V43M63 6L83 12 63 19",1.2);break;
case "adventurer_camp":s=G(tent(v),14,15,.87)+G(fire(1-v),78,49,1)+P("M4 74Q17 61 33 74V82H4Z")+L("M7 74Q18 69 30 74M12 68V82M24 68V82",.7)+(v?G(rock(v),96,74,.42):L("M93 29L103 45M89 32L97 29",1));break;
case "monster_lair":s=cave(v)+P("M10 78Q10 66 23 66Q36 66 35 78L29 82H16Z")+C(18,74,2)+C(27,74,2)+L("M17 82V86M22 82V87M27 82V86M100 77L119 68M102 68L119 78",1.1);break;
case "battlefield":s=L("M15 15L108 80M107 15L16 80",3)+L("M10 8L26 22M102 8L116 22M8 76L22 88M102 87L116 75",2)+P(v?"M44 36L83 36V59Q65 81 44 59Z":"M45 35L83 35V62L64 76 45 62Z")+L("M64 38V70M49 48H79",1.3)+G(grave(v),3,43,.6)+G(grave(1-v),108,43,.6);break;
case "ancient_monument":s=G(obelisk(v),48,2,1.1)+P("M37 72H89V79H37Z M26 79H102V85H26Z M13 85H115V91H13Z")+L("M55 26L72 26M56 34L70 34M55 42L71 42M54 51L71 51",.8)+(v?G(obelisk(1-v),9,46,.52):G(rock(v),98,62,.5));break;
case "well":s=well(v);break;
case "hidden_entrance":s=G(rock(v),1,33,1.3)+G(rock(1-v),69,39,1.1)+P("M49 80V54L65 40 82 54V80Z",ink)+L("M4 71Q24 58 44 66M85 67Q110 59 124 70M55 80L51 90M76 80L80 90",1.1,"stroke-dasharray=\"2 3\"")+(v?L("M9 80l9 -11m-6 11l4 -5M112 80l-5 -14m2 14l8 -7",1):L("M7 83l6 -8m98 8l5 -7",1));break;
case "point_of_interest":s=G(obelisk(v),52,15,.86)+G(rock(1-v),11,51,.8)+G(rock(v),91,57,.65)+L(v?"M64 7L67 1 70 7M59 4L64 9M75 4L70 9":"M64 6V1M53 9L48 5M76 9L81 5",1);break;
default:throw Error(kind)}return s+base(v)}
export const kinds=["cave","cavern","mine","crypt","tomb","graveyard","ruins","ancient_ruins","abandoned_village","ruined_castle","dungeon","standing_stones","stone_circle","magical_portal","camp","bandit_camp","military_camp","adventurer_camp","monster_lair","battlefield","ancient_monument","well","hidden_entrance","point_of_interest"];
export {adventure};
