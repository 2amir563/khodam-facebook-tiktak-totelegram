#!/bin/bash
# Telegram Media Downloader Bot - Complete Installer for Fresh Servers (V15 - Final Fix)

set -e # Exit immediately if a command exits with a non-zero status

echo "=============================================="
echo "🤖 Telegram Media Downloader Bot - Universal (V15)"
echo "=============================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Helper functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash install.sh"
    exit 1
fi

# Ask for bot token
echo "🔑 Enter your bot token from @BotFather:"
read -p "📝 Bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "Bot token is required!"
    exit 1
fi

print_status "Starting installation process..."

# ============================================
# STEP 1: System Update & Essential Tools
# ============================================
print_status "Updating system packages..."
apt-get update -y
apt-get upgrade -y

print_status "Installing essential tools..."
apt-get install -y curl wget nano htop screen unzip pv git

# ============================================
# STEP 2: Install Python, PIP, and FFmpeg
# ============================================
print_status "Checking Python installation..."

if ! command -v python3 &> /dev/null; then
    print_status "Installing Python3..."
    apt-get install -y python3
fi

if ! command -v pip3 &> /dev/null; then
    print_status "Installing Python3-PIP (Package Installer)..."
    apt-get install -y python3-pip
fi

print_status "Installing FFmpeg..."
apt-get install -y ffmpeg

# V14 FIX: Remove system's youtube-dl/yt-dlp to prevent conflicts with pip version
print_status "Removing conflicting system youtube-dl/yt-dlp package..."
apt-get remove -y youtube-dl yt-dlp 2>/dev/null || true


# ============================================
# STEP 3: Create Project Structure
# ============================================
print_status "Creating project directory..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

mkdir -p downloads logs cookies tmp
chmod 777 downloads logs cookies tmp

# ============================================
# STEP 4: Install Python Packages
# ============================================
print_status "Installing Python packages..."

cat > requirements.txt << 'REQEOF'
python-telegram-bot>=20.7
python-dotenv>=1.0.0
yt-dlp>=2024.4.9
aiofiles>=23.2.1
requests>=2.31.0
psutil>=5.9.8
REQEOF

python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

print_status "Core packages installed successfully."

# ============================================
# STEP 5: Create Configuration
# ============================================
print_status "Creating configuration files..."

cat > .env << ENVEOF
BOT_TOKEN=${BOT_TOKEN}
MAX_FILE_SIZE=2000
DELETE_AFTER_MINUTES=2
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
ENVEOF

print_status "Configuration created."

