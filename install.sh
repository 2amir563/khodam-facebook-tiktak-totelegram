#!/bin/bash

# =========================================================
#             Integrated Telegram Downloader Bot Setup
# =========================================================
# This script installs dependencies, configures the environment,
# extracts the Python bot code, and runs the bot in the background.

BOT_FILE="bot.py"
ENV_FILE=".env"

# 1. Update packages and install prerequisites
echo "🛠️ Updating system packages and installing Python, Git, and Curl..."
sudo apt update
sudo apt install -y python3 python3-pip git curl libmagic1

# 2. Install yt-dlp (the core downloader tool)
echo "⬇️ Installing yt-dlp for download management..."
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp

# 3. Create virtual environment and install Python libraries
echo "🐍 Creating virtual environment and installing required Python libraries..."
python3 -m venv venv
source venv/bin/activate
pip install python-telegram-bot python-dotenv

# 4. Configure Bot Token
echo "🤖 Please enter your Telegram Bot Token (obtained from BotFather):"
read BOT_TOKEN
echo "BOT_TOKEN=$BOT_TOKEN" > $ENV_FILE
echo "Token saved to $ENV_FILE."

# 5. Extract Python Code and Save to bot.py
echo "📝 Extracting and saving bot logic code to $BOT_FILE..."
cat << 'EOF_PYTHON_CODE' > $BOT_FILE
# =========================================================
#                       bot.py (Bot Logic)
# =========================================================
import logging
import os
import subprocess
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import Application, MessageHandler, filters, ContextTypes
import telegram.ext
import mimetypes

# Load bot token from .env file
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")

# Logging configuration
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# List of supported domains (covered by yt-dlp)
SUPPORTED_DOMAINS = [
    "tiktok.com", "facebook.com", "fb.watch", "terabox.com", "loom.com", 
    "streamable.com", "pinterest.com", "pin.it", "snapchat.com/spotlight"
]

# Start command handler
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Answers the /start command."""
    welcome_message = (
        "👋 Welcome! I am a download bot.\n\n"
        "Send me a link from the following supported platforms:\n"
        "🔸 **TikTok**\n"
        "🔸 **Facebook**\n"
        "🔸 **Terabox** (Video)\n"
        "🔸 **Loom** (Video)\n"
        "🔸 **Streamable**\n"
        "🔸 **Pinterest** (Image & Video)\n"
        "🔸 **Snapchat Spotlights**\n\n"
        "**Note:** Only public and unrestricted links will be downloaded."
    )
    await update.message.reply_text(welcome_message)

# Main link processing and download function
async def handle_link(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Downloads the received link using yt-dlp and sends the file."""
    
    chat_id = update.message.chat_id
    link = update.message.text.strip()
    
    logger.info(f"Received link from {chat_id}: {link}")

    # Check link for supported domains
    if not any(domain in link.lower() for domain in SUPPORTED_DOMAINS):
        await update.message.reply_text(
            "⚠️ This domain is not supported or the link is invalid. Please send a link from the mentioned platforms."
        )
        return

    # Send initial message and show waiting status
    message = await update.message.reply_text(f"⏳ Processing your link... This may take a moment.\nLink: `{link}`", parse_mode='Markdown')
    
    # Define temporary output path
    temp_dir = f"./downloads/{chat_id}"
    os.makedirs(temp_dir, exist_ok=True)
    # Using %(ext)s for dynamic file extension naming
    output_template = os.path.join(temp_dir, "downloaded_file.%(ext)s")
    
    downloaded_filepath = None
    
    try:
        # --- 1. Execute yt-dlp for download ---
        
        # --max-filesize 50M: Telegram file size limit for non-document files
        command = [
            "yt-dlp",
            "-f", "best",
            "--max-filesize", "50M", 
            "--restrict-filenames",
            "--no-warnings",
            "--print", "filepath", 
            link,
            "-o", output_template
        ]
        
        # Execute command
        process = subprocess.run(command, check=True, capture_output=True, text=True)
        
        # Get the exact downloaded file path from yt-dlp output
        downloaded_filepath = process.stdout.strip().split('\n')[-1]
        
        # --- 2. Send File ---
        
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=message.message_id,
            text="✅ Download complete. Sending file..."
        )
        
        # Determine file type for correct sending (video or photo)
        # Using mimetypes or file command to check content type
        try:
             # Use the 'file' command which is more reliable than mimetypes for downloads
            mime_type_process = subprocess.run(['file', '-b', '--mime-type', downloaded_filepath], capture_output=True, text=True, check=True)
            mime_type = mime_type_process.stdout.strip()
        except subprocess.CalledProcessError:
            mime_type, _ = mimetypes.guess_type(downloaded_filepath)
            mime_type = mime_type if mime_type else 'application/octet-stream'


        with open(downloaded_filepath, 'rb') as f:
            if mime_type.startswith('video'):
                await context.bot.send_video(
                    chat_id,
                    video=f,
                    caption=f"🎥 Downloaded from: {link}",
                    supports_streaming=True
                )
            elif mime_type.startswith('image'):
                await context.bot.send_photo(
                    chat_id,
                    photo=f,
                    caption=f"🖼 Downloaded from: {link}"
                )
            else:
                await context.bot.send_document(
                    chat_id,
                    document=f,
                    caption=f"📄 Downloaded from: {link}"
                )

    except subprocess.CalledProcessError as e:
        error_message = f"❌ An error occurred during download:\n\n`{e.stderr.splitlines()[-1]}`"
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=message.message_id,
            text=error_message,
            parse_mode='Markdown'
        )
        logger.error(f"yt-dlp error: {e.stderr}")
        
    except Exception as e:
        error_message = f"❌ An unknown bot error occurred: {type(e).__name__}"
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=message.message_id,
            text=error_message
        )
        logger.error(f"Unknown error: {e}")

    finally:
        # --- 3. Cleanup downloaded files ---
        if downloaded_filepath and os.path.exists(downloaded_filepath):
            os.remove(downloaded_filepath)
        # Cleanup temporary directory (if empty)
        if os.path.exists(temp_dir) and not os.listdir(temp_dir):
            os.rmdir(temp_dir)
        
def main() -> None:
    """Sets up and runs the bot."""
    if not BOT_TOKEN:
        logger.error("🚨 Bot token (BOT_TOKEN) is not configured in .env file.")
        return

    application = Application.builder().token(BOT_TOKEN).build()

    application.add_handler(telegram.ext.CommandHandler("start", start_command))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_link))

    logger.info("🟢 Downloader bot started. (Polling)")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
EOF_PYTHON_CODE

# 6. Run the Bot
echo "🚀 Running the bot..."

# Activate virtual environment
source venv/bin/activate

# Run the bot in the background using nohup
nohup python3 $BOT_FILE &

echo ""
echo "--------------------------------------------------------"
echo "✅ Bot installation and execution complete."
echo "💡 The bot is running in the background."
echo "💡 To view bot status/logs: cat nohup.out"
echo "💡 To stop the bot: pkill -f $BOT_FILE"
echo "--------------------------------------------------------"
