export type Look={body:'masculine'|'feminine'|'androgynous';skin:string;hair:string;hairColor:string;eyes:string;face:'soft'|'angular'|'round';brows:'natural'|'bold'|'arched'|'straight';beard:'none'|'stubble'|'full'|'goatee'|'moustache';build?:'slim'|'athletic'|'broad';height?:'short'|'average'|'tall';eyeShape?:'almond'|'round'|'sharp';nose?:'small'|'straight'|'wide';mouth?:'neutral'|'smile'|'serious'|'full';lipColor?:string;trimColor?:string;facePaint?:'none'|'warrior'|'runes'|'sun';paintColor?:string;freckles?:'none'|'light'|'many';scar?:'none'|'cheek'|'brow';glasses?:'none'|'round'|'square';earrings?:'none'|'studs'|'hoops';pantsColor?:string;bootColor?:string;weapon?:string;emote?:string;victory?:string;outfitColor:string;outfit:string;hat:string;aura:string};
export const defaultLook:Look={body:'masculine',skin:'#dba77d',hair:'swept',hairColor:'#30251f',eyes:'#63b5bd',face:'soft',brows:'natural',beard:'none',build:'athletic',height:'average',eyeShape:'almond',nose:'straight',mouth:'neutral',lipColor:'#975f56',trimColor:'#c0b3a0',facePaint:'none',paintColor:'#d2b679',freckles:'none',scar:'none',glasses:'none',earrings:'none',pantsColor:'#263344',bootColor:'#17202c',outfitColor:'#344761',weapon:'none',emote:'none',victory:'none',outfit:'starter',hat:'none',aura:'none'};
export function normalizeLook(value?:Partial<Look>|null):Look{return {...defaultLook,...value};}
export type Category='outfit'|'hat'|'aura'|'frame'|'card';
export type StyleItem={id:string;slot:Category;name:string;rarity:'SELTEN'|'EPISCH'|'LEGENDÄR';price:number;color:string;description:string};
export const styleCatalog:StyleItem[]=[
 {id:'card-frost',slot:'card',name:'Frostschmiede',rarity:'SELTEN',price:350,color:'#8edcec',description:'Eine neue Kollektion aus Eis, Silber und gläsernen Klingen. Für alle sieben Karten.'},
 {id:'card-ember',slot:'card',name:'Glutgeschmiedet',rarity:'EPISCH',price:650,color:'#f2ad78',description:'Kristallwaffen im Licht glühender Lava. Ein Design-Set für dein gesamtes Deck.'},
 {id:'card-eclipse',slot:'card',name:'Eklipse',rarity:'LEGENDÄR',price:1000,color:'#c0a0f0',description:'Dunkle Kristalle, kosmische Reflexe und ein neuer Look für deine sieben Mächte.'},
 {id:'coat-nocturne',slot:'outfit',name:'Nocturne',rarity:'EPISCH',price:450,color:'#83b3e7',description:'Ein langer Mantel. Silberne Kanten. Dein Auftritt nach Mitternacht.'},
 {id:'armor-solstice',slot:'outfit',name:'Sonnenwache',rarity:'LEGENDÄR',price:900,color:'#eac979',description:'Geschmiedetes Gold und ein tiefroter Umhang für große Auftritte.'},
 {id:'jacket-street',slot:'outfit',name:'After Hours',rarity:'SELTEN',price:250,color:'#c4aeef',description:'Oversized Jacke, schwere Boots und ein Hauch Rebellion.'},
 {id:'robe-astral',slot:'outfit',name:'Astral-Seide',rarity:'EPISCH',price:550,color:'#71d2cc',description:'Fließende Stoffe mit leuchtenden, türkisfarbenen Nähten.'},
 {id:'hat-beanie',slot:'hat',name:'Night Shift',rarity:'SELTEN',price:150,color:'#b8a7d9',description:'Eine gerippte Beanie für entspanntes Chaos.'},
 {id:'hat-crown',slot:'hat',name:'Souverän',rarity:'LEGENDÄR',price:650,color:'#eac979',description:'Eine filigrane Krone aus Gold und Sternenlicht.'},
 {id:'hat-cap',slot:'hat',name:'Underground',rarity:'SELTEN',price:200,color:'#9fbeda',description:'Die schwarze Cap mit dem Zeichen der Arena.'},
 {id:'hat-halo',slot:'hat',name:'Heiligenschein',rarity:'EPISCH',price:400,color:'#f7e9b4',description:'Ein schwebender Ring. Unschuld ist optional.'},
 {id:'aura-ember',slot:'aura',name:'Glutkern',rarity:'EPISCH',price:500,color:'#ffae70',description:'Warme Glut und aufsteigende Funken um deinen Charakter.'},
 {id:'aura-frost',slot:'aura',name:'Polarlicht',rarity:'EPISCH',price:500,color:'#7bddf2',description:'Kühle Lichtbänder und schimmernde Eiskristalle.'},
 {id:'aura-void',slot:'aura',name:'Ereignishorizont',rarity:'LEGENDÄR',price:1000,color:'#b49af8',description:'Ein violetter Orbit aus kosmischer Energie.'},
 {id:'violet',slot:'frame',name:'Arkaner Kreis',rarity:'SELTEN',price:150,color:'#b18afa',description:'Ein profilumspannender Runenkreis.'},
 {id:'gold',slot:'frame',name:'Goldene Krone',rarity:'EPISCH',price:350,color:'#e3bf78',description:'Ein goldener Rahmen für deine Visitenkarte.'},
 {id:'celestial',slot:'frame',name:'Sternenkranz',rarity:'LEGENDÄR',price:700,color:'#9bdded',description:'Himmlisches Licht für dein Profil.'},
];
export function tryStyle(look:Look,item:StyleItem):Look{return item.slot==='frame'||item.slot==='card'?look:{...look,[item.slot]:item.id};}

export const hairstyles=[['swept','Seitenscheitel'],['crop','Kurz'],['curls','Locken'],['long','Lang'],['bob','Bob'],['braids','Zöpfe'],['bun','Dutt'],['bald','Ohne Haare'],['pixie','Pixie'],['waves','Wellen'],['ponytail','Pferdeschwanz'],['high-pony','Hoher Zopf'],['twin-tails','Twin Tails'],['mohawk','Irokesenschnitt'],['undercut','Undercut'],['dreads','Dreadlocks'],['afro','Afro'],['sidebraid','Seitenzopf'],['shag','Shag'],['topknot','Topknot']] as const;
