#!/bin/bash
# ===========================================
# Telegram Media Downloader Bot - UNIVERSAL VERSION
# Version 7.0 - Fixed for Ubuntu 22.04
# ============================================

set -e  # Exit on error

echo "==============================================="
echo "🤖 Telegram Media Downloader Bot - UNIVERSAL VERSION"
echo "==============================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root or use: sudo bash install.sh"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Ask for bot token
echo "🔑 Enter your bot token from @BotFather:"
echo "Example: 1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ"
echo ""
read -p "📝 Bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "Bot token is required!"
    exit 1
fi

print_status "Starting installation..."

# ============================================
# STEP 1: Update System
# ============================================
print_status "Updating system packages..."
apt-get update
apt-get upgrade -y

# ============================================
# STEP 2: Install System Dependencies
# ============================================
print_status "Installing system dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    ffmpeg \
    curl \
    wget \
    cron \
    nano \
    htop \
    unzip \
    pv \
    screen \
    atomicparsley \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    build-essential \
    python3-dev \
    jq

# ============================================
# STEP 3: Create Project Directory
# ============================================
print_status "Creating project directory..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create necessary directories
mkdir -p downloads logs cookies tmp
chmod 755 downloads logs cookies tmp

# ============================================
# STEP 4: Install Python Dependencies (FIXED)
# ============================================
print_status "Installing Python dependencies..."

# First upgrade pip without problematic options
python3 -m pip install --upgrade pip

# Install dependencies one by one (compatible with older pip)
print_status "Installing python-telegram-bot..."
python3 -m pip install python-telegram-bot==20.7

print_status "Installing yt-dlp..."
python3 -m pip install yt-dlp==2024.4.9

print_status "Installing other dependencies..."
python3 -m pip install python-dotenv==1.0.0
python3 -m pip install aiofiles==23.2.1
python3 -m pip install psutil==5.9.8
python3 -m pip install requests==2.31.0
python3 -m pip install beautifulsoup4==4.12.3
python3 -m pip install lxml==4.9.4
python3 -m pip install pillow==10.2.0
python3 -m pip install brotli==1.1.0

# ============================================
# STEP 5: Create Configuration Files
# ============================================
print_status "Creating configuration files..."

# Create .env file
cat > .env << EOF
# Telegram Bot Configuration
BOT_TOKEN=${BOT_TOKEN}

# Server Settings
MAX_FILE_SIZE=2000  # MB
DELETE_AFTER_MINUTES=2
CONCURRENT_DOWNLOADS=1
MAX_RETRIES=3
SERVER_WEAK_MODE=true

# yt-dlp Settings
YTDLP_COOKIES_FILE=cookies/cookies.txt
YTDLP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
YTDLP_MAX_DOWNLOAD_SIZE=2000M

# Bot Settings
ENABLE_QUALITY_SELECTION=false
SHOW_FILE_SIZE=true
AUTO_CLEANUP=true
EOF

print_status "Created .env file with your bot token"

# ============================================
# STEP 6: Create Simple Bot File
# ============================================
print_status "Creating bot main file..."

cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - Simple Version
Compatible with Ubuntu 22.04
"""

import os
import sys
import logging
import subprocess
import asyncio
from pathlib import Path
from datetime import datetime
import re

from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.constants import ParseMode
from dotenv import load_dotenv

# Load environment
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")

if not BOT_TOKEN:
    print("ERROR: BOT_TOKEN not found in .env file")
    sys.exit(1)

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('/opt/telegram-media-bot/logs/bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def clean_url(text):
    """Extract URL from text"""
    if not text:
        return None
    
    # Simple URL detection
    text = text.strip()
    url_pattern = r'https?://[^\s<>"\']+|www\.[^\s<>"\']+\.[a-z]{2,}'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    
    if matches:
        url = matches[0]
        if not url.startswith(('http://', 'https://')):
            if url.startswith('www.'):
                url = 'https://' + url
            else:
                url = 'https://' + url
        return url
    
    return None

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = """
🤖 *Telegram Media Downloader Bot*

✅ *Supports:*
• YouTube, TikTok, Instagram
• Facebook, Twitter/X
• Reddit, Pinterest
• Twitch, Vimeo
• Dailymotion, Streamable

📝 *How to use:*
1. Send any media URL
2. Bot downloads automatically
3. Receive file in Telegram

