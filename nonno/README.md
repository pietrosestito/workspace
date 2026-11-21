# Il Nonno e la Coppa rubata

Platform retro in **Love2D 11.5**. Una sola versione gira su R36S, Android e PC.

## Regole retro

- Lo schermo interno è **320×240**, ingrandito di un fattore intero (2× sull'R36S), senza filtri.
- Il gioco gira a **60 fotogrammi al secondo** fissi.
- Ogni sprite e ogni gruppo di tile usa al massimo **16 colori**; lo controlla `tools/mkassets.py`.
- Le sfumature sono a retino (dithering), mai semitrasparenti.
- Il tasto **SELECT** accende e spegne le scanline.

## Comandi

| | Tastiera | Joypad (R36S, Android) | Touch |
|---|---|---|---|
| Muovi | frecce | croce / levetta | ◀ ▶ |
| Salta / avanti | Z, spazio | A | A |
| Pausa, salta la storia | Invio | START | II |
| Scanline | Tab | SELECT | – |

## Comandi make

```sh
make assets   # rigenera i PNG (Python 3 + Pillow + numpy)
make run      # gioca sul PC
make test     # partita automatica senza schermo, con screenshot
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
- `levels/*.txt`: le mappe. `#` sabbia, `B` cassa, `=` passerella, `C` granchio, `P` partenza, `G` obiettivo.
- `lib/retro.lua`: il canvas, la scala intera e le scanline.
- `lib/input.lua`: tastiera, joypad e touch.
