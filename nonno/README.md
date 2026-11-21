# Il Nonno e la Coppa rubata

Platform retro in **Love2D 11.5**. Una sola versione gira su R36S, Android e PC.

## Regole retro

- Lo schermo interno è **320×240**, ingrandito di un fattore intero (2× sull'R36S), senza filtri.
- Il gioco gira a **60 fotogrammi al secondo** fissi.
- Ogni sprite e ogni gruppo di tile usa al massimo **16 colori**; lo controlla `tools/mkassets.py`.
- Le sfumature sono a retino (dithering), mai semitrasparenti.
- Il tasto **SELECT** accende e spegne le scanline.

## Comandi

Dal menu scegli **STORIA** (il platform) o **SFIDA** (Nonno contro Toro, 1 contro 1).

| | Tastiera | Joypad (R36S, Android) | Touch |
|---|---|---|---|
| Muovi | frecce | croce / levetta | ◀ ▶ |
| Salta / avanti | Z, spazio | A | A |
| Lancia la palla (platform) | X | B | B |
| Pausa, salta la storia | Invio | START | II |
| Scanline | Tab | SELECT | – |

### Sfida

| Colpo | Tastiera | Joypad |
|---|---|---|
| Pugno leggero | A | Y |
| Pugno forte | S | X |
| Calcio leggero | X | B |
| Calcio forte | Z | A |
| Parata | indietro (giù + indietro per i colpi bassi) | |
| Salto / accovacciato | su / giù | |
| Calcio in salto | un calcio durante il salto | |

- Combo: un colpo leggero che va a segno si interrompe nel colpo successivo, per esempio pugno, pugno, pugno forte.
- Speciale del Nonno, **schiacciata**: giù, giù-avanti, avanti + pugno.
- Speciale del Toro, **carica**: tieni indietro per circa 1 secondo, poi avanti + pugno.
- La partita si vince in 2 round su 3, da 60 secondi l'uno.

## Comandi make

```sh
make assets   # rigenera i PNG (Python 3 + Pillow + numpy)
make run      # gioca sul PC
make test     # partite automatiche senza schermo (storia e sfida), con screenshot
make          # build/nonno.love
```

## Dove gira

- **R36S con Alpine:** installa Love con `apk add love`, poi lancia `love nonno.love`.
- **R36S con dArkOS:** copia il gioco in `ports/` usando il runtime Love di PortMaster.
- **Android:** installa l'app "LÖVE for Android" e apri `nonno.love`. Per un APK autonomo usa `love-android`.
- **PC:** usa Love 11.5, su Windows, Linux o macOS.

## Struttura

- `scenes/story.lua`: il ritratto grande, il testo e il rimpicciolimento verso lo sprite.
- `scenes/level.lua`: la mappa a tile, la fisica, i granchi e l'obiettivo.
- `scenes/fight.lua`: la sfida 1 contro 1, con colpi, parate, speciali, CPU e round.
- `tools/mkfighters.py`: i lottatori generati da uno scheletro, con le zone di colpo calcolate in automatico.
- `levels/*.txt`: le mappe. `#` sabbia, `B` cassa, `=` passerella, `C` granchio, `P` partenza, `G` obiettivo.
- `lib/retro.lua`: il canvas, la scala intera e le scanline.
- `lib/input.lua`: tastiera, joypad e touch.
