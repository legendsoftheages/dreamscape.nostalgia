#!/bin/bash
set -e

# Directories & files
TMP=$(mktemp -d)
INPUT_DIR="./reels"
AUDIO_DIR="./audio"
FONT="./Inter-Black.ttf"
LOGO_PATH="./spotify.png"
QUOTES_FILE="./quotes.txt"
OUTPUT_DIR="./output"

mkdir -p "$OUTPUT_DIR"

# 1. Check for required assets
[ ! -f "$QUOTES_FILE" ] && echo "❌ quotes.txt not found" && exit 1
[ ! -f "$LOGO_PATH" ] && echo "❌ spotify.png not found" && exit 1
# Fallback for font if not in repo
[ ! -f "$FONT" ] && FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# 2. Select random clips (15 clips, 1 second each)
FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | sort -R | head -n 15))
[ ${#FILES[@]} -eq 0 ] && echo "❌ No .mp4 files found in $INPUT_DIR." && exit 1

# 3. Select random audio
AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | sort -R | head -n 1)
[ -z "$AUDIO_FILE" ] && echo "❌ No audio file found in $AUDIO_DIR." && exit 1
echo "🎵 Using audio: $AUDIO_FILE"

# 4. Process video clips into 1-second chunks
i=1
for f in "${FILES[@]}"; do
  echo "➡️ Processing: $f"
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  
  # Pick a random start time at least 1s before the end
  START=$(awk -v d="$DURATION" 'BEGIN{srand(); if(d>1.5) printf "%.3f", rand()*(d-1.2); else print 0}')

  ffmpeg -ss "$START" -i "$f" -t 1 \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30" \
    -c:v libx264 -preset superfast -crf 23 -pix_fmt yuv420p \
    -an "$TMP/clip_$i.mp4" -y -loglevel error

  echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
  i=$((i+1))
done

# 5. Merge clips
MERGED_TMP="$TMP/merged.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -c copy "$MERGED_TMP" -y -loglevel error
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_TMP")

# 6. Add audio with 2s fade-out
FADE_START=$(awk -v d="$VIDEO_DURATION" 'BEGIN{print (d>2)?d-2:0}')
MERGED_AUDIO="$TMP/merged_audio.mp4"
ffmpeg -i "$MERGED_TMP" -i "$AUDIO_FILE" \
  -filter_complex "[1:a]afade=t=out:st=$FADE_START:d=2[aud]" \
  -map 0:v -map "[aud]" -c:v copy -c:a aac -shortest "$MERGED_AUDIO" -y -loglevel error

# 7. Quote Selection & Formatting
TOTAL_QUOTES=$(wc -l < "$QUOTES_FILE")
RANDOM_LINE=$((RANDOM % TOTAL_QUOTES + 1))
RAW_QUOTE=$(sed -n "${RANDOM_LINE}p" "$QUOTES_FILE")

# Fix: Create a temporary file with the wrapped text to preserve newlines
echo "$RAW_QUOTE" | fold -s -w 35 > "$TMP/wrapped_quote.txt"

# Fix: Clean filename (No underscores, just spaces and letters)
SAFE_FILENAME=$(echo "$RAW_QUOTE" | sed 's/[^a-zA-Z0-9 ]/ /g' | tr -s ' ' | xargs)
FINAL_OUTPUT="$OUTPUT_DIR/${SAFE_FILENAME}.mp4"

# 8. Logo Timing & Overlay Logic
logo_start=$(awk -v d="$VIDEO_DURATION" 'BEGIN{printf "%.2f", d/2}')
logo_end=$(awk -v d="$VIDEO_DURATION" 'BEGIN{printf "%.2f", d-1}')
logo_fadeout=$(awk -v e="$logo_end" 'BEGIN{printf "%.2f", e-1}')

# The Filter: Uses 'textfile' instead of 'text' to ensure multi-line rendering
FILTER="[1:v]loop=loop=-1:size=1:start=0,fps=30,setpts=N/(30*TB),scale=180:-1,format=rgba,fade=t=in:st=${logo_start}:d=1:alpha=1,fade=t=out:st=${logo_fadeout}:d=1:alpha=1[logo]; \
[0:v][logo]overlay=x=(W-w)/2:y=H-h-120:format=auto:shortest=1[v_logo]; \
[v_logo]drawtext=fontfile='${FONT}':textfile='$TMP/wrapped_quote.txt':fontcolor=white:fontsize=48:box=1:boxcolor=black@0.6:boxborderw=20:line_spacing=15:x=(w-text_w)/2:y=(h-text_h)/2[v_out]"

# 9. Final Render
ffmpeg -i "$MERGED_AUDIO" -i "$LOGO_PATH" \
  -filter_complex "$FILTER" \
  -map "[v_out]" -map 0:a \
  -c:v libx264 -preset fast -crf 22 -pix_fmt yuv420p -c:a copy \
  -movflags +faststart -shortest "$FINAL_OUTPUT" -y -loglevel warning

echo "🎬 Done — final output: $FINAL_OUTPUT"

# Clean up
rm -rf "$TMP"
