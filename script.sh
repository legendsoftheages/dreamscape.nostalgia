#!/bin/bash
set -e

# Directories
TMP=$(mktemp -d)
INPUT_DIR="./reels"
AUDIO_DIR="./audio"
LOGO_PATH="./spotify.png"
QUOTES_FILE="./quotes.txt"
OUTPUT_DIR="./output"

mkdir -p "$OUTPUT_DIR"

# 1. PREPARE ASSETS
# Copy system font to local dir to guarantee accessibility for FFmpeg
LOCAL_FONT="$TMP/font.ttf"
cp /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf "$LOCAL_FONT"

# Remove Windows line endings from quotes file if they exist
sed -i 's/\r//' "$QUOTES_FILE"

# 2. SELECT RANDOM ASSETS
FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | sort -R | head -n 15))
[ ${#FILES[@]} -eq 0 ] && echo "❌ No videos found" && exit 1

AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | sort -R | head -n 1)
[ -z "$AUDIO_FILE" ] && echo "❌ No audio found" && exit 1

# 3. PROCESS CLIPS (Forcing 1080x1920)
i=1
for f in "${FILES[@]}"; do
  # Using trunc to ensure dimensions are divisible by 2 (Required by libx264)
  ffmpeg -i "$f" -t 1 -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:trunc((ow-iw)/2):trunc((oh-ih)/2):black,fps=30" \
    -c:v libx264 -preset superfast -an "$TMP/clip_$i.mp4" -y -loglevel error
  echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
  i=$((i+1))
done

# 4. MERGE CLIPS & ADD AUDIO
MERGED_AUDIO="$TMP/merged_audio.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -i "$AUDIO_FILE" \
  -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest "$MERGED_AUDIO" -y -loglevel error

VIDEO_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_AUDIO")

# 5. QUOTE FORMATTING (The "Fix")
RAW_QUOTE=$(shuf -n 1 "$QUOTES_FILE")

# Wrap text at 30 characters. 
# We use a temporary file to hold the wrapped text to preserve literal newlines.
echo "$RAW_QUOTE" | fold -s -w 30 > "$TMP/final_text.txt"
WRAPPED_TEXT=$(cat "$TMP/final_text.txt")

# Clean filename: replace non-alphanumeric with space, trim to 50 chars
SAFE_NAME=$(echo "$RAW_QUOTE" | sed 's/[^a-zA-Z0-9 ]/ /g' | tr -s ' ' | cut -c1-50 | xargs)
FINAL_OUT="$OUTPUT_DIR/${SAFE_NAME}.mp4"

# 6. LOGO TIMING
logo_start=$(awk -v d="$VIDEO_DUR" 'BEGIN{printf "%.2f", d/2}')
logo_fade=$(awk -v d="$VIDEO_DUR" 'BEGIN{printf "%.2f", d-1}')

# 7. THE FILTER
# We use the textfile approach here because it is the ONLY 100% reliable way 
# to keep newlines intact across different FFmpeg versions on Linux.
FILTER="[1:v]scale=200:-1,format=rgba,fade=t=in:st=${logo_start}:d=1:alpha=1,fade=t=out:st=${logo_fade}:d=1:alpha=1[logo]; \
[0:v][logo]overlay=x=(W-w)/2:y=H-h-150[v_logo]; \
[v_logo]drawtext=fontfile='${LOCAL_FONT}':textfile='$TMP/final_text.txt':fontcolor=white:fontsize=55: \
box=1:boxcolor=black@0.6:boxborderw=25:line_spacing=15:x=(w-text_w)/2:y=(h-text_h)/2"

# 8. FINAL RENDER
ffmpeg -i "$MERGED_AUDIO" -i "$LOGO_PATH" \
  -filter_complex "$FILTER" \
  -c:v libx264 -preset fast -crf 22 -c:a copy -movflags +faststart "$FINAL_OUT" -y

echo "🎬 Output created: $FINAL_OUT"

# Clean up
rm -rf "$TMP"
