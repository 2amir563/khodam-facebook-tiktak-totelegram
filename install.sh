#!/bin/bash
# Telegram Media Downloader Bot - Complete Installer for Fresh Servers
# Compatible with Ubuntu/Debian fresh installations

set -e  # Exit on error

echo "=============================================="
echo "🤖 Telegram Media Downloader Bot"
echo "=============================================="
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root: sudo bash install.sh"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Ask for bot token
echo "🔑 Enter your bot token from @BotFather:"
read -p "📝 Bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "Bot token is required!"
    exit 1
fi

print_status "Starting installation on fresh server..."

# ============================================
# STEP 1: System Update
# ============================================
print_status "Updating system packages..."
apt-get update
apt-get upgrade -y

print_status "Installing essential tools..."
apt-get install -y curl wget nano htop screen unzip pv

# ============================================
# STEP 2: Install Python and Dependencies
# ============================================
print_status "Checking Python installation..."

# Install Python if not exists
if ! command -v python3 &> /dev/null; then
    print_status "Installing Python3..."
    apt-get install -y python3 python3-pip
fi

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1)
print_status "Found $PYTHON_VERSION"

# Install FFmpeg
print_status "Installing FFmpeg..."
apt-get install -y ffmpeg

# ============================================
# STEP 3: Create Project Structure
# ============================================
print_status "Creating project directory..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create directories
mkdir -p downloads logs cookies tmp
chmod 755 downloads logs cookies tmp

# ============================================
# STEP 4: Install Python Packages
# ============================================
print_status "Installing Python packages..."

# Create requirements file
cat > requirements.txt << 'REQEOF'
python-telegram-bot==20.7
python-dotenv==1.0.0
yt-dlp==2024.4.9
aiofiles==23.2.1
requests==2.31.0
REQEOF

# Install packages
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

print_status "✅ Core packages installed"

# ============================================
# STEP 5: Create Configuration
# ============================================
print_status "Creating configuration files..."

# Create .env file
cat > .env << ENVEOF
BOT_TOKEN=${BOT_TOKEN}
MAX_FILE_SIZE=2000
DELETE_AFTER_MINUTES=2
ENVEOF

print_status "✅ Configuration created"

# ============================================
# STEP 6: Create Bot File
# ============================================
print_status "Creating bot main file..."

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
"""
Simple Telegram Media Downloader Bot
Works on fresh servers
"""

import os
import sys
import logging
import subprocess
import asyncio
import re
from pathlib import Path
from datetime import datetime
from urllib.parse import urlparse

from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.constants import ParseMode
from dotenv import load_dotenv

# Load config
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))

