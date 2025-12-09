#!/bin/bash

# --- Section 1: Configuration ---
echo "## 🤖 Universal Social Media Downloader Bot (Powered by yt-dlp) ##"
echo "---"

# Get Bot Token
read -p "Please enter your Telegram bot token (e.g., 123456:ABC-DEF): " BOT_TOKEN

# --- Section 2: Install Prerequisites and VENV Setup ---
echo "---"
echo "🛠️ Installing system prerequisites (Python3, pip, venv, git, and FFmpeg)..."
# yt-dlp requires FFmpeg for some operations (like stitching video/audio)
sudo apt update > /dev/null 2>&1
sudo apt install -y python3 python3-pip python3-venv git ffmpeg > /dev/null 2>&1

# Create and activate a virtual environment (VENV)
echo "⚙️ Setting up virtual environment..."
python3 -m venv bot_env
source bot_env/bin/activate

# --- Section 3: Install Libraries inside VENV ---
echo "📚 Installing Python libraries (yt-dlp and python-telegram-bot) inside VENV..."
pip install yt-dlp python-telegram-bot > /dev/null 2>&1

# --- Section 4: Create and Configure Python File (Bot Logic) ---
PYTHON_SCRIPT_NAME="universal_downloader.py"
echo "🐍 Creating bot file ($PYTHON_SCRIPT_NAME) and injecting token..."

# Full Python bot content using V20+ structure and yt-dlp
cat << EOF > $PYTHON_SCRIPT_NAME
import telegram
from telegram.ext import Application, MessageHandler, filters
from telegram import Update
import yt_dlp
import os
import re
from uuid import uuid4

# Configuration: Injected from the install script
TOKEN = "$BOT_TOKEN"

# Increase timeouts to prevent TimedOut errors during long downloads/uploads
TELEGRAM_READ_TIMEOUT = 45
TELEGRAM_WRITE_TIMEOUT = 45
TELEGRAM_POOL_TIMEOUT = 90
MAX_FILE_SIZE_MB = 2000 # Telegram limit is 2048 MB

def get_yt_dlp_options(output_path):
    """Sets options for yt-dlp to handle file size and output format."""
    return {
        'outtmpl': f'{output_path}/%(title)s.%(ext)s',
        'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
        'merge_output_format': 'mp4',
        'noplaylist': True,
        'writesubtitles': True,
        'subtitlesformat': 'srt/best',
        'postprocessors': [{
            'key': 'FFmpegVideoRemuxer',
            'preferedformat': 'mp4',
        }],
        # Limit file size slightly below the Telegram maximum
        'max_filesize': MAX_FILE_SIZE_MB * 1024 * 1024, 
    }

async def handle_message(update: Update, context):
    text = update.message.text
    chat_id = update.message.chat_id
    
    # Simple check for any HTTP link
    url_match = re.search(r'https?://[^\s]+', text)
    if not url_match:
        await update.message.reply_text("Please send a valid public link (TikTok, Facebook, Pinterest, Loom, Terabox, Streamable, etc.).")
        return

    video_url = url_match.group(0)
    
    # 1. Start message and create unique temp directory
    await context.bot.send_message(chat_id, "⏳ Processing and attempting to download link... Please wait.", disable_web_page_preview=True)
    
    temp_dir = f'downloads/{uuid4()}'
    os.makedirs(temp_dir, exist_ok=True)

    try:
        ydl_opts = get_yt_dlp_options(temp_dir)
        
        # 2. Download the media using yt-dlp
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info_dict = ydl.extract_info(video_url, download=True)
            # Find the actual output file name
            file_name = ydl.prepare_filename(info_dict)
            
        # If yt-dlp successfully downloaded the file
        downloaded_files = [os.path.join(temp_dir, f) for f in os.listdir(temp_dir) if not f.endswith(('.part', '.temp', '.json', '.description'))]
        
        if not downloaded_files:
             await context.bot.send_message(chat_id, "❌ Error: Could not download the media. (Might be private, unsupported, or geo-restricted).")
             return

        file_path = downloaded_files[0]
        
        # 3. Determine media type and prepare caption
        is_video = any(ext in file_path.lower() for ext in ['.mp4', '.webm', '.mov', '.mkv'])
        
        # Extract title and uploader for caption
        title = info_dict.get('title', 'N/A')
        uploader = info_dict.get('uploader', 'N/A')
        caption = f"✅ **Title:** {title}\n**Source:** {uploader}\n**Downloaded via:** @{context.bot.username}"
        
        # 4. Send media
        if os.path.getsize(file_path) > MAX_FILE_SIZE_MB * 1024 * 1024:
             await context.bot.send_message(chat_id, "❌ File is too large. (Telegram limit: 2 GB)")
        elif is_video:
            with open(file_path, 'rb') as video_file:
                # Use a higher timeout for video upload
                await context.bot.send_video(chat_id, video_file, caption=caption, timeout=600, supports_streaming=True, parse_mode=telegram.constants.ParseMode.MARKDOWN)
        else:
            # Assume image/other file type
            with open(file_path, 'rb') as media_file:
                await context.bot.send_document(chat_id, media_file, caption=caption, parse_mode=telegram.constants.ParseMode.MARKDOWN)
        
    except Exception as e:
        error_message = f"❌ A processing error occurred: {str(e)}"
        if "Unsupported URL" in str(e):
             error_message += "\n\n(This URL is either not supported by yt-dlp or the post is private.)"
        await context.bot.send_message(chat_id, error_message)
    finally:
        # 5. Clean up temporary directory
        if os.path.exists(temp_dir):
            os.system(f'rm -rf {temp_dir}')

def main():
    # FIX: Increased timeouts to prevent TimedOut error during polling
    application = Application.builder().token(TOKEN).read_timeout(TELEGRAM_READ_TIMEOUT).write_timeout(TELEGRAM_WRITE_TIMEOUT).pool_timeout(TELEGRAM_POOL_TIMEOUT).build()
        
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    # Start polling (blocking call)
    application.run_polling()

if __name__ == '__main__':
    main()
EOF

# --- Section 5: Run the Bot ---
echo "---"
echo "🚀 Running the bot inside the VENV in the background..."

# Execute the bot using the specific Python interpreter inside the VENV
nohup ./bot_env/bin/python $PYTHON_SCRIPT_NAME > bot.log 2>&1 &

# Deactivate the shell environment
deactivate 2>/dev/null

echo "---"
echo "✅ **Bot successfully installed and running.**"
echo "The bot is public and ready to receive links. Use 'tail -f bot.log' to monitor."
echo "---"
echo "📜 Useful Commands:"
echo "* To view logs: 'tail -f bot.log'"
echo "* To stop the bot: 'pkill -f python3 $PYTHON_SCRIPT_NAME'"