# ============================================
# STEP 6: Create Bot File (bot.py - V15: NameError Fix)
# ============================================
print_status "Creating bot main file (bot.py - V15)..."

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - UNIVERSAL VERSION (v15 - NameError Fix)
Fixed: Missing 'handle_url' function definition.
"""

import os
import sys
import logging
import subprocess
import asyncio
import re
from pathlib import Path
from datetime import datetime
from urllib.parse import urlparse, unquote

import psutil 
from telegram import Update
from telegram.ext import (
    Application, 
    CommandHandler, 
    MessageHandler, 
    filters, 
    ContextTypes
)
from telegram.constants import ParseMode
from dotenv import load_dotenv

# Load environment
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))
USER_AGENT = os.getenv("USER_AGENT", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

if not BOT_TOKEN:
    print("ERROR: BOT_TOKEN is missing in .env file.")
    sys.exit(1)

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('logs/bot.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

def clean_url(text):
    """Clean URL from text"""
    if not text:
        return None
    
    text = text.strip()
    url_pattern = r'(https?://[^\s<>"\']+|www\.[^\s<>"\']+\.[a-z]{2,})'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    
    if matches:
        url = matches[0]
        if not url.startswith(('http://', 'https://')):
            url = 'https://' + url
            
        url = re.sub(r'[.,;:!?]+$', '', url)
        url = unquote(url)
        
        return url
    
    return None

def format_size(bytes_val):
    """Format file size"""
    if bytes_val is None:
        return "Unknown"
    
    try:
        bytes_val = float(bytes_val)
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_val < 1024.0:
                return f"{bytes_val:.1f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:.1f} TB"
    except:
        return "Unknown"

async def download_video(url, output_path):
    """Download video using yt-dlp with optimized options (V14/V15)"""
    
    download_format = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
    
    cmd = [
        "python3", "-m", "yt_dlp",
        "-f", download_format, 
        "-o", output_path,
        "--no-warnings",
        "--ignore-errors",
        "--no-playlist",
        "--concurrent-fragments", "4",
        "--limit-rate", "10M",
        # --- Advanced Options for stability ---
        "--retries", "15",
        "--fragment-retries", "15",
        "--buffer-size", "256K",
        "--user-agent", USER_AGENT, 
        # V14 FIX: Removed geo-bypass options to resolve Geo/XFF error
        "--no-check-certificate", 
        "--referer", "https://google.com/",
        "--http-chunk-size", "10M",
        # ------------------------------------
        url
    ]
    
    # Add cookies if available
    cookies_file = "cookies/cookies.txt"
    if os.path.exists(cookies_file):
        cmd.extend(["--cookies", cookies_file])
    
    logger.info(f"Initiating download for: {url}")
    
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Timeout to prevent infinite hang
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=480) 
        except asyncio.TimeoutError:
            process.kill()
            logger.error(f"Download Timeout (480s) for: {url}")
            return False, "Timeout (8 minutes) - Server might be too slow or file too large."
        
        if process.returncode == 0:
            logger.info(f"yt-dlp finished successfully for: {url}")
            return True, "Success"
        else:
            error_output = stderr.decode('utf-8', errors='ignore')
            
            # --- Better Error Parsing ---
            error_summary = "Unknown Download Error"
            
            if "HTTP Error 403" in error_output or "Forbidden" in error_output or "Access Denied" in error_output or "HTTP Error 412" in error_output:
                error_summary = "Access Denied (403/412/Blocked). Requires Cookies."
            elif "HTTP Error 404" in error_output or "NOT FOUND" in error_output:
                error_summary = "File Not Found (404). Check URL validity."
            elif "logged-in" in error_output or "--cookies" in error_output:
                error_summary = "Login Required (Vimeo/Private). You MUST provide cookies.txt."
            elif "Requested format is not available" in error_output:
                error_summary = "Format Not Found. The link might be broken or not a video."
            else:
                lines = [line.strip() for line in error_output.split('\n') if line.strip()]
                error_summary = lines[-1][:200] if lines else "Unknown Download Error"

            logger.error(f"yt-dlp failed for {url}: {error_output}")
            return False, f"Download error: {error_summary}"
            
    except Exception as e:
        logger.error(f"Exception during download: {e}")
        return False, f"Internal Error: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = f"""
🤖 *UNIVERSAL Media Downloader Bot - V15*

✅ *Supported Sites:*
• Supports almost all sites compatible with yt-dlp.

📝 *How to Use:*
1. Send any media URL.
2. The bot will download and send the file.

⚡ *Features:*
✅ Fully functional core after NameError fix.
✅ Automatic file deletion after {DELETE_AFTER} minutes
✅ Max file size: {MAX_SIZE_MB}MB

