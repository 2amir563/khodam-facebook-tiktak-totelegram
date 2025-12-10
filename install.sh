#!/bin/bash
# ===========================================
# Telegram Media Downloader Bot - Complete Installer
# Version 2.0 - One Script for Fresh Server
# ============================================

set -e  # Exit on error

echo "==============================================="
echo "📦 Telegram Media Downloader Bot - Full Install"
echo "==============================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root or use: sudo bash install.sh"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Ask for bot token
echo "🔑 First, get your bot token from @BotFather on Telegram"
echo ""
echo "Steps to get token:"
echo "1. Open Telegram app"
echo "2. Search for @BotFather"
echo "3. Send /newbot command"
echo "4. Choose bot name and username"
echo "5. Copy the token (looks like: 1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ)"
echo ""
read -p "📝 Enter your bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "Bot token is required! Exiting."
    exit 1
fi

# Validate token format
if [[ ! "$BOT_TOKEN" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; then
    print_warning "Token format looks incorrect. Make sure it's from @BotFather"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
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
    screen

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
# STEP 4: Install Python Dependencies
# ============================================
print_status "Installing Python dependencies..."
pip3 install --upgrade pip
pip3 install \
    python-telegram-bot==20.7 \
    yt-dlp==2024.4.9 \
    python-dotenv==1.0.0 \
    aiofiles==23.2.1 \
    psutil==5.9.8 \
    requests==2.31.0 \
    beautifulsoup4==4.12.3 \
    pillow==10.2.0

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
YTDLP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
YTDLP_MAX_DOWNLOAD_SIZE=2000M

# Bot Settings
ENABLE_QUALITY_SELECTION=true
SHOW_FILE_SIZE=true
AUTO_CLEANUP=true
EOF

# Create main bot file
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - Simple & Efficient Version
Optimized for weak servers
"""

import os
import sys
import logging
import subprocess
import asyncio
import json
import shutil
from pathlib import Path
from datetime import datetime, timedelta
import aiofiles
import psutil

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, 
    CommandHandler, 
    MessageHandler, 
    filters, 
    ContextTypes, 
    CallbackQueryHandler
)
from telegram.constants import ParseMode
from dotenv import load_dotenv

# Load environment
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))

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

# Supported platforms
SUPPORTED_DOMAINS = [
    "youtube.com", "youtu.be",
    "tiktok.com", "douyin.com",
    "facebook.com", "fb.watch",
    "instagram.com",
    "twitter.com", "x.com",
    "reddit.com",
    "pinterest.com", "pin.it",
    "twitch.tv",
    "dailymotion.com", "dai.ly",
    "streamable.com",
    "vimeo.com",
    "rumble.com",
    "bilibili.com",
    "ted.com",
    "9gag.com",
    "imgur.com"
]

class DownloadManager:
    """Manage downloads and cleanup"""
    def __init__(self):
        self.active_downloads = {}
        self.cleanup_queue = []
        
    async def cleanup_old_files(self):
        """Clean files older than DELETE_AFTER minutes"""
        downloads_dir = Path("downloads")
        if downloads_dir.exists():
            for file in downloads_dir.iterdir():
                if file.is_file():
                    file_age = datetime.now().timestamp() - file.stat().st_mtime
                    if file_age > (DELETE_AFTER * 60):  # Convert minutes to seconds
                        try:
                            file.unlink()
                            logger.info(f"Cleaned up: {file.name}")
                        except:
                            pass

manager = DownloadManager()

def format_size(bytes):
    """Format file size"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes < 1024.0:
            return f"{bytes:.1f} {unit}"
        bytes /= 1024.0
    return f"{bytes:.1f} TB"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = f"""
🤖 *Media Downloader Bot*

📥 *Supported Platforms:*
• YouTube, TikTok, Facebook, Instagram
• Twitter, Reddit, Pinterest, Twitch
• Dailymotion, Streamable, Vimeo
• Rumble, Bilibili, TED

✨ *Features:*
✅ Quality selection
✅ Auto cleanup after {DELETE_AFTER} minutes
✅ Weak server optimized
✅ No 50MB limit

📝 *How to use:*
Send me a video URL
Choose quality
Get your file!

⚡ *Server Status:*
Max file size: {MAX_SIZE_MB}MB
Auto delete: {DELETE_AFTER} minutes
    """
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL message"""
    url = update.message.text.strip()
    
    # Check if supported
    supported = False
    for domain in SUPPORTED_DOMAINS:
        if domain in url.lower():
            supported = True
            break
    
    if not supported:
        await update.message.reply_text(
            "❌ *URL not supported*\n\n"
            "Supported platforms:\n"
            "• YouTube, TikTok, Facebook\n"
            "• Instagram, Twitter, Reddit\n"
            "• Pinterest, Twitch, etc.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Get video info
    msg = await update.message.reply_text("🔍 *Analyzing URL...*", parse_mode=ParseMode.MARKDOWN)
    
    try:
        # Get formats using yt-dlp
        cmd = [
            "yt-dlp",
            "--dump-json",
            "--no-warnings",
            "--skip-download",
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
        
        if process.returncode != 0:
            await msg.edit_text("❌ Failed to analyze URL. It might be private or restricted.")
            return
            
        info = json.loads(stdout.decode('utf-8', errors='ignore'))
        title = info.get('title', 'Unknown')
        duration = info.get('duration', 0)
        
        # Get formats
        formats = []
        for fmt in info.get('formats', []):
            if fmt.get('vcodec') != 'none':  # Video formats only
                format_id = fmt.get('format_id', 'best')
                resolution = fmt.get('resolution', 'N/A')
                filesize = fmt.get('filesize') or fmt.get('filesize_approx', 0)
                
                # Skip if too large
                if filesize and filesize > (MAX_SIZE_MB * 1024 * 1024):
                    continue
                    
                formats.append({
                    'id': format_id,
                    'resolution': resolution,
                    'size': filesize,
                    'size_str': format_size(filesize) if filesize else 'Unknown'
                })
        
        if not formats:
            # Try with best format
            formats.append({
                'id': 'best',
                'resolution': 'Best',
                'size': 0,
                'size_str': 'Unknown'
            })
        
        # Create keyboard
        keyboard = []
        for fmt in formats[:8]:  # Max 8 options
            btn_text = f"{fmt['resolution']} - {fmt['size_str']}"
            callback_data = f"dl:{url}:{fmt['id']}"
            keyboard.append([InlineKeyboardButton(btn_text, callback_data=callback_data)])
        
        keyboard.append([InlineKeyboardButton("❌ Cancel", callback_data="cancel")])
        
        await msg.edit_text(
            f"🎬 *{title[:50]}...*\n"
            f"⏱ Duration: {duration//60}:{duration%60:02d}\n"
            f"📊 Select quality:",
            reply_markup=InlineKeyboardMarkup(keyboard),
            parse_mode=ParseMode.MARKDOWN
        )
        
    except Exception as e:
        logger.error(f"Error analyzing URL: {e}")
        await msg.edit_text("❌ Error analyzing URL. Please try again.")

async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle button callbacks"""
    query = update.callback_query
    await query.answer()
    
    data = query.data
    
    if data == "cancel":
        await query.edit_message_text("❌ Download cancelled.")
        return
    
    if data.startswith("dl:"):
        _, url, quality = data.split(":", 2)
        
        await query.edit_message_text(
            f"⬇️ *Downloading...*\n"
            f"Quality: {quality}\n"
            f"Please wait...",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Start download
        asyncio.create_task(download_file(query, url, quality))

async def download_file(query, url, quality):
    """Download and send file"""
    try:
        chat_id = query.message.chat_id
        message_id = query.message.message_id
        
        # Create filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output = f"downloads/{timestamp}.%(ext)s"
        
        # Build command
        cmd = [
            "yt-dlp",
            "-f", quality,
            "-o", output,
            "--no-warnings",
            "--progress",
            "--newline",
            url
        ]
        
        # Add cookies if available
        cookies_file = "cookies/cookies.txt"
        if os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
        
        # Start download
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        # Monitor progress
        last_progress = ""
        while True:
            line = await process.stdout.readline()
            if not line:
                break
                
            line_str = line.decode('utf-8', errors='ignore').strip()
            if "[download]" in line_str:
                last_progress = line_str
                
                # Update every 10 seconds
                await query.edit_message_text(
                    f"⬇️ *Downloading...*\n"
                    f"`{line_str}`",
                    parse_mode=ParseMode.MARKDOWN
                )
        
        await process.wait()
        
        if process.returncode != 0:
            error = await process.stderr.read()
            error_text = error.decode('utf-8', errors='ignore')[:200]
            await query.edit_message_text(
                f"❌ *Download failed*\n`{error_text}`",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        # Find downloaded file
        files = list(Path("downloads").glob(f"{timestamp}.*"))
        if not files:
            await query.edit_message_text("❌ File not found after download.")
            return
        
        file_path = files[0]
        file_size = file_path.stat().st_size
        
        # Check size limit
        if file_size > (MAX_SIZE_MB * 1024 * 1024):
            file_path.unlink()
            await query.edit_message_text(
                f"❌ *File too large*\n"
                f"Size: {format_size(file_size)}\n"
                f"Limit: {MAX_SIZE_MB}MB",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        # Upload to Telegram
        await query.edit_message_text(
            f"📤 *Uploading...*\n"
            f"Size: {format_size(file_size)}",
            parse_mode=ParseMode.MARKDOWN
        )
        
        with open(file_path, 'rb') as f:
            if str(file_path).lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                await query.message.reply_photo(
                    f,
                    caption=f"📷 *Image Downloaded*\nSize: {format_size(file_size)}"
                )
            else:
                await query.message.reply_video(
                    f,
                    caption=f"🎬 *Video Downloaded*\nSize: {format_size(file_size)}",
                    supports_streaming=True
                )
        
        # Update message
        await query.edit_message_text(
            f"✅ *Download Complete!*\n"
            f"File sent successfully\n"
            f"Will auto-delete in {DELETE_AFTER} minutes",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Schedule cleanup
        await asyncio.sleep(DELETE_AFTER * 60)
        if file_path.exists():
            file_path.unlink()
            logger.info(f"Auto-deleted: {file_path.name}")
        
    except Exception as e:
        logger.error(f"Download error: {e}")
        try:
            await query.edit_message_text(f"❌ Error: {str(e)[:200]}")
        except:
            pass

async def cleanup_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Manual cleanup"""
    await manager.cleanup_old_files()
    await update.message.reply_text("🧹 Cleanup completed!")

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Server status"""
    cpu = psutil.cpu_percent()
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    status_msg = f"""
📊 *Server Status*

🖥 CPU: {cpu:.1f}%
💾 Memory: {mem.percent:.1f}% ({format_size(mem.available)} available)
💿 Disk: {disk.percent:.1f}% ({format_size(disk.free)} free)

⚙️ *Bot Settings:*
Max file: {MAX_SIZE_MB}MB
Auto delete: {DELETE_AFTER} min
    """
    await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Error handler"""
    logger.error(f"Update {update} caused error: {context.error}")

def main():
    """Main function"""
    print("🤖 Starting Telegram Media Downloader Bot...")
    
    # Create application
    app = Application.builder().token(BOT_TOKEN).build()
    
    # Add handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(CommandHandler("cleanup", cleanup_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    app.add_handler(CallbackQueryHandler(handle_callback))
    app.add_error_handler(error_handler)
    
    # Start cleanup task
    async def periodic_cleanup():
        while True:
            await manager.cleanup_old_files()
            await asyncio.sleep(300)  # Every 5 minutes
    
    # Run bot
    print("✅ Bot is running!")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
EOF

# Make bot executable
chmod +x bot.py

# ============================================
# STEP 6: Create Systemd Service
# ============================================
print_status "Creating systemd service..."

cat > /etc/systemd/system/telegram-media-bot.service << EOF
[Unit]
Description=Telegram Media Downloader Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/bot.py
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=telegram-media-bot
Environment=PYTHONUNBUFFERED=1

# Resource limits for weak server
MemoryMax=512M
CPUQuota=50%
IOWeight=100

[Install]
WantedBy=multi-user.target
EOF

# ============================================
# STEP 7: Create Cleanup Cron Job
# ============================================
print_status "Setting up auto cleanup..."

cat > /etc/cron.d/telegram-media-cleanup << EOF
*/5 * * * * root find ${INSTALL_DIR}/downloads -type f -mmin +${DELETE_AFTER_MINUTES} -delete 2>/dev/null
*/10 * * * * root find ${INSTALL_DIR}/tmp -type f -mmin +10 -delete 2>/dev/null
0 3 * * * root find ${INSTALL_DIR}/logs -name "*.log" -mtime +7 -delete 2>/dev/null
EOF

# ============================================
# STEP 8: Create Management Script
# ============================================
print_status "Creating management script..."

cat > /usr/local/bin/manage-bot << 'EOF'
#!/bin/bash
INSTALL_DIR="/opt/telegram-media-bot"

case "$1" in
    start)
        systemctl start telegram-media-bot
        echo "Bot started"
        ;;
    stop)
        systemctl stop telegram-media-bot
        echo "Bot stopped"
        ;;
    restart)
        systemctl restart telegram-media-bot
        echo "Bot restarted"
        ;;
    status)
        systemctl status telegram-media-bot --no-pager
        ;;
    logs)
        journalctl -u telegram-media-bot -f
        ;;
    logs-error)
        journalctl -u telegram-media-bot --since "1 hour ago" | grep -i error
        ;;
    update)
        cd $INSTALL_DIR
        echo "Updating yt-dlp..."
        pip3 install --upgrade yt-dlp
        systemctl restart telegram-media-bot
        echo "Update complete"
        ;;
    cleanup)
        echo "Cleaning old files..."
        find $INSTALL_DIR/downloads -type f -mmin +5 -delete
        echo "Cleanup done"
        ;;
    dir)
        echo "Bot directory: $INSTALL_DIR"
        ls -la $INSTALL_DIR/downloads/
        ;;
    config)
        nano $INSTALL_DIR/.env
        ;;
    test)
        echo "Testing bot connection..."
        curl -s https://api.telegram.org/bot$(grep BOT_TOKEN $INSTALL_DIR/.env | cut -d= -f2)/getMe | python3 -m json.tool
        ;;
    *)
        echo "Usage: manage-bot {start|stop|restart|status|logs|update|cleanup|dir|config|test}"
        echo ""
        echo "Commands:"
        echo "  start     - Start bot"
        echo "  stop      - Stop bot"
        echo "  restart   - Restart bot"
        echo "  status    - Check status"
        echo "  logs      - View live logs"
        echo "  logs-error - View error logs"
        echo "  update    - Update yt-dlp"
        echo "  cleanup   - Clean old files"
        echo "  dir       - Show download directory"
        echo "  config    - Edit config"
        echo "  test      - Test bot connection"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/manage-bot

# ============================================
# STEP 9: Start and Enable Services
# ============================================
print_status "Starting services..."

systemctl daemon-reload
systemctl enable telegram-media-bot.service
systemctl start telegram-media-bot.service

# Wait a bit for bot to start
sleep 3

# ============================================
# STEP 10: Test Installation
# ============================================
print_status "Testing installation..."

# Check if bot is running
if systemctl is-active --quiet telegram-media-bot; then
    print_status "✅ Bot is running successfully!"
else
    print_error "❌ Bot failed to start. Checking logs..."
    journalctl -u telegram-media-bot -n 10 --no-pager
    echo ""
    print_warning "Trying to start manually..."
    cd $INSTALL_DIR && python3 bot.py &
    sleep 2
fi

# Test yt-dlp
if command -v yt-dlp &> /dev/null; then
    print_status "✅ yt-dlp installed successfully"
else
    print_error "❌ yt-dlp installation failed"
fi

# ============================================
# STEP 11: Display Final Information
# ============================================
echo ""
echo "==============================================="
echo "🎉 INSTALLATION COMPLETE!"
echo "==============================================="
echo ""
echo "📋 IMPORTANT INFORMATION:"
echo "----------------------------"
echo "📁 Installation Directory: $INSTALL_DIR"
echo "🔑 Bot Token: ${BOT_TOKEN:0:15}..."  # Show only first 15 chars for security
echo ""
echo "🛠 MANAGEMENT COMMANDS:"
echo "----------------------------"
echo "manage-bot start      # Start bot"
echo "manage-bot stop       # Stop bot"
echo "manage-bot restart    # Restart bot"
echo "manage-bot status     # Check status"
echo "manage-bot logs       # View logs"
echo "manage-bot update     # Update yt-dlp"
echo "manage-bot cleanup    # Manual cleanup"
echo "manage-bot test       # Test connection"
echo ""
echo "🔧 CONFIGURATION:"
echo "----------------------------"
echo "Config file: $INSTALL_DIR/.env"
echo "Downloads: $INSTALL_DIR/downloads/"
echo "Logs: $INSTALL_DIR/logs/"
echo ""
echo "📱 HOW TO USE:"
echo "----------------------------"
echo "1. Open Telegram"
echo "2. Search for your bot"
echo "3. Send /start command"
echo "4. Send any video URL"
echo "5. Choose quality"
echo "6. Get your file!"
echo ""
echo "🔄 AUTO CLEANUP:"
echo "----------------------------"
echo "Files auto-delete after $DELETE_AFTER minutes"
echo "Cleanup runs every 5 minutes"
echo ""
echo "⚡ SERVER OPTIMIZATION:"
echo "----------------------------"
echo "• Memory limit: 512MB"
echo "• CPU limit: 50%"
echo "• Concurrent downloads: 1"
echo "• Max file size: ${MAX_SIZE_MB}MB"
echo ""
echo "==============================================="
echo "✅ Bot should be ready! Send /start on Telegram"
echo "==============================================="

# Final test
echo ""
echo "Running final test..."
sleep 2
systemctl status telegram-media-bot --no-pager | head -20
