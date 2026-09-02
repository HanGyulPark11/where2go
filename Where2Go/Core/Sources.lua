-- Real per-dungeon/per-boss item pools for Season 2 (Midnight patch 12.1),
-- ported verbatim from codex/pre-restart-backup's Data/Sources.lua, which
-- was itself generated from the Battle.net Game Data API Journal
-- endpoints. See
-- docs/superpowers/specs/2026-09-02-phase3-direct-drop-design.md for full
-- provenance. Do not hand-edit -- if the data needs correcting, regenerate
-- from the same source. Two encounters below (Dazar, The First King;
-- Avatar of Sethraliss) contain duplicate item IDs in their raw itemIds
-- lists -- this is an artifact of the source's own generation, left as-is
-- here; Core/Ranking.lua deduplicates before counting.

Where2GoSources = {}

Where2GoSources.DUNGEONS = {
    {
        instanceId = 1322,
        name = "Altar of Fangs",
        encounters = {
            { bossId = 2878, name = "Rav'i", itemIds = { 273796, 273795, 273785, 273775, 273777, 273780, 273793 } },
            { bossId = 2879, name = "The Writhing Coil", itemIds = { 273781, 273794, 273786, 273774, 273787, 273782, 273783, 273779 } },
            { bossId = 2880, name = "Zul'jan", itemIds = { 273792, 273797, 273773, 273791, 273789, 273776, 273778, 273784, 270900, 275070, 279211, 276804 } },
        },
    },
    {
        instanceId = 1311,
        name = "Den of Nalorakk",
        encounters = {
            { bossId = 2776, name = "The Hoardmonger", itemIds = { 250248, 251148, 251147, 251146, 251145, 251144, 251143 } },
            { bossId = 2777, name = "Sentinel of Winter", itemIds = { 251154, 251153, 251152, 251155, 251151, 251150, 251149, 250244, 271681 } },
            { bossId = 2778, name = "Nalorakk", itemIds = { 256737, 251160, 250229, 251159, 251158, 251156, 251173, 251214, 251173, 264332 } },
        },
    },
    {
        instanceId = 1304,
        name = "Murder Row",
        encounters = {
            { bossId = 2679, name = "Kystia Manaheart", itemIds = { 250243, 251127, 251124, 251125, 251126, 251123, 271680 } },
            { bossId = 2680, name = "Zaen Bladesorrow", itemIds = { 250215, 251129, 251132, 251130, 251131, 251133, 251128 } },
            { bossId = 2681, name = "Xathuux the Annihilator", itemIds = { 250228, 251136, 251137, 251135, 251134 } },
            { bossId = 2682, name = "Lithiel Cinderfury", itemIds = { 250255, 251142, 251139, 251140, 251141, 251138, 263238, 256640, 258487, 258518, 256746, 258045 } },
        },
    },
    {
        instanceId = 1309,
        name = "The Blinding Vale",
        encounters = {
            { bossId = 2769, name = "Lightblossom Trinity", itemIds = { 251185, 251183, 251184, 251182, 251180, 251181, 250254 } },
            { bossId = 2770, name = "Ikuzz the Light Hunter", itemIds = { 251190, 251189, 251187, 251186, 251188, 250238 } },
            { bossId = 2771, name = "Lightwarden Ruia", itemIds = { 250214, 251194, 251191, 251193, 251192, 251165 } },
            { bossId = 2772, name = "Ziekket", itemIds = { 251199, 251198, 251200, 251197, 251196, 251195, 250259, 256652, 256642, 253451, 268728 } },
        },
    },
    {
        instanceId = 1313,
        name = "Voidscar Arena",
        encounters = {
            { bossId = 2791, name = "Taz'Rah", itemIds = { 250225, 251219, 251222, 251223, 251220, 251221, 251218 } },
            { bossId = 2792, name = "Atroxus", itemIds = { 250245, 251227, 251226, 251228, 251229, 251225, 251224, 252258 } },
            { bossId = 2793, name = "Charonus", itemIds = { 250224, 251234, 251232, 251235, 251233, 251230, 251231, 256721, 264336 } },
        },
    },
    {
        instanceId = 1041,
        name = "Kings' Rest",
        encounters = {
            { bossId = 2165, name = "The Golden Serpent", itemIds = { 159137, 159234, 159413, 159304, 159617, 159369, 159412, 159313 } },
            { bossId = 2171, name = "Mchimba the Embalmer", itemIds = { 159618, 159459, 159667, 160213, 159312, 159642, 159409 } },
            { bossId = 2170, name = "The Council of Tribes", itemIds = { 160216, 159300, 159136, 159643, 159288, 159243, 159371, 159418 } },
            { bossId = 2172, name = "Dazar, The First King", itemIds = { 159921, 158344, 159236, 159422, 159423, 159645, 158355, 159303, 159368, 159301, 159644, 239047, 239045, 239048, 239046, 239049, 239050, 239051, 278245, 239045, 239047, 239050, 239051, 239046, 239048, 239049, 273649 } },
        },
    },
    {
        instanceId = 1202,
        name = "Ruby Life Pools",
        encounters = {
            { bossId = 2488, name = "Melidrussa Chillworn", itemIds = { 193759, 193758, 193761, 193757, 193728 } },
            { bossId = 2485, name = "Kokia Blazehoof", itemIds = { 193762, 193765, 193767, 193763, 193764, 193766 } },
            { bossId = 2503, name = "Kyrakka and Erkhart Stormvein", itemIds = { 193756, 193752, 193691, 193750, 193754, 193755, 193751, 193748, 198059, 198058, 198056, 193753, 256428 } },
        },
    },
    {
        instanceId = 1030,
        name = "Temple of Sethraliss",
        encounters = {
            { bossId = 2142, name = "Adderis and Aspix", itemIds = { 159317, 159380, 158370, 159259, 159425, 159329, 159636, 159388, 159263, 159435 } },
            { bossId = 2143, name = "Merektha", itemIds = { 159637, 159327, 159437, 159375, 162544, 158367, 158714, 159255, 160832, 159437 } },
            { bossId = 2144, name = "Galvazzt", itemIds = { 159247, 159442, 158374, 158366, 158369, 159664 } },
            { bossId = 2145, name = "Avatar of Sethraliss", itemIds = { 159374, 158373, 159254, 159318, 158368, 159370, 159424, 159337, 159257, 159439, 239032, 239031, 239033, 239034, 239035, 239036, 239037, 278982, 239035, 159374, 239031, 159254, 239033, 159318, 239034, 159370, 239036, 159424, 239032, 159257, 239037, 159439 } },
        },
    },
}

