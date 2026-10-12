# LUĎAS: LAST TIME KRATOS — design bible

Pracovní dokument reskinu. Hratelnost zůstává (hordy, kontrakty, extrakce,
pět skillů, komba, Guided start); mění se svět, příběh, jména, zvuky a modely.
Všechno označené **[NÁVRH]** je výchozí volba k připomínkování.

### Implementováno v aktuálním source

- Všech jedenáct nepřátelských slotů má nové modely podle bestiáře níže.
  Šest lidí je přebarvených z CC0 Quaternius packu; myška, šváb, lahev,
  automat a Jackpot jsou vlastní generované rigy. Pohyb, útok a smrt se pečou do VAT.
- Husté skupiny 6–8 běžných halucinací stejného druhu se slepí do jednoho
  megaslepence: mohutnější tělo, mosazné spoje a koruna, přitažené jiskry,
  pomalý asymetrický krok. Zdraví se sečte bez léčení; zabití až po porážce
  započítá všechny slepené životy do zakázky i běžných odměn.
  Bossové, specialisté, hlídači a výběrčí zůstávají samostatní. Spojení
  neprojde zdí ani mezi patry a nevymaže aktivní oheň, mráz, omráčení či tag.
  Počítadlo HALUCINACE ukazuje těla, tlak spawnu pořád počítá původní životy.
- Slepence opakují vlastní anatomii: dvě další hlavy, další ruce/nohy a menší
  končetiny vyrůstající z končetin ve třech omezených generacích. Vnořené menší
  hlavy smyčkují zmenšování pro iluzi nekonečného zoomu; používají skutečné
  textury a VAT modelu, ne geometrickou tapetu. Hlavní korunovaná hlava/jádro
  zůstává přesným cílem, přidané části nemají vlastní životy ani kolize.
  Periferie obrazu běží ve smyčce zpětné vazby (inspirace Fraksl/crystaldive):
  šest zrcadlených kopií světa se do sebe vnořuje a donekonečna zmenšuje k místu zamíření, točí, mění odstín, rozpadá
  barevně a v hloubce zrcadlí, navíc rozostření a dvojité vidění. Střed
  zamíření a HUD zůstávají ostré.
  INTENZITA HALUCINACÍ se ukládá (0–100 %, výchozí 65 %); nula vypne nové efekty
  i v pauze. Nový pohyb v pauze/odměnách stojí, kamera se neotáčí ani nebliká.
- První improvizovaná zbraň **Lahve od piva**: špinavá ruka v bezprsté
  rukavici, hnědá pivní lahev, letící lahve a skleněné střepy s pěnou.
  Všech šest hlavních zbraní má vlastní improvizovaný model.
- První generovaný sektor má žižkovské činžáky, pavlače, dlažbu, HERNA NONSTOP,
  PIVO, sodíkové lampy a vysílač. Geometrie kontraktů a kolizí se nemění.
  Palmovka/Hlavák mají nové názvy, zatím původní prostředí.
- Drobné, Cigára a Kešulky mají nové názvy a pixelové ikony. Skilly a
  komba používají schválená jména; parta je Luďas, Vítek ultras, Mikoláš
  hajzldítě a Aleš legendary skillz. Interní ID tříd zůstávají původní.
- Všechny XP upgrady, trvalé talenty, recepty, nabídky obchodu a mastery
  mají české názvy a konkrétní popisy skutečných efektů. Čísla a ceny zůstávají.
- Krystaly a vrtačka jsou nahrazené banky automatů a páčidlem:
  skutečné přihrádky se páčí, dvířka se otevírají a rozbíjejí, kořist se
  zachovává a prázdná skříň zůstává. Dropy jsou mince, krabičky cigaret a žetony.
  Výherní automaty a JACKPOT 777 jsou trojice skutečných hospodských
  automatů: podsvícené sklo s výherní tabulkou a žebříčkem SUPER TURBO
  x1–x10, červené LED displeje SÁZKA/MULTIWIN/BONUS, točící se válce s ovocem
  (rozjezd, rozmazání, zastavení zleva doprava s cuknutím), výhry s
  blikáním a načítáním kreditu, RISK hra na spodním skle a svítící tlačítka.
  Páčí se horní sklo, spodní sklo a pokladna se zámkem. Vypáčený automat
  přestane hrát a rozbliká červenou lampu; vybrakovaná trojice je mimo
  provoz. Cigaretový automat bliká žárovkami a neonem. Vše stojí v pauze a
  ozdoby nemají kolize.
