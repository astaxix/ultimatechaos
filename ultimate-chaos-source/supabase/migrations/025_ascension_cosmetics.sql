begin;
-- Additive cosmetic catalogue only; existing ownership, prices and combat rules are unchanged.
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model,power_index,theme) values
('skin-sniper-frost','card','Frostjäger','Frostjäger — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#83d9f6',320,1,'sniper',7,'sniper-frost'),
('skin-sniper-jade','card','Jadedrache','Jadedrache — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#7be2b4',650,2,'sniper',7,'sniper-jade'),
('skin-sniper-seraph','card','Seraphenschuss','Seraphenschuss — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#f2d693',1100,3,'sniper',7,'sniper-seraph'),
('skin-sniper-void','card','Leerenjäger','Leerenjäger — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#c6a1f3',1900,4,'sniper',7,'sniper-void'),
('outfit-asc-paladin','outfit','Solaris-Wache','Solaris-Wache — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#d5b67a',950,3,'paladin',null,null),
('outfit-asc-ronin','outfit','Schattenronin','Schattenronin — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#944b60',850,3,'ronin',null,null),
('outfit-asc-astral','outfit','Astralweber','Astralweber — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#6795ba',750,2,'astral',null,null),
('outfit-asc-specter','outfit','Nachtklinge','Nachtklinge — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#6b8b88',1400,4,'specter',null,null)
on conflict(id) do nothing;
insert into chaos_private.styles(id,slot,price,rarity,power_index) select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog where id in('skin-sniper-frost','skin-sniper-jade','skin-sniper-seraph','skin-sniper-void','outfit-asc-paladin','outfit-asc-ronin','outfit-asc-astral','outfit-asc-specter') on conflict(id) do nothing;
commit;
