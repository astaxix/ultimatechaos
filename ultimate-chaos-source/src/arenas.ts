export const arenas=[
 {id:'temple',name:'Himmlischer Tempel',image:'/art/arena-ascension.webp',color:'#e9c98c'},
 {id:'shadow',name:'Schattenfestung',image:'/art/arena-shadow.webp',color:'#b995e9'},
 {id:'crystal',name:'Kristallpalast',image:'/art/arena-crystal.webp',color:'#93d5ed'},
 {id:'volcano',name:'Vulkanarena',image:'/art/arena-volcano.webp',color:'#ef9675'},
 {id:'dimension',name:'Verlorene Dimension',image:'/art/arena-dimension.webp',color:'#a9a2ef'},
 {id:'observatory',name:'Sternenobservatorium',image:'/art/arena-observatory.webp',color:'#9bbde9'},
 {id:'throne',name:'Chaos-Thron',image:'/art/arena-throne.webp',color:'#e6c38a'},
] as const;
export const chapterArena=[0,3,2,0,1,4,5,6] as const;
export function arenaFor(stage:number|null|undefined,wave:number|null|undefined,code:string){return arenas[stage!=null?chapterArena[stage]??0:wave!=null?(wave-1)%7:Array.from(code).reduce((n,c)=>n+c.charCodeAt(0),0)%7];}
export const chapterStories=[
 'Am äußeren Tor hält Milo die erste Laterne gegen die Dunkelheit. Er sucht keinen Helden, sondern jemanden, der auch nach einem Fehlzug stehen bleibt. Zeig ihm, dass dein Funke trägt.',
 'Nora kennt jeden sicheren Stein zwischen den Lavaströmen. Seit das Feuer die alten Wege verschlungen hat, bewacht sie die letzte Passage. Ihr Rhythmus ist schnell – deiner muss unberechenbar bleiben.',
 'In den Spiegeln des Kristallpalasts erscheint jede Bewegung zweimal. Kaito vertraut keinem Spiegelbild. Die stille Klinge fordert dich auf, deine Gewohnheiten abzulegen, bevor du die Silberbrücke überquerst.',
 'Seraphine hat geschworen, die goldene Bastion niemals einem Schatten zu überlassen. Ihre Rüstung trägt acht Sonnensiegel. Brich jedes davon, und sie wird dir das Tor zu den inneren Reichen öffnen.',
 'Rook handelt mit Geschichten, Geheimnissen und gelegentlich mit der Wahrheit. Unter dem Mond der Schattenfestung setzt er alles auf deinen nächsten vorhersehbaren Zug. Gib ihm nichts, das er verkaufen kann.',
 'Am Astralhafen antwortet der Nebel mit Stimmen aus möglichen Zukünften. Nyx hört sie alle. Doch keine Zukunft ist entschieden, solange du deine nächste Macht noch wählen kannst.',
 'Astra zählt die Sterne, die seit dem ersten Chaos erloschen sind. Im Observatorium hält die letzte Wache ihre Position. Wer ihre Prüfung besteht, darf den Pfad hinter dem gefrorenen Himmel betreten.',
 'Veyr sitzt dort, wo alle Wege enden und wieder beginnen. Elf Siegel halten den Ereignishorizont zusammen. Besiege den Herrn des Chaos, bevor dein letzter Funke im Schatten seines Throns erlischt.',
] as const;
