# BOX HERO

Platform a scorrimento orizzontale in stile Super Mario, con un mostro finale alla fine di ogni livello, scritto in assembly 6502 per la **SUP Game Box** (clone NES su chip VT02/VT03). Gira anche su qualsiasi emulatore NES e su NES/Famicom veri.

- 3 livelli, ognuno chiuso da un boss più veloce e resistente (3, 4 e 5 colpi)
- Nemici: *walker* (si schiacciano saltandoci sopra) e *spiky* (con gli aculei, vanno evitati)
- Monete: 100 monete valgono una vita
- Pausa con START

| Tasto | Azione |
|---|---|
| Croce ← → | Muovi |
| A | Salta (tieni premuto per saltare più in alto) |
| B | Corri |
| START | Inizia / pausa |

## Compilare

Servono `cc65` e `python3` (su Debian/Ubuntu: `apt install cc65`).

```sh
make            # -> build/boxhero.nes
make test       # test automatico headless (pip install cynes pillow)
```

Il ROM è **NROM-128** (mapper 0, 16 KB di PRG + 8 KB di CHR, mirroring verticale): è il formato più piccolo e compatibile, adatto a prendere il posto di un gioco nella flash della SUP.

## Struttura

| Percorso | Contenuto |
|---|---|
| `src/main.s` | Codice del gioco: motore, fisica, nemici, boss, grafica, suoni |
| `src/nes.cfg` | Mappa di memoria per il linker (NROM-128) |
| `tools/mkchr.py` | Grafica disegnata in ASCII → CHR-ROM (`build/chr.bin`) |
| `levels/level*.txt` | Mappe dei livelli, modificabili con un editor di testo |
| `tools/mklevels.py` | Converte le mappe in dati assembly e ne controlla la validità |
| `tools/smoketest.py` | Gioca il ROM nell'emulatore e verifica stati, morte, boss e vittoria |
| `tools/patch_multicart.py` | Inserisce il gioco nel dump della flash della SUP |
| `docs/hardware.md` | Guida alla modifica hardware della SUP |

## Modificare i livelli

Ogni file `levels/levelN.txt` ha 15 righe, e ogni carattere è un blocco di 16×16 pixel:

```
.  cielo          #  terreno (colonna piena dal basso)    B  mattone sospeso
o  moneta         w  walker         s  spiky             K  boss (2 righe sopra il terreno)
```

Regole:
- al massimo un mattone per colonna;
- larghezza da 17 a 240 colonne;
- per un salto si possono superare al massimo 3 blocchi di dislivello;
- il boss va messo nelle ultime 16 colonne, cioè nella schermata finale.

Per aggiungere un livello basta creare `level4.txt` e aggiungere un valore in ognuna delle tabelle `boss_*` in fondo a `src/main.s`. `make` segnala gli errori.

## Metterlo sulla SUP

Vedi [docs/hardware.md](docs/hardware.md).
