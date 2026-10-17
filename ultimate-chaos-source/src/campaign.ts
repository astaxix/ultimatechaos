import {defaultLook,type Look} from './appearance';
export const campaign=[
 {name:'Milo',title:'Der erste Funke',region:'Die äußeren Tore',difficulty:'EINSTIEG',xp:120,coins:100,rounds:10,target:0,look:{hair:'crop',hairColor:'#865739',outfitColor:'#4b6c58'}},
 {name:'Nora',title:'Die Flammenläuferin',region:'Der rote Garten',difficulty:'LEICHT',xp:160,coins:140,rounds:10,target:0,look:{body:'feminine',hair:'long',hairColor:'#a54634',eyes:'#c3a35a',outfit:'jacket-street'}},
 {name:'Kaito',title:'Die stille Klinge',region:'Die Silberbrücke',difficulty:'NORMAL',xp:200,coins:180,rounds:10,target:0,look:{body:'androgynous',skin:'#ba805c',hair:'curls',hairColor:'#171a25',outfit:'outfit-asc-ronin'}},
 {name:'Seraphine',title:'Wächterin der Sonne',region:'Die goldene Bastion',difficulty:'BOSS',xp:320,coins:300,rounds:14,target:8,look:{body:'feminine',hair:'long',hairColor:'#e3c98b',outfit:'outfit-asc-paladin',hat:'hat-crown',aura:'aura-ember'}},
 {name:'Rook',title:'Der Schattenhändler',region:'Unterstadt',difficulty:'SCHWER',xp:260,coins:240,rounds:10,target:0,look:{skin:'#704733',hair:'crop',beard:'full',outfit:'outfit-asc-specter',hat:'hat-beanie'}},
 {name:'Nyx',title:'Die Stimmen des Nebels',region:'Der Astralhafen',difficulty:'EXPERTE',xp:300,coins:280,rounds:10,target:0,look:{body:'feminine',skin:'#955e42',hair:'braids',hairColor:'#8b79b3',outfit:'outfit-asc-astral',aura:'aura-void'}},
 {name:'Astra',title:'Die letzte Sternenwache',region:'Der gefrorene Himmel',difficulty:'MEISTER',xp:360,coins:340,rounds:10,target:0,look:{body:'androgynous',skin:'#e7ba92',hair:'bun',hairColor:'#ece1cb',eyes:'#71aace',outfit:'robe-astral',hat:'hat-halo',aura:'aura-frost'}},
 {name:'Veyr',title:'Der Herr des Ereignishorizonts',region:'Der Thron des Chaos',difficulty:'FINALBOSS',xp:600,coins:600,rounds:18,target:11,look:{skin:'#d1c3ba',hair:'long',hairColor:'#ece1cb',eyes:'#8974b0',face:'angular',outfit:'armor-solstice',hat:'hat-crown',aura:'aura-void'}},
] as const;
export const enemyLook=(stage:number):Look=>({...defaultLook,...campaign[stage]?.look});
export const packTiers=[
 {id:0,name:'Chaos-Truhe',tag:'STANDARD',price:150,color:'#83b4d1',odds:[20,35,20,18,5,1.8,.2],coins:[40,100]},
 {id:1,name:'Epische Truhe',tag:'EPISCH',price:400,color:'#b4a0ed',odds:[10,30,10,28,17,4.5,.5],coins:[100,250]},
 {id:2,name:'Legendäre Truhe',tag:'LEGENDÄR',price:900,color:'#eac879',odds:[5,25,0,20,30,18,2],coins:[250,700]},
 {id:3,name:'Himmlische Truhe',tag:'HIMMLISCH',price:1800,color:'#d7b2ee',odds:[2,18,0,10,25,35,10],coins:[450,1000]},
] as const;