- Celé UI používá české texty, špinavý papír/kov, oprýskané rámy a tlumenou
  tabákovou, rezavou a jantarovou paletu: úvod, menu, výběr party, bazar,
  nastavení/rekordy, pauza, upgrady, HUD/rady, obchod, interakce a smrt/kořist.
  Anglické schválené hlášky a jména z bible zůstávají; nejde o neonový terminál.
- Každý generovaný sektor má krytou halu v hloubce −4,5 m, průchod,
  veřejné WC a dva schodišťové vstupy z ulice. Jiřího z Poděbrad nese
  zelenou linku A, Palmovka žlutou B a Hlavní nádraží červenou C:
  panely, zářivky, validátory, jízdenkové automaty, lavičky a cedule.
- WC má skutečné duté mísy se sedátkem, nádržkou, splachovacími tlačítky,
  trubkami a papírem; kabinky, pisoáry, dvojitá umyvadla, zrcadla,
  mýdlo, ručníky, vpusti a obsluhu s miskou na drobné.
  Na ulici jsou přenosné WC, staveniště a malý park. Každý sektor má dvě
  skutečně průchozí herny, dvě hospody a dva nonstopy; Palmovka navíc večerku.
  Místnosti mají označený čtyřmetrový vstup z ulice a vlastní přístupné automaty.
  Těžitelné automaty stojí uvnitř vhodných podniků: výherní v herně či hospodě,
  vzácný v herně a cigaretové v hospodě, večerce či nonstopu. Nejsou náhodně
  rozvěšené po venkovních zdech; počáteční dostupný obsah pokryje kontrakt.
  Varianty mění barvy, opotřebení a rozmístění. Nábytek má skutečné kolize,
  ale nechává průchody a přístup k automatům; úzké slepé mezery nevznikají.
  Otočené stěny metra i WC mají shodný viditelný a fyzický půdorys,
  včetně stěn mezi sousedními podzemními místnostmi.
- Hlášky z `hlasky.txt` jsou na závěsných cedulích uvnitř podniků, nad vstupy,
  v metru a WC i na venkovních nástěnkách parku a staveniště. Celé řádky se
  zalamují podle prostoru; výběr je náhodný podle seedu a nemění herní RNG.
- Podzemí zabírá rezervovaný půdorys pod neprůchozí hmotou domu:
  v jednom XZ bodě není zároveň hratelná ulice i spodní patro.
  Hráč a horda používají stejné rampy; radar rozlišuje patro,
  kořist a efekty leží na místní podlaze. Odvoz a zásoby shora zůstávají venku.
- Hlasová banka obsahuje 19 klipů. Z delších zpráv přibyly fráze
  `street_racer`, `jedno_kolo`, `takhle`, `plna_rychlost` pro variace reakcí.
- Zvolený konec B je zapsaný v kapitole 5; tento asset pass nepřidává
  příběhové cutscény ani svatební dialogy.
- Lidé z ulice mají čtyřiadvacet vymyšlených pixelových obličejů (dvacet bezďáci,
  opilci a feťáci, čtyři tvrdší chlapi; osm z nich jsou nové archetypy) a špínu v shaderu. Bezdomovec, Feťák a
  Alkoholik se objevují ve všech třech sektorech včetně Hlaváku. Obličeje jsou
  malované z parametrů; nejsou podle fotek ani skutečných lidí.
- Čtrnáct obchodů (Večerka NONSTOP, Bazar Roháč, Potraviny pivo 18, Second hand
  Nositel, Hospoda točené 32, Železářství, Trafika losy, Absintherie, Výdejna PPL,
  Drogerie Savo, Řeznictví, Herna žetony, Pekárna 6:00, Žižkovský tunel) stojí jako
  výlohy na činžácích a pojmenovávají obchod mezi sektory. Květinářství záměrně
  chybí („vegetariánský mor“). Jen kulisa a hlášky; hratelnost se nemění.