⚡ *Features:*
✅ Auto-download
✅ File size limits
✅ Works on all servers
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    url = clean_url(update.message.text)
    
    if not url:
        await update.message.reply_text("❌ Please send a valid URL starting with http:// or https://")
        return
    
    # Get domain name
    domain = url.split('/')[2] if '//' in url else url.split('/')[0]
    domain = domain.replace('www.', '').split('.')[0]
    
    # Initial message
    msg = await update.message.reply_text(f"🔗 Processing {domain.upper()} URL...")
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{domain}_{timestamp}"
    output_template = f"/opt/telegram-media-bot/downloads/{filename}.%(ext)s"
    
    try:
        # Download with yt-dlp
        await msg.edit_text("⬇️ Downloading... Please wait.")
        
        cmd = [
            "yt-dlp",
            "-f", "best[height<=720]/best",
            "-o", output_template,
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
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='ignore')[:200]
            await msg.edit_text(f"❌ Download failed:\n`{error}`")
            return
        
        # Find downloaded file
        downloaded_files = list(Path("/opt/telegram-media-bot/downloads").glob(f"{filename}.*"))
        if not downloaded_files:
            await msg.edit_text("❌ File not found after download.")
            return
        
        file_path = downloaded_files[0]
        file_size = file_path.stat().st_size
        
        # Check size (2000MB limit)
        if file_size > (2000 * 1024 * 1024):
            file_path.unlink()
            await msg.edit_text("❌ File too large (max 2000MB)")
            return
        
        # Upload to Telegram
        await msg.edit_text("📤 Uploading to Telegram...")
        
        with open(file_path, 'rb') as file:
            if file_path.suffix.lower() in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
                await update.message.reply_photo(
                    photo=file,
                    caption=f"✅ Download complete!\nSize: {file_size / 1024 / 1024:.1f}MB"
                )
            else:
                await update.message.reply_video(
                    video=file,
                    caption=f"✅ Download complete!\nSize: {file_size / 1024 / 1024:.1f}MB",
                    supports_streaming=True
                )
        
        await msg.edit_text("✅ Done! File sent successfully.")
        
        # Cleanup after 2 minutes
        async def cleanup():
            await asyncio.sleep(120)  # 2 minutes
            if file_path.exists():
                file_path.unlink()
                logger.info(f"Cleaned up: {file_path.name}")
        
        asyncio.create_task(cleanup())
        
    except asyncio.TimeoutError:
        await msg.edit_text("❌ Timeout (5 minutes). Try a smaller video.")
    except Exception as e:
        logger.error(f"Error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)[:200]}")

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
🆘 *HELP GUIDE*

📋 *How to use:*
1. Send any media URL
2. Bot downloads automatically
3. Receive file in Telegram

🌐 *Supported sites:*
- YouTube, TikTok, Instagram
- Facebook, Twitter/X
- Reddit, Pinterest
- Twitch, Vimeo
- Dailymotion, Streamable

⚙️ *Limits:*
- Max file size: 2000MB
- Auto-cleanup: 2 minutes
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

def main():
    """Main function"""
    print("Starting Telegram Media Downloader Bot...")
    
    app = Application.builder().token(BOT_TOKEN).build()
    
    # Add handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    
    print("Bot is starting...")
    print("Send /start to your bot in Telegram")
    
    app.run_polling(
        allowed_updates=Update.ALL_TYPES,
        drop_pending_updates=True
    )

if __name__ == "__main__":
    main()
EOF

# Make bot executable
chmod +x bot.py

# ============================================
# STEP 7: Create Systemd Service
# ============================================
print_status "Creating systemd service..."

cat > /etc/systemd/system/telegram-media-bot.service << 'EOF'
[Unit]
Description=Telegram Media Downloader Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/telegram-media-bot
ExecStart=/usr/bin/python3 /opt/telegram-media-bot/bot.py
Restart=always
RestartSec=10
StandardOutput=append:/opt/telegram-media-bot/logs/bot.log
StandardError=append:/opt/telegram-media-bot/logs/bot-error.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable telegram-media-bot.service

# ============================================
# STEP 8: Create Management Scripts
# ============================================
print_status "Creating management scripts..."

# Start script
cat > start-bot.sh << 'EOF'
#!/bin/bash
cd /opt/telegram-media-bot
python3 bot.py
EOF

# Stop script
cat > stop-bot.sh << 'EOF'
#!/bin/bash
systemctl stop telegram-media-bot.service
echo "Bot stopped"
EOF

# Restart script
cat > restart-bot.sh << 'EOF'
#!/bin/bash
systemctl restart telegram-media-bot.service
echo "Bot restarted"
EOF

# Status script
cat > bot-status.sh << 'EOF'
#!/bin/bash
systemctl status telegram-media-bot.service
EOF

# Logs script
cat > bot-logs.sh << 'EOF'
#!/bin/bash
tail -f /opt/telegram-media-bot/logs/bot.log
EOF

# Make scripts executable
chmod +x start-bot.sh stop-bot.sh restart-bot.sh bot-status.sh bot-logs.sh

# ============================================
# STEP 9: Start the Bot
# ============================================
print_status "Starting bot service..."
systemctl start telegram-media-bot.service

sleep 3

if systemctl is-active --quiet telegram-media-bot.service; then
    print_status "✅ Bot service is running!"
else
    print_warning "⚠️ Service might need manual start."
    print_info "Try: systemctl start telegram-media-bot.service"
fi

# ============================================
# FINAL MESSAGE
# ============================================
echo ""
echo "==============================================="
echo "📦 INSTALLATION COMPLETE"
echo "==============================================="
echo "📁 Directory: /opt/telegram-media-bot"
echo "🤖 Bot token: Saved in .env file"
echo "📝 Logs: /opt/telegram-media-bot/logs/bot.log"
echo ""
echo "🚀 TO START USING:"
echo "1. Go to Telegram"
echo "2. Find your bot"
echo "3. Send /start command"
echo "4. Send any media URL"
echo ""
echo "⚙️ MANAGEMENT:"
echo "cd /opt/telegram-media-bot"
echo "./start-bot.sh    # Start manually"
echo "./stop-bot.sh     # Stop"
echo "./restart-bot.sh  # Restart"
echo "./bot-status.sh   # Check status"
echo "./bot-logs.sh     # View logs"
echo ""
echo "🐛 TROUBLESHOOTING:"
echo "tail -f /opt/telegram-media-bot/logs/bot.log"
echo "systemctl status telegram-media-bot.service"
echo "==============================================="
