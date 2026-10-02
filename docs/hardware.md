# Modificare la SUP Game Box

> ⚠️ Serve saldare un componente SMD. Si rischia di danneggiare la console in modo permanente: lavora su una seconda flash e conserva il dump originale.

## Come è fatta

La SUP "400 in 1" contiene:
- un **NES-on-a-chip** (VT02/VT03 o simile), di solito una goccia di resina nera sul PCB;
- una **memoria flash** che contiene il menu e tutti i giochi. Nei modelli più diffusi è una NOR parallela in package TSOP48 (sigle come `29LV160`, `29LV320`, `S29GL064`, `MX29LV640`); in alcune revisioni è una flash SPI SOP8 (`25Qxx`).

I giochi sono ROM NES normali, quasi tutte NROM, CNROM o UNROM. Il menu imposta i registri di banking del VT02 per avviare ciascuno. Box Hero è NROM-128, quindi può prendere il posto di uno qualunque dei giochi NROM-128.

## Cosa serve

- un programmatore: XGecu **T48** / TL866II+ con adattatore **TSOP48** (per la SPI basta una clip SOIC8 o il CH341A);
- una stazione ad aria calda, flussante e treccia dissaldante;
- possibilmente una seconda flash identica, vergine;
- un PC con Python 3 e questo repository compilato (`make`).

## Procedura

1. **Prova prima in emulatore.** Apri `build/boxhero.nes` con Mesen o FCEUX. La SUP non ha slot cartuccia, quindi ogni tentativo sull'hardware costa una dissaldatura.
2. **Apri la console** (viti posteriori) e trova la flash. Annota la sigla esatta.
3. **Dissalda la flash** con l'aria calda. Una SPI SOP8 si può spesso leggere in-circuit con la clip, senza dissaldare.
4. **Fai il dump** con il programmatore, selezionando la sigla esatta. Leggi **due volte** e confronta i file: devono essere identici. Conserva `originale.bin` in un posto sicuro.
5. **Scegli il gioco da sacrificare.** Deve essere NROM-128 (16 KB + 8 KB) e preferibilmente a **scorrimento orizzontale** (mirroring verticale, come Box Hero). Ti serve il suo file `.nes`.
6. **Applica la patch:**
   ```sh
   python3 tools/patch_multicart.py originale.bin build/boxhero.nes modificato.bin --victim gioco.nes
   ```
   Se il gioco non viene trovato, riprova con `--swap16`: alcune schede salvano le parole a 16 bit con i byte invertiti. Altrimenti trova gli offset a mano con un editor esadecimale e passali con `--prg 0x... --chr 0x...`.
7. **Scrivi `modificato.bin`** sulla seconda flash (o cancella e riscrivi la prima) e verifica la scrittura.
8. **Risalda la flash**, accendi e scegli dal menu la voce del gioco sostituito: parte Box Hero. Il nome nel menu resta quello vecchio.

## Se qualcosa va storto

| Sintomo | Causa probabile |
|---|---|
| Schermo nero o menu assente | Saldatura difettosa, oppure hai sovrascritto il menu: rimetti `originale.bin` |
| Il gioco parte ma la grafica è sbagliata | Hai sostituito un gioco non NROM-128, oppure il CHR è all'offset sbagliato |
| Lo sfondo scorre "a scatti" o duplicato | Il gioco sostituito usava mirroring orizzontale: scegline uno a scorrimento orizzontale |
| Tutto più lento del 17% | La console è PAL (50 Hz): la fisica è calcolata a fotogramma, quindi il gioco resta giocabile |

## Alternativa senza menu

Se il formato del menu non collabora, puoi scrivere sulla flash **solo** Box Hero, ripetuto per riempirla: PRG all'inizio di ogni banco. Così però la console perde gli altri giochi. Il modo in cui il VT02 mappa la flash dopo il reset dipende dalla revisione della scheda, quindi questa strada va verificata sul tuo modello.