Where2GoSources.RAIDS = {
    {
        instanceId = 1317,
        name = "The Tidebound Grotto",
        encounters = {
            { bossId = 2849, name = "Nymrissa Wavecaller", itemIds = { 279112, 270167, 268199, 268221, 268238, 268226, 268263, 268262, 268232, 268247, 268217, 268244, 268266 } },
        },
    },
    {
        instanceId = 1320,
        name = "The Venomous Abyss",
        encounters = {
            { bossId = 2888, name = "Nek'zali the Soulcoiler", itemIds = { 279115, 281227, 268230, 280305, 270162, 268203, 268236, 268235, 268229, 268245, 268208, 270930, 268248, 268218, 268240, 268216 } },
            { bossId = 2874, name = "Entombed Sentinels", itemIds = { 270913, 270912, 270911, 270910, 264716, 268250, 270165, 268204, 268198, 268224, 268228, 268219, 268197 } },
            { bossId = 2894, name = "The Lost Explorers", itemIds = { 279118, 270925, 270924, 270923, 270922, 270164, 270160, 268210, 268200, 268227, 268242, 268258, 268239, 268196 } },
            { bossId = 2882, name = "Vashnik the Malignant", itemIds = { 270929, 270928, 270927, 270926, 272361, 268249, 268246, 268254, 268260, 268214, 270166, 270161, 268205 } },
            { bossId = 2871, name = "Sszorak", itemIds = { 244343, 270921, 270920, 270919, 270918, 270163, 270174, 268206, 268201, 268257, 268234, 268233, 268252 } },
            { bossId = 2887, name = "The Twin Fangs", itemIds = { 279122, 270917, 270916, 270915, 270914, 270171, 270170, 268251, 268264, 268241, 268261, 268223, 268220, 273070 } },
            { bossId = 2883, name = "The Coiled Altar", itemIds = { 268225, 268231, 279131, 268209, 270173, 268243, 270169, 268237, 268222, 268213, 268253, 268255, 268256, 268259, 268211, 275937, 275938 } },
            { bossId = 2895, name = "Ula'tek", itemIds = { 279125, 279127, 279129, 279500, 270909, 268202, 268215, 270168, 270175, 268207, 268265, 271874, 271875, 271876, 271878, 271093, 271092, 275658 } },
        },
    },
}