- Výbava na jeden běh: čtyři místa, žádné duplikáty a výslovná výměna při
  plné kapacitě. Zrcadlo těžkýho dna odráží zásahy, Geoxy z Palmovky nechávají
  stopu při úhybu, Kabel celoživotních blesků řetězí šok, Podržtaškovy rukavice
  dávají štít za páčení, Nebozízkový zapalovač odměňuje sérii zabití výbuchem.
  Nejsem sklenička je označené prokletí: +50 % poškození, −35 % maximálního zdraví.
  Karty i prohlížení přes G ukazují účinek, pixelovou ikonu a odpovídající hlášku.
- Každý sektor má hlídanou skrýš, dvě průzkumné keše a volitelného výběrčího
  s výbavou. Skrýš lze vybojovat nebo ukrást držením E; její odměna nabízí až
  tři různé věci, keše a výběrčí jednu. Pro odvoz musíš vedle páčení a zabití
  vybrat alespoň dvě různé skrýše: počítá se hlídaná i obě průzkumné keše,
  ne elitní drop. Odmítnutí výbavy nevadí; opakované vybrání nepřidá postup.
  Počítadlo začíná v každém sektoru od nuly.
  Objevy odemykají budoucí elitní dropy, nikoli trvale vybavenou sílu.


## 1. Logline

Samozvaná DJ legenda Luďas prochlastal, prošlehal a v automatech protočil
rodinné dědictví. Kamarády všechny permabanoval, spí v igelitce z Kauflandu.
Jedné noci v devadesátkách se probudí v septiku na Žižkově, oznámí poslední
party — *„Tartarus se uzavírá, minuta, no mercy“* — a v deliriu sestupuje
Prahou jako Kratos: Žižkov → Palmovka → Hlavní nádraží. Musí vysekat
automaty, vyplatit gramce ze zastavárny a odehrát svůj set. Černá komedie,
která s každým sektorem tmavne.

## 2. Luďas

- Chce být DJ. Má „4 setupy a jeden mixák navíc“, „vytažený gramce“, ví
  „co je crossfader“, Maschine místo „FL Studia pro mrdky“.
- Rodinné dědictví utratil za Nebožízek party (platil je sám, nikdo nepřišel,
  pak lidem posílal „zpětné účty“), za automaty a za techniku, kterou zastavil.
- Svůj svět vidí jako mytologii: **Tartarus, Valhalla, Kratos „last time“,
  Heroic Ragnarok, Excalibur, unlimited god mode**.
- Rituál: **permaban**, „BANNED 24 hodin za no response“, „disrespect to the
  gods“, „Ende system restart, poslední šance“, „Odpočet do autodestrukce“.
- Oblouk: legenda → krach („Zkrachujem a sem v hovnech“) → dno („Jsem úplně
  trash popelnice“, „Nikdo nechce bejt sám“) → *„Já sem se změnil, už hejtit
  nebudu lidi takhle“* (opakováno šestkrát).

### Dream team (čtyři hratelné postavy) [NÁVRH]

Podle hlášky *„Aleš legendary skillz, Vítek ultras, Mikoláš hajzldítě a já —
dream team“* nahrazují čtyři třídy:

| Třída dnes | Postava | Profil |
| --- | --- | --- |
| Scout (zdarma) | **Luďas** | DJ legenda, rychlý, kolobežka Duplex |
| Gunner | **Vítek ultras** | tvrdej, víc zdraví, hlasitej |
| Driller | **Mikoláš hajzldítě** | vytrhává hajzly, septiky, ničení |
| Engineer | **Aleš legendary skillz** | lítá nahej, „vždycky řekne pojď někam jdem“ |

## 3. Tón a hranice obsahu

- Černý humor, absurdita, chlast, cigára, automaty, hovna, septiky, hejt,
  bany, bohové, vegetariáni a knírači jako terče posměchu.
- Úrovně tmavnou: Žižkov je komedie, Palmovka kocovina, Hlavák peklo.
- **Do hry nejde:** sexuální násilí, nekrofilie, nadávky mířené na gaye a
  rasové nadávky, oslava nacismu a Putina z Luďasových chatů. Výjimka: hláška
  z videa „Můžeme si tady zahajlovat?“ zůstává doslova (zadání).
- Jména kamarádů jsou zástupná (Aleš, Vrába, Vítek, Mikoláš, Palisek, Sony,
  Radek, Lenka, Vobo) a smí se použít.

## 4. Éra: devadesátky

Instagram, YouTube a covid z chatů se převádí do dobových ekvivalentů:

- „permaban“ = smazal tě z telefonního seznamu Nokie / neodepíše na pager /
  „ban na ICQ“ (ICQ od 1996)
- herny NONSTOP, výherní automaty, jednoruký bandita, žetony
- koruny (Kčs do 1993, pak Kč), veksláci, zastavárny, bazary
- absint (český absint se znovu prodává od 1990), rum, vodka, Fernet, pivo
- igelitka z Kauflandu zůstává jako Luďasův mem, i když je trochu anachronická

## 5. Struktura: tři kruhy Tartaru

Hratelnost sektorů zůstává (procedurální místnosti a chodby, kontrakt,
extrakce, obchod mezi úrovněmi).

| Sektor dnes | Kruh | Místo a dominanty | Kontrakt | Extrakce [NÁVRH] |
| --- | --- | --- | --- | --- |
| Yard | **I. Žižkov — „Ijéééé“** | pavlače, dvorky, hospody, herna NONSTOP; nad zdmi **Žižkovský vysílač** (1985–1992, ještě bez miminek; „Jakešův prst“, „Bajkonur“) | vysekat automaty (drobné) + rozprášit jeden druh halucinací | noční tramvaj |
| Foundry | **II. Palmovka — kocovina** | tramvajová křižovatka pod **Libeňským plynojemem**, Libeňský most, podchody, bazar, zastavárna, Hrabalova Libeň; metro B od 1990 | vyplatit gramce ze zastavárny + cigára | metro B |
| Reactor | **III. Hlavák — Tartarus** | secesní **Fantova budova** s kupolí, komunistická hala pod parkem (1972–77), **Sherwood** (Vrchlického sady), kubistický kiosek s tabákem, sousoší **Sbratření** | jackpot (kešulky) na finální set | pódium / poslední vlak |

### Příběhové beaty [NÁVRH]

- **Prolog:** probuzení v septiku na žižkovském dvorku. Telefon: nikdo
  neodepisuje. „Ende system restart.“
- **Žižkov:** herna, první halucinace (knírači). Luďas zjistí, že gramce jsou v
  zastavárně na Palmovce.
- **Palmovka:** kocovina, bazar, zastavárna, zelináři a street raceři. Gramce
  zpátky, ale na Hlaváku se hraje *svatba* a DJ tam chybí („100k za svatbu“).
- **Hlavák:** Tartarus. Kerberos u Fantovky, jackpot, poslední set.
- **Epilog (zvolený konec B):** po posledním setu se Luďas probudí znovu v
  septiku na Žižkově. Telefon: nikdo neodepisuje. „User not found, probíhá
  reinkarnace.“ Smyčka — další běh začíná stejně.

Repliky z videa svatby („Nemám ani jednu svatební fotku!“, „Kde máš sako?“,
„Dělej, je na stole, kytka!“) patří svatebčanům ve finále.

## 6. Bestiář: halucinace (mix podle sektoru)

Statistiky a role zůstávají; mění se modely, jména a barvy. Jak se trip
zhoršuje, mizí lidé a zůstává čisté delirium.

### Ztracené existence (Žižkov, Palmovka; dnes sloty `robot_*`)

Lidské CC0 modely, přebarvené do sešlých devadesátkových hadrů, groteskně
zvětšené proporce.

| Slot | Postava | Role | Popis |
| --- | --- | --- | --- |
| robot_grunt | **Bezdomovec** | roj | igelitka, rozedraná bunda, šourá se v houfech |
| robot_runner | **Feťák** | rychlík | vyzáblý, sprintuje |
| robot_spitter | **Alkoholik** | plivač | z dálky hází lahve |
| robot_tank | **Veksl­ák** | tank | kožená bunda, zlaté řetězy, obr |
| robot_bulwark | **Vyhazovač** | obrněný zepředu | drží před sebou dveře z herny, slabé místo na zádech |
| robot_boss | **Pan Herna** | boss | majitel herny NONSTOP, obří gambler |

### Čisté delirium (Hlavák; dnes sloty `alien_*`)

Vlastní low-poly modely z Blenderu s jednoduchou kostrou.

| Slot | Halucinace | Role | Popis |
| --- | --- | --- | --- |
| alien_grunt | **Bílá myška** | roj | klasika deliria tremens |
| alien_runner | **Šváb z herny** | rychlík | obří šváb |
| alien_spitter | **Lahev rumu** | plivač | chodící lahev, plive rum |
| alien_tank | **Jednoruký bandita** | beran | výherní automat na nohou |
| alien_boss | **Pan Jackpot** | boss | obří automat se třemi válci |

