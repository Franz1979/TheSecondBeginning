# Stagionalità delle risorse secondarie

Documento generato il 2026-09-19 — solo documentazione, non è letto da alcun codice del progetto.
Sostituisce/accompagna `secondary_resources_seasonality.csv` (stessi dati, qui in forma leggibile).
I valori sono presi a fresco dai `.tres` correnti in `simulation/data/secondary_resources/`: se li
ritocchi, questo documento invecchia — non fidarsene ciecamente, verificare contro il file reale.

Per ogni risorsa, **"Disponibilità"** è `seasonal_availability_multiplier` per stagione: la frazione
[0,1] delle unità effettivamente raggiungibili in quella stagione, non una quantità assoluta (quella
dipende dallo stato della macrocella). **"Calorie disponibili"** è Disponibilità × `calories_per_unit`
— un indice comparabile tra risorse, non le calorie totali raccolte in una macrocella reale.

Le risorse si dividono in tre modelli, e la stagionalità si comporta diversamente in ciascuno.

## Stateless — nessun registro da azzerare

`forage`, `fish_meat` e `bird_meat` non hanno alcuno stock o registro di raccolto: scalano
direttamente la risorsa primaria collegata (`GRASS`/`FISH`/`BIRDS`), quindi non c'è mai nulla da
"azzerare" a fine stagione — la disponibilità è semplicemente ricalcolata ogni volta dal vivo.

| Risorsa | Calorie/unità | Inverno | Primavera | Estate | Autunno | Nota |
|---|---|---|---|---|---|---|
| forage | 2.0 | 60% → 1.2 | 100% → 2.0 | 100% → 2.0 | 100% → 2.0 | sempre foraggiabile, un po' meno in inverno |
| fish_meat | 6.0 | 100% → 6.0 | 100% → 6.0 | 100% → 6.0 | 100% → 6.0 | curva piatta (default) — nessuna specie la mangia ancora oggi |
| bird_meat | 10.0 | 100% → 10.0 | 100% → 10.0 | 100% → 10.0 | 100% → 10.0 | curva piatta (default) — nessuna specie la mangia ancora oggi |

## Stock aggregato — un solo stock per macrocella, ripartito per lotto

`berry`, `acorn`, `fruit` ed `eggs` hanno uno stock persistente unico per macrocella, ripartito tra i
lotti (per peso individuale nel caso di berry/acorn/fruit, per peso deterministico del nido nel caso
di eggs). Il raccolto per lotto si azzera quando il moltiplicatore stagionale **sale** rispetto alla
stagione precedente — mai quando scende, perché in quel caso non compare nulla di nuovo da azzerare
verso.

| Risorsa | Calorie/unità | Inverno | Primavera | Estate | Autunno | Nota |
|---|---|---|---|---|---|---|
| berry | 4.0 | 10% → 0.4 | 0% → 0.0 | 70% → 2.8 | 100% → 4.0 | azzera primavera→estate ed estate→autunno |
| acorn | 12.0 | 30% → 3.6 | 10% → 1.2 | 0% → 0.0 | 100% → 12.0 | azzera solo estate→autunno (unica salita della curva) |
| fruit | 30.0 | 10% → 3.0 | 5% → 1.5 | 50% → 15.0 | 100% → 30.0 | azzera primavera→estate ed estate→autunno |
| eggs | 20.0 | 0% → 0.0 | 100% → 20.0 | 0% → 0.0 | 0% → 0.0 | i nidi esistono SOLO se lo stock è > 0 — fuori primavera l'insieme nidi è vuoto, non solo "a disponibilità 0" |

## Capacità per lotto — una microcella, una capacità propria

`pebble`, `stick`, `plant_fiber`, `mushroom` e `wild_vegetables` non condividono nessuno stock di
macrocella: ogni lotto (una microcella) ha una propria capacità. Il gruppo mischia materiali da
costruzione (pebble/stick/plant_fiber, tutti a 0 calorie) e cibo (mushroom/wild_vegetables). Solo
mushroom e wild_vegetables hanno una curva stagionale non piatta oggi, e sono le uniche due che si
azzerano davvero a una salita di stagione — ma il meccanismo (`LOT_CAPACITY_RESOURCE_NAMES`) copre
anche stick/plant_fiber: se domani gli si desse una curva vera, si azzererebbero automaticamente
senza bisogno di aggiungerli a un elenco. `pebble` resta fuori da questo meccanismo per scelta: un
sasso estratto non deve mai ricrescere, qualunque sia la sua curva stagionale.

| Risorsa | Calorie/unità | Inverno | Primavera | Estate | Autunno | Nota |
|---|---|---|---|---|---|---|
| pebble | 0.0 | 100% → 0.0 | 100% → 0.0 | 100% → 0.0 | 100% → 0.0 | mai regrowth — una volta estratto, sparisce per sempre |
| stick | 0.0 | 100% → 0.0 | 100% → 0.0 | 100% → 0.0 | 100% → 0.0 | curva piatta oggi — azzeramento automatico se cambia |
| plant_fiber | 0.0 | 100% → 0.0 | 100% → 0.0 | 100% → 0.0 | 100% → 0.0 | curva piatta oggi — azzeramento automatico se cambia |
| mushroom | 6.0 | 40% → 2.4 | 0% → 0.0 | 30% → 1.8 | 100% → 6.0 | azzera primavera→estate ed estate→autunno (+ un secondo reset incidentale a fine primavera, vedi VegetationPoolService) |
| wild_vegetables | 3.0 | 0% → 0.0 | 100% → 3.0 | 100% → 3.0 | 0% → 0.0 | i lotti esistono SOLO se dedicated_space(GRASS) > 0 — azzeramento raccolto solo inverno→primavera |

## In breve

Guardando le curve tutte insieme: l'**inverno** è la stagione più povera per quasi tutto tranne
forage/fish_meat/bird_meat (flat) e acorn (30%, il suo picco relativo più alto fuori dall'autunno).
L'**autunno** è il picco quasi universale per lo stock aggregato (berry/acorn/fruit tutte al 100%),
mentre eggs e wild_vegetables sono le due eccezioni che vivono di primavera/estate e sono
completamente assenti in autunno-inverno. La **primavera**, paradossalmente, è il buco nero di
berry/acorn/mushroom (0%) proprio mentre eggs e wild_vegetables sono al massimo — le curve non sono
mai state pensate per compensarsi a vicenda tra risorse diverse, è un'osservazione, non una regola
del progetto.