🍪 *Cookie Setup (CRITICAL for Access):*
For links requiring login or restricted access:
Place your `cookies.txt` file here:
`/opt/telegram-media-bot/cookies/`
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages - V15: This function was missing!"""
    original_text = update.message.text
    url = clean_url(original_text)
    
    if not url:
        await update.message.reply_text(
            "❌ *Invalid URL*\nPlease send a valid URL starting with http:// or https://",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Detect site
    try:
        parsed = urlparse(url)
        site_name = parsed.netloc.split('.')[-2] if parsed.netloc.count('.') >= 2 else parsed.netloc.split('.')[0]
        site = site_name.replace('www.', '').split(':')[0]
    except:
        site = "Unknown"
    
    # Initial message
    msg = await update.message.reply_text(
        f"🔗 *Processing URL*\n\n"
        f"Site: *{site.upper()}*\n"
        f"URL: `{url[:50]}...`\n\n"
        f"Starting download...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name = site 
    filename = f"{safe_name}_{timestamp}"
    output_template = f"downloads/{filename}.%(ext)s"
    
    # Download
    await msg.edit_text(
        f"📥 *Downloading...*\n\n"
        f"Site: {site.upper()}\n"
        f"Please wait (Max 8 minutes)...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    success, result = await download_video(url, output_template)
    
    # If download fails, report error with more details
    if not success:
        
        if "Login Required" in result:
             error_message = (
                f"❌ *Download Failed (Login Required)*\n\n"
                f"Error: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *Solution:* This link is private or requires login.\n"
                f"Please place your `cookies.txt` file in `/opt/telegram-media-bot/cookies/`."
            )
        elif "Access Denied" in result:
            error_message = (
                f"❌ *Download Failed (Access Blocked)*\n\n"
                f"Error: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *Solution:* Server rejected access (403/412).\n"
                f"If the link is public, check network access or provide `cookies.txt`."
            )
        elif "File Not Found" in result:
            error_message = (
                f"❌ *Download Failed (404)*\n\n"
                f"Error: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *Solution:* The provided URL does not point to an existing file/page."
            )
        else:
             error_message = (
                f"❌ *Download Failed*\n\n"
                f"Error: `{result}`\n\n"
                f"Possible reasons:\n"
                f"• URL is inaccessible or broken.\n"
                f"• Cookies file (`cookies.txt`) is required.\n"
                f"• Content is restricted (Geo/Private)."
            )

        await msg.edit_text(error_message, parse_mode=ParseMode.MARKDOWN)
        return
    
    # Find downloaded file
    downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
    downloaded_files.sort(key=lambda p: p.stat().st_size, reverse=True)
    
    if not downloaded_files:
        await msg.edit_text(
            "❌ Download completed but the final file was not found.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    file_path = downloaded_files[0]
    file_size = file_path.stat().st_size
    
    # Check size
    if file_size > (MAX_SIZE_MB * 1024 * 1024):
        # Clean up all related downloaded files
        for p in downloaded_files:
            if p.exists():
                p.unlink()
        
        await msg.edit_text(
            f"❌ *File Too Large*\n\n"
            f"Size: {format_size(file_size)}\n"
            f"Limit: {MAX_SIZE_MB}MB",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Upload to Telegram
    await msg.edit_text(
        f"📤 *Uploading...*\n\n"
        f"File: {file_path.name}\n"
        f"Size: {format_size(file_size)}\n\n"
        f"This may take a moment...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    try:
        with open(file_path, 'rb') as file:
            file_ext = file_path.suffix.lower()
            caption_text = (
                f"✅ *Download Complete!*\n\n"
                f"Site: {site.upper()}\n"
                f"Size: {format_size(file_size)}\n"
                f"Auto-deletes in {DELETE_AFTER} minutes"
            )
            
            # Smart media type detection
            if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']:
                await update.message.reply_photo(photo=file, caption=caption_text, parse_mode=ParseMode.MARKDOWN)
            elif file_ext in ['.mp3', '.m4a', '.wav', '.ogg', '.flac']:
                await update.message.reply_audio(audio=file, caption=caption_text, parse_mode=ParseMode.MARKDOWN)
            else: # Default to video (covers mp4, webm, etc.)
                await update.message.reply_video(
                    video=file, 
                    caption=caption_text, 
                    parse_mode=ParseMode.MARKDOWN,
                    supports_streaming=True
                )
        
        # Final status update
        await msg.edit_text(
            f"🎉 *SUCCESS!*",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Auto delete after delay
        async def delete_files_after_delay():
            await asyncio.sleep(DELETE_AFTER * 60)
            for p in downloaded_files:
                if p.exists():
                    try:
                        p.unlink()
                        logger.info(f"Auto-deleted file: {p.name}")
                    except Exception as e:
                        logger.error(f"Failed to delete {p.name}: {e}")

        asyncio.create_task(delete_files_after_delay())
        
    except Exception as upload_error:
        logger.error(f"Upload error: {upload_error}")
        await msg.edit_text(
            f"❌ *Upload Failed*\n\n"
            f"Error: {str(upload_error)[:200]}",
            parse_mode=ParseMode.MARKDOWN
        )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = f"""
🆘 *HELP GUIDE (V15)*

📋 *How to Use:*
1. Send any media URL.
2. The bot automatically handles the download.
3. Receive the file in Telegram.
4. Files are auto-deleted after {DELETE_AFTER} minutes.

🌐 *Supported Sites:*
- Almost all sites supported by yt-dlp.

⚙️ *Cookie Setup (CRITICAL for Access):*
To bypass login/access errors, place your `cookies.txt` file in: `/opt/telegram-media-bot/cookies/`