if not BOT_TOKEN:
    print("ERROR: BOT_TOKEN not found in .env")
    sys.exit(1)

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('logs/bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def clean_url(text):
    """Extract URL from text"""
    if not text:
        return None
    
    text = text.strip()
    url_pattern = r'https?://[^\s<>"\']+'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    
    if matches:
        return matches[0]
    return None

def format_size(bytes_val):
    """Format file size"""
    if not bytes_val:
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
    """Download video using yt-dlp"""
    try:
        cmd = [
            "yt-dlp",
            "-f", "best[height<=720]/best",
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=180)
        
        if process.returncode == 0:
            return True, "Success"
        else:
            error = stderr.decode('utf-8', errors='ignore')[:200]
            return False, f"Error: {error}"
            
    except asyncio.TimeoutError:
        return False, "Timeout (3 minutes)"
    except Exception as e:
        return False, f"Error: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = """
🤖 *Media Downloader Bot*

✅ *Working Sites:*
• Streamable (streamable.com)
• Dailymotion (dai.ly)
• Twitch clips (twitch.tv)

📝 *How to use:*
1. Send a video URL
2. Bot downloads and sends it
3. File auto-deletes after 2 minutes

⚡ *Features:*
• Max file size: 2000MB
• Auto cleanup
• Simple and fast
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    url = clean_url(update.message.text)
    
    if not url:
        await update.message.reply_text("❌ Please send a valid URL starting with http:// or https://")
        return
    
    # Get site name
    parsed = urlparse(url)
    site = parsed.netloc.replace('www.', '')
    
    # Initial message
    msg = await update.message.reply_text(f"🔗 Processing: {site}\n\nDownloading...")
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"downloads/video_{timestamp}.mp4"
    
    # Download
    success, result = await download_video(url, filename)
    
    if not success:
        await msg.edit_text(f"❌ Download failed:\n{result}")
        return
    
    # Check if file exists
    if not Path(filename).exists():
        await msg.edit_text("❌ File not found after download")
        return
    
    file_path = Path(filename)
    file_size = file_path.stat().st_size
    
    # Check size
    if file_size > (MAX_SIZE_MB * 1024 * 1024):
        file_path.unlink()
        await msg.edit_text(f"❌ File too large: {format_size(file_size)}")
        return
    
    # Upload to Telegram
    await msg.edit_text("📤 Uploading...")
    
    try:
        with open(file_path, 'rb') as file:
            await update.message.reply_video(
                video=file,
                caption=f"✅ Downloaded from {site}\nSize: {format_size(file_size)}",
                supports_streaming=True
            )
        
        await msg.edit_text(f"✅ Success! File sent.\nSize: {format_size(file_size)}")
        
        # Auto delete
        async def delete_file():
            await asyncio.sleep(DELETE_AFTER * 60)
            if file_path.exists():
                file_path.unlink()
        
        asyncio.create_task(delete_file())
        
    except Exception as e:
        logger.error(f"Upload error: {e}")
        await msg.edit_text(f"❌ Upload failed: {str(e)[:200]}")

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
🆘 *Help Guide*

Send video URLs from:
• Streamable (streamable.com)
• Dailymotion (dai.ly)
• Twitch clips (twitch.tv)

Examples:
• https://streamable.com/2ipg1n
• https://dai.ly/x7rx1hr
• https://twitch.tv/clip/example

Note: Some sites need cookies. For Pinterest/Reddit, you need to add cookies.txt file.
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Error: {context.error}")

def main():
    """Main function"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot")
    print("=" * 60)
    
    app = Application.builder().token(BOT_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    app.add_error_handler(error_handler)
    
    print("✅ Bot starting...")
    print("📱 Send /start to your bot")
    
    app.run_polling(allowed_updates=Update.ALL_TYPES, drop_pending_updates=True)

if __name__ == "__main__":
    main()
PYEOF

# Make bot executable
chmod +x bot.py

# ============================================
# STEP 7: Create Systemd Service
# ============================================
print_status "Creating systemd service..."

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
ExecStart=/usr/bin/python3 /opt/telegram-media-bot/bot.py
StandardOutput=append:/opt/telegram-media-bot/logs/bot.log
StandardError=append:/opt/telegram-media-bot/logs/bot-error.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable telegram-media-bot.service

# ============================================
# STEP 8: Create Management Scripts
# ============================================
print_status "Creating management scripts..."

cat > start-bot.sh << 'EOF'
#!/bin/bash
cd /opt/telegram-media-bot
python3 bot.py
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
echo "=============================================="
echo "🎉 INSTALLATION COMPLETE"
echo "=============================================="
echo "📁 Directory: /opt/telegram-media-bot"
echo "🤖 Bot token saved in: .env"
echo "📝 Logs: logs/bot.log"
echo ""
echo "🚀 TO START USING:"
echo "1. Go to Telegram"
echo "2. Find your bot"
echo "3. Send /start"
echo "4. Send a URL from:"
echo "   • streamable.com"
echo "   • dai.ly"
echo "   • twitch.tv/clips"
echo ""
echo "⚙️ MANAGEMENT:"
echo "cd /opt/telegram-media-bot"
echo "./start-bot.sh    # Start"
echo "./stop-bot.sh     # Stop"
echo "./restart-bot.sh  # Restart"
echo "./bot-status.sh   # Status"
echo "./bot-logs.sh     # Logs"
echo ""
echo "🐛 TROUBLESHOOTING:"
echo "tail -f logs/bot.log"
echo "systemctl status telegram-media-bot"
echo "=============================================="
