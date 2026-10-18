begin;
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model,power_index,theme)values
('outfit-resonance-velvet','outfit','Mitternachtsamt','Resonanz-Kollektion · ausgearbeitete Material-Farbvariante. Rein kosmetisch.','#514478',850,2,'umbra',null,null),
('outfit-resonance-jade','outfit','Jadewächter','Resonanz-Kollektion · ausgearbeitete Material-Farbvariante. Rein kosmetisch.','#438f83',1350,3,'archon',null,null),
('outfit-resonance-ivory','outfit','Elfenbein-Regent','Resonanz-Kollektion · ausgearbeitete Material-Farbvariante. Rein kosmetisch.','#ded2b4',2000,4,'monarch',null,null),
('outfit-resonance-rose','outfit','Rosengarde','Resonanz-Kollektion · ausgearbeitete Material-Farbvariante. Rein kosmetisch.','#a25c7d',750,2,'duelist',null,null),
('outfit-resonance-cobalt','outfit','Kobaltklinge','Resonanz-Kollektion · ausgearbeitete Material-Farbvariante. Rein kosmetisch.','#396fa9',1150,3,'ronin',null,null),
('outfit-resonance-ember','outfit','Glutwanderer','Resonanz-Kollektion · ausgearbeitete Material-Farbvariante. Rein kosmetisch.','#b27a4f',1200,3,'mistblade',null,null),
('weapon-resonance-jade','weapon','Jadesichel','Resonanz-Kollektion · edle Material-Farbvariante. Rein kosmetisch.','#6fd6b4',1100,3,'scythe',null,null),
('weapon-resonance-ivory','weapon','Elfenbein-Lanze','Resonanz-Kollektion · edle Material-Farbvariante. Rein kosmetisch.','#eadbb5',850,2,'spear',null,null),
('weapon-resonance-rose','weapon','Rosendämmerung','Resonanz-Kollektion · edle Material-Farbvariante. Rein kosmetisch.','#d39bb9',1250,3,'twins',null,null),
('weapon-resonance-cobalt','weapon','Kodex der Tiefe','Resonanz-Kollektion · edle Material-Farbvariante. Rein kosmetisch.','#74b9e5',1800,4,'grimoire',null,null)
on conflict(id)do nothing;
insert into chaos_private.styles(id,slot,price,rarity,power_index)select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog where id like '%-resonance-%' on conflict(id)do nothing;
commit;