📏 *Limits:*
- Max file size: {MAX_SIZE_MB}MB
- Auto-delete: {DELETE_AFTER} minutes
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    
    cpu = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    status_text = f"""
📊 *BOT STATUS (V15)*

🖥 *System:*
• CPU: {cpu:.1f}%
• RAM: {memory.percent:.1f}% ({format_size(memory.available)} Free)
• Disk: {disk.percent:.1f}% ({format_size(disk.free)} Free)

🤖 *Bot:*
• Version: V15 (NameError Fixed)
• Max size: {MAX_SIZE_MB}MB
• Auto-delete: {DELETE_AFTER} min
• Status: ✅ Running

💡 *Quick Commands:*
/start - Welcome message
/help - Guide
/status - Bot status
"""
    await update.message.reply_text(status_text, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Unhandled error: {context.error}")
    if update and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "❌ An internal error occurred. Please try again.",
                parse_mode=ParseMode.MARKDOWN
            )
        except Exception as e:
            logger.error(f"Failed to send error message: {e}")

def main():
    """Main function"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot - V15 (Starting)")
    print("=" * 60)
    print(f"Token: {BOT_TOKEN[:20]}...")
    print(f"Max size: {MAX_SIZE_MB}MB")
    print("=" * 60)
    
    app = Application.builder().token(BOT_TOKEN).build()
    
    # V15 FIX: handle_url is now defined above this point
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    app.add_error_handler(error_handler)
    
    print("✅ Bot polling started...")
    
    try:
        app.run_polling(
            allowed_updates=Update.ALL_TYPES,
            drop_pending_updates=True,
            timeout=30
        )
    except Exception as e:
        logger.critical(f"Bot failed to start polling: {e}")
        sys.exit(1)


if __name__ == "__main__":
    if not os.access(__file__, os.X_OK):
        try:
            os.chmod(__file__, 0o755) 
        except Exception as e:
            pass
    main()
PYEOF

# Make bot executable
chmod +x bot.py

# ============================================
# STEP 7: Create Systemd Service (No Change)
# ============================================
print_status "Creating systemd service..."
# Find the exact path of python3
PYTHON_PATH=$(which python3)

cat > /etc/systemd/system/telegram-media-bot.service << SERVICEEOF
[Unit]
Description=Telegram Media Downloader Bot
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=10
User=root
WorkingDirectory=/opt/telegram-media-bot
ExecStart=${PYTHON_PATH} /opt/telegram-media-bot/bot.py
StandardOutput=append:/opt/telegram-media-bot/logs/bot.log
StandardError=append:/opt/telegram-media-bot/logs/bot-error.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable telegram-media-bot.service

# ============================================
# STEP 8: Create Management Scripts (No Change)
# ============================================
print_status "Creating management scripts..."

cat > start-bot.sh << 'EOF'
#!/bin/bash
systemctl start telegram-media-bot.service
echo "Bot started"
EOF

cat > stop-bot.sh << 'EOF'
#!/bin/bash
systemctl stop telegram-media-bot.service
echo "Bot stopped"
EOF

cat > restart-bot.sh << 'EOF'
#!/bin/bash
systemctl restart telegram-media-bot.service
echo "Bot restarted"
EOF

cat > bot-status.sh << 'EOF'
#!/bin/bash
systemctl status telegram-media-bot.service
EOF

cat > bot-logs.sh << 'EOF'
#!/bin/bash
tail -f /opt/telegram-media-bot/logs/bot.log
EOF

chmod +x *.sh

# ============================================
# STEP 9: Start Service
# ============================================
print_status "Starting bot service..."
systemctl start telegram-media-bot.service
sleep 3

# ============================================
# STEP 10: Show Final Instructions
# ============================================
echo ""
echo "================================================"
echo "🎉 INSTALLATION COMPLETE (V15 - FINAL CODE FIX)"
echo "================================================"
echo "💡 The NameError (handle_url) has been resolved."
echo "✅ The bot should now be fully functional."
echo ""
echo "⚙️ FINAL CHECK COMMANDS:"
echo "------------------------------------------------"
echo "A) Check Service Status:"
echo "   systemctl status telegram-media-bot"
echo "B) View Live Logs:"
echo "   tail -f /opt/telegram-media-bot/logs/bot.log"
echo "------------------------------------------------"
echo "================================================"