## 7. Zbraně (civilní improvizace, role zůstávají)

| Slot | Zbraň | Role |
| --- | --- | --- |
| pulse | **Lahve od piva** | rychlé házení |
| rail | **Excalibur** (štětka vyrvaná z hajzlu) | těžký průraz |
| scatter | **Vinyly** | vějíř jako frisbee |
| minigun | **Holubí letka** | proud holubů po roztočení |
| autocannon | **Absintovej molotov** | výbuch |
| flamethrower | **Rum + zapalovač** | plamen |

## 8. Skilly

| Skill dnes | Nové jméno | Zdroj |
| --- | --- | --- |
| Gravity Well | **Ban zóna** | „Ban zóna, nic složitýho“ |
| Pulse Barrier | **Valhalla** | „Odcházím do Valhally“ |
| Seismic Charge | **Odpočet do autodestrukce** | |
| Blink Dash | **Kolobežka Duplex** | |
| Drill Dash | **Ilegal street racer** | |
| Grapple Vault | **Vytrhnu hajzl z podlahy** | „for the last time“ |
| Battle Frenzy | **Heroic Ragnarok** | |
| Overdrive | **Unlimited god mode on** | |
| Magma Trail | **Brikulóza** | hořící stopa |
| Recon Flare | **Šlehat blesky** | „Musíš přijít šlehat blesky“ |
| Suppression Barrage | **Blesky ze stropu** | „blesky ze stropu“ |
| Bulwark | **Jsem god** | „Já sem god“ |
| Platform Turret | **4 setupy** | reproduktor, který střílí basy |
| Repair Drone | **Sony s rejzí** | „Jednu rejzi Sony plz“ |

Komba: CRUSH → **POWNED**, COLLAPSE → **PERMABAN**, SHIELD RAM → **LAST TIME KRATOS**.

## 9. Měny

| Dnes | Nově | Kde |
| --- | --- | --- |
| Gold | **Drobné** (Kč) | z automatů |
| Cinder Crystal | **Cigára** | z automatů na cigarety, platidlo scény |
| Void Shard | **Kešulky** (žetony) | vzácný jackpot |

### Páčení automatů

Zblízka zamiř na živou přihrádku a drž **F**. Páčidlo se vysune samo,
zasune do zámku a páčí dvířka zpátky. Když odběhneš bojovat, poškození zůstává.
Zámek označený **+** dává ×1,75; práce na stejné západce postupně přidá
až +35 % rychlosti. Dvířka mají vlastní skutečné kolidery, po rozbití se
odstraní a vyplatí jen svůj díl předem určené kořisti. Prázdná skříň zůstává
a nejde vybrat znovu. Zbraň, skill, vzdálený cíl ani cíl za zdí kořist nevydají.
Kontrakt počítá skutečně vypáčené jednotky, ne sebrané či uložené peníze.


## 10. Hlas a hlášky

- **Repliky z videa** (doslova, beze změn): svatebčané, halucinace v boji.
- **Luďasovy hlášky** (`hlasky.txt`) a **hlasové zprávy**: Luďasovy reakce
  (zabití, komba, nízké zdraví, odemknutí skillu, obchod, extrakce).
- Krátké nastříhané klipy z archivu `#ludas_vox` jsou první sada; dlouhé
  zprávy se stříhají postupně.

## 11. Assety a reference

- Lidé: CC0 animované základní modely (Quaternius), přeoblečené a
  přetexturované; nepřátelé se pečou do VAT jako dnes (`tools/vat`).
- Zbraně a rekvizity: vlastní low-poly z Blenderu (jako dnešní zbraně).
- Textury: vlastní procedurální, inspirované veřejně známými místy (žádné
  cizí fotky v buildu).
- Fotky míst slouží jen jako reference.

## 12. Otevřené otázky

- ~~Konec A, nebo B?~~ → B (smyčka v septiku).
- Miminka na vysílači: jsou až z roku 2000. Halucinace navíc pro finále?
- Dobová hudba: punk, raný techno, dechovka z hospody?
- Které Luďasovy hlášky chceš povinně ve hře?
