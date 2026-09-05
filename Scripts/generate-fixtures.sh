#!/bin/bash
# Tiny original sine-wave recordings only; no copyrighted music in the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p OtoTests/Fixtures work
python3 - <<'PY'
from pathlib import Path
p=Path('work/cover.ppm')
w=96
p.write_bytes(f'P6\n{w} {w}\n255\n'.encode()+bytes(c for y in range(w) for x in range(w) for c in (35+x,75+y,92)))
PY
ffmpeg -hide_banner -loglevel error -y -i work/cover.ppm OtoTests/Fixtures/cover.jpg
base=(-hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:duration=8:sample_rate=44100' -af 'volume=0.0001')
ffmpeg "${base[@]}" -c:a flac -metadata title='First Light' -metadata artist='Test Artist' -metadata album='Quiet Hours' -metadata album_artist='Test Artist' -metadata track='1/3' -metadata disc='1/1' OtoTests/Fixtures/01.flac
ffmpeg "${base[@]}" -c:a flac -metadata title='Second Light' -metadata artist='Test Artist' -metadata album='Quiet Hours' -metadata track=2 OtoTests/Fixtures/02.flac
ffmpeg "${base[@]}" -c:a alac -metadata title='Lossless' -metadata artist='Test Artist' -metadata album='Formats' -metadata album_artist='Album Artist' -metadata track='2/4' -metadata disc='2/2' OtoTests/Fixtures/alac.m4a
ffmpeg "${base[@]}" -c:a aac -metadata title='AAC Song' -metadata artist='Test Artist' -metadata album='Formats' -metadata track=1 OtoTests/Fixtures/aac.m4a
ffmpeg "${base[@]}" -c:a libmp3lame -metadata title='MP3 Song' -metadata artist='Test Artist' -metadata album='Formats' -metadata album_artist='Album Artist' -metadata track='3/4' -metadata disc='2/2' OtoTests/Fixtures/song.mp3
ffmpeg "${base[@]}" -c:a pcm_s16le OtoTests/Fixtures/untagged.wav
ffmpeg "${base[@]}" -c:a pcm_s16be OtoTests/Fixtures/untagged.aiff
ffmpeg "${base[@]}" -c:a aac -f adts OtoTests/Fixtures/raw.aac
ffmpeg -hide_banner -loglevel error -y -i OtoTests/Fixtures/01.flac -i OtoTests/Fixtures/cover.jpg -map 0:a -map 1:v -c copy -disposition:v attached_pic work/embedded.flac
mv work/embedded.flac OtoTests/Fixtures/01.flac
