export const fighters = [
 {name:'Schere',title:'DIE KLINGEN DES SCHICKSALS',short:'Schnitt. Ende. Aus.',color:'#c3b1ff',wins:[2,5,4]},
 {name:'Stein',title:'DER URALTE KOLOSS',short:'Diskussion beendet.',color:'#b9c1d7',wins:[0,5,6]},
 {name:'Papier',title:'DAS HEILIGE KLEINGEDRUCKTE',short:'Unterschreib dein Schicksal.',color:'#f3e8c9',wins:[1,3,6]},
 {name:'Zauberbrunnen',title:'DAS PORTAL HAT DURST',short:'Ein Wunsch. Ein Dimensionsloch.',color:'#88ded7',wins:[0,1,4]},
 {name:'Erzengel Michael',title:'DIE HIMMLISCHE INSTANZ',short:'Dein Ende. Amtlich beglaubigt.',color:'#edca7c',wins:[1,2,6]},
 {name:'Himmlischer Colt',title:'GÖTTLICHE DURCHSCHLAGSKRAFT',short:'Amen. Nachladen.',color:'#f1b385',wins:[2,3,4]},
 {name:'Atombombe',title:'DAS LETZTE ARGUMENT',short:'Das eskalierte etwas.',color:'#b9e888',wins:[0,3,5]},
] as const;
export function winner(a:number,b:number){return a===b?0:(fighters[a].wins as readonly number[]).includes(b)?1:2;}
const lines:Record<string,string[]>={
 '0-2':['Papierkram erledigt. Endgültig.','Die Schere kürzt das Kleingedruckte.'],
 '0-5':['Waffenschein in zwei Hälften.','Göttliche Munition. Irdische Bastelschere.'],
 '0-4':['Flügel gestutzt. Beförderung vertagt.','Michael hätte die Sicherheitsschere nehmen sollen.'],
 '1-0':['Die Klingen beißen auf Granit.','Schere trifft Stein. Die Garantie erlischt.'],
 '1-5':['Göttliche Kugeln. Solide Gegenargumente.','Der Stein hat keinen Respekt vor Kalibern.'],
 '1-6':['Steinzeit schlägt Endzeit.','Dieser Fels hat die Explosion ausgesessen.'],
 '2-1':['Eingewickelt. Versandkosten trägt der Stein.','Auch ein Koloss passt ins Geschenkpapier.'],
 '2-3':['Brunnen geschlossen. Wegen Papierstau.','Ein Formular stoppt sogar den Abgrund.'],
 '2-6':['Papier schlägt Atombombe. Frag nicht nach Physik.','Explosion abgelehnt. Antrag unvollständig.'],
 '3-0':['Der Brunnen hatte heute besonders viel Hunger.','Schere versenkt. Bastelstunde abgesagt.'],
 '3-1':['Der Stein macht jetzt Tiefenforschung.','Plumps. Geologie trifft Kanalisation.'],
 '3-4':['Auch Engel müssen mal untertauchen.','Michael hat den falschen Aufzug genommen.'],
 '4-1':['Michael teilt den Fels. Ohne Baugenehmigung.','Stein? Ein göttlicher Kiesel.'],
 '4-2':['Das Kleingedruckte wurde heiliggesprochen.','Michael kennt die AGB des Universums.'],
 '4-6':['Michael hat die Atombombe persönlich entschärft.','Apokalypse verschoben. Michael hat Feierabend.'],
 '5-2':['Der himmlische Colt hat göttliche Munition geladen.','Papier durchlöchert. Jetzt als Konfetti erhältlich.'],
 '5-3':['Der Abgrund kassiert eine himmlische Salve.','Brunnen getroffen. Wunsch leider verfehlt.'],
 '5-4':['Der Colt hatte die höhere himmlische Freigabe.','Michael wurde zum Duell gebeten. Amen.'],
 '6-0':['Die Schere schneidet jetzt radioaktiv.','Bastelstunde endet mit einem Pilz.'],
 '6-3':['Brunnen verdampft. Wunsch erfüllt?','Der Abgrund hat jetzt Fußbodenheizung.'],
 '6-5':['Ein Colt. Eine Bombe. Eine kurze Diskussion.','Göttliche Munition trifft sehr weltliche Eskalation.'],
};
export function quip(a:number|null,b:number|null,round:number){if(a===null&&b===null)return 'Beide zu langsam. Selbst das Chaos wartet nicht ewig.';if(a===null||b===null)return 'Fünf Sekunden vorbei. Wer zögert, verliert.';if(a===b)return 'Zwei gleiche Gedanken. Null Fortschritt. Göttlich.';const w=winner(a,b)===1?a:b;const l=w===a?b:a;return lines[`${w}-${l}`][round%2];}
export type Room={id:string;code:string;host:string;guest:string|null;host_name:string;guest_name:string|null;phase:'lobby'|'select'|'result'|'finished';match_no:number;round_no:number;host_score:number;guest_score:number;host_locked:boolean;guest_locked:boolean;host_ready:boolean;guest_ready:boolean;host_choice:number|null;guest_choice:number|null;winner:string|null;reveal_at:string|null;select_until:string|null;next_round_at:string|null;match_winner:string|null;host_seen:string;guest_seen:string|null;updated_at:string};
