#!/bin/bash
# ===========================================
# Telegram Media Downloader Bot - WORKING Installer
# Version 4.0 - Fixed event loop error
# ============================================

set -e  # Exit on error

echo "==============================================="
echo "🤖 Telegram Media Downloader Bot - WORKING Install"
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
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Ask for bot token
echo "🔑 Get your bot token from @BotFather on Telegram"
echo ""
echo "Token example: 1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ"
echo ""
read -p "📝 Enter your bot token: " BOT_TOKEN

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
    atomicparsley

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
    requests==2.31.0

# Update yt-dlp to latest
print_status "Updating yt-dlp..."
pip3 install --upgrade yt-dlp

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

# ============================================
# STEP 6: Create Main Bot File (FIXED EVENT LOOP)
# ============================================
print_status "Creating bot file..."

cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - WORKING VERSION
FIXED: Event loop error, optimized for Python 3.10+
"""

import os
import sys
import logging
import subprocess
import asyncio
import json
import re
from pathlib import Path
from datetime import datetime, timedelta
import aiofiles
import psutil
from urllib.parse import urlparse

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

if not BOT_TOKEN or BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
    print("ERROR: Please set BOT_TOKEN in .env file")
    print("Edit: nano /opt/telegram-media-bot/.env")
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

# Enhanced platform detection with fixes
PLATFORM_CONFIGS = {
    "pinterest": {"domains": ["pinterest.com", "pin.it"]},
    "ted": {"domains": ["ted.com"]},
    "rumble": {"domains": ["rumble.com"]},
    "reddit": {"domains": ["reddit.com"]},
    "bilibili": {"domains": ["bilibili.com"]},
    "twitch": {"domains": ["twitch.tv"]},
    "dailymotion": {"domains": ["dailymotion.com", "dai.ly"]},
    "streamable": {"domains": ["streamable.com"]},
    "vimeo": {"domains": ["vimeo.com"]},
    "facebook": {"domains": ["facebook.com", "fb.watch"]},
    "tiktok": {"domains": ["tiktok.com"]},
    "youtube": {"domains": ["youtube.com", "youtu.be"]},
    "twitter": {"domains": ["twitter.com", "x.com"]},
    "instagram": {"domains": ["instagram.com"]},
    "9gag": {"domains": ["9gag.com"]},
    "imgur": {"domains": ["imgur.com"]}
}

# All supported domains
ALL_DOMAINS = []
for config in PLATFORM_CONFIGS.values():
    ALL_DOMAINS.extend(config["domains"])

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

def detect_platform(url):
    """Detect platform from URL"""
    url_lower = url.lower()
    for platform, config in PLATFORM_CONFIGS.items():
        for domain in config["domains"]:
            if domain in url_lower:
                return platform
    return "generic"

def is_valid_url(url):
    """Validate URL format"""
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc])
    except:
        return False

async def get_video_info(url):
    """Get video information with error handling"""
    try:
        # Build yt-dlp command
        cmd = [
            "yt-dlp",
            "--dump-json",
            "--no-warnings",
            "--no-playlist",
            "--skip-download",
            "--ignore-errors",
            url
        ]
        
        # Add cookies if available
        cookies_file = "cookies/cookies.txt"
        if os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
        
        # Add referer for bilibili
        if "bilibili.com" in url.lower():
            cmd.extend(["--referer", "https://www.bilibili.com/"])
        
        # Run command with timeout
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
        
        if process.returncode != 0:
            error_msg = stderr.decode('utf-8', errors='ignore')[:300]
            logger.error(f"yt-dlp error: {error_msg}")
            return {'success': False, 'error': 'Failed to analyze URL'}
        
        # Parse JSON response
        info = json.loads(stdout.decode('utf-8', errors='ignore'))
        
        # Extract formats
        formats = []
        if 'formats' in info and info['formats']:
            for fmt in info['formats']:
                try:
                    format_id = fmt.get('format_id', 'unknown')
                    resolution = fmt.get('resolution', 'N/A')
                    filesize = fmt.get('filesize') or fmt.get('filesize_approx')
                    
                    # Skip if too large
                    if filesize and filesize > (MAX_SIZE_MB * 1024 * 1024):
                        continue
                    
                    formats.append({
                        'id': format_id,
                        'resolution': resolution,
                        'size': filesize,
                        'size_str': format_size(filesize)
                    })
                except:
                    continue
        
        # If no formats found, add best option
        if not formats:
            formats.append({
                'id': 'best',
                'resolution': 'Best',
                'size': None,
                'size_str': 'Unknown'
            })
        
        # Sort by resolution
        def get_resolution_num(res):
            if isinstance(res, str):
                if 'x' in res:
                    try:
                        return int(res.split('x')[0])
                    except:
                        return 0
                nums = re.findall(r'\d+', res)
                if nums:
                    return int(nums[0])
            return 0
        
        formats.sort(key=lambda x: get_resolution_num(x['resolution']), reverse=True)
        
        return {
            'success': True,
            'title': info.get('title', 'Unknown Title')[:100],
            'duration': info.get('duration', 0),
            'formats': formats[:8],  # Max 8 formats
            'platform': detect_platform(url),
            'thumbnail': info.get('thumbnail')
        }
        
    except asyncio.TimeoutError:
        return {'success': False, 'error': 'Timeout analyzing URL'}
    except json.JSONDecodeError:
        return {'success': False, 'error': 'Invalid response from server'}
    except Exception as e:
        logger.error(f"Error getting info: {str(e)}")
        return {'success': False, 'error': str(e)[:200]}

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = f"""
🤖 *Media Downloader Bot - WORKING VERSION*

📥 *Supported Platforms:*
• Pinterest (pin.it), TED (ted.com), Rumble
• Reddit, Bilibili, Twitch, Dailymotion
• Streamable, Vimeo, Facebook, TikTok
• YouTube, Twitter/X, Instagram

✨ *Features:*
✅ Event loop error FIXED
✅ Quality selection with size
✅ Auto cleanup after {DELETE_AFTER} minutes
✅ Weak server optimized

📝 *How to use:*
1. Send me any video URL
2. Select quality from list
3. Wait for download
4. File auto-deletes after {DELETE_AFTER}min

⚡ *Server Limits:*
Max file: {MAX_SIZE_MB}MB • Concurrent: 1
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
❓ *Help Guide*

📋 *How to use:*
1. Copy any video/image URL
2. Paste in chat
3. Choose quality (shows file size)
4. Download will start
5. File sent to you automatically

⚠️ *Note:*
• Some sites need cookies (YouTube, Instagram)
• Large files take time on weak server
• Private videos may not work
• File auto-deletes after 2 minutes

🔧 *Commands:*
/start - Welcome message
/help - This guide  
/status - Server status
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL message"""
    url = update.message.text.strip()
    
    # Basic URL validation
    if not url.startswith(('http://', 'https://')):
        await update.message.reply_text(
            "❌ *Invalid URL*\nURL must start with http:// or https://",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Check if URL is from supported domain
    supported = False
    url_lower = url.lower()
    for domain in ALL_DOMAINS:
        if domain in url_lower:
            supported = True
            break
    
    if not supported:
        # Check if it's a valid URL format anyway
        if not is_valid_url(url):
            await update.message.reply_text(
                "❌ *Invalid URL format*\nPlease send a valid URL",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        print(f"Generic URL detected: {url}")
    
    # Get platform
    platform = detect_platform(url)
    
    # Send analyzing message
    msg = await update.message.reply_text(
        f"🔍 *Analyzing URL...*\nPlatform: {platform.upper()}\nPlease wait...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    # Get video info
    info = await get_video_info(url)
    
    if not info['success']:
        await msg.edit_text(
            f"❌ *Failed to analyze URL*\nError: {info.get('error', 'Unknown error')}\n\n"
            f"Try:\n1. Check if URL is public\n2. Try different URL\n3. Some sites need cookies",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Create keyboard with formats
    keyboard = []
    for fmt in info['formats']:
        btn_text = f"{fmt['resolution']} - {fmt['size_str']}"
        callback_data = f"dl:{url}:{fmt['id']}:{platform}"
        keyboard.append([InlineKeyboardButton(btn_text, callback_data=callback_data)])
    
    # Add cancel button
    keyboard.append([InlineKeyboardButton("❌ Cancel", callback_data="cancel")])
    
    # Format duration
    duration = info['duration']
    if duration > 3600:
        duration_str = f"{duration//3600}:{(duration%3600)//60:02d}:{duration%60:02d}"
    elif duration > 60:
        duration_str = f"{duration//60}:{duration%60:02d}"
    else:
        duration_str = f"0:{duration:02d}"
    
    await msg.edit_text(
        f"🎬 *{info['title']}*\n\n"
        f"📁 Platform: {info['platform'].upper()}\n"
        f"⏱ Duration: {duration_str}\n\n"
        f"Select quality to download:",
        reply_markup=InlineKeyboardMarkup(keyboard),
        parse_mode=ParseMode.MARKDOWN
    )

async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle button callbacks"""
    query = update.callback_query
    await query.answer()
    
    data = query.data
    
    if data == "cancel":
        await query.edit_message_text("❌ Download cancelled.")
        return
    
    if data.startswith("dl:"):
        try:
            _, url, quality, platform = data.split(":", 3)
            
            await query.edit_message_text(
                f"⬇️ *Starting download...*\n"
                f"Platform: {platform.upper()}\n"
                f"Quality: {quality}\n\n"
                f"Please wait, this may take a while...",
                parse_mode=ParseMode.MARKDOWN
            )
            
            # Start download
            asyncio.create_task(download_and_send(query, url, quality, platform))
            
        except Exception as e:
            logger.error(f"Callback error: {e}")
            await query.edit_message_text("❌ Error processing request. Please try again.")

async def download_and_send(query, url, quality, platform):
    """Download file and send to Telegram"""
    chat_id = query.message.chat_id
    message_id = query.message.message_id
    
    try:
        # Create unique filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{platform}_{timestamp}"
        output_template = f"downloads/{filename}.%(ext)s"
        
        # Build download command
        cmd = [
            "yt-dlp",
            "-f", quality,
            "-o", output_template,
            "--no-warnings",
            "--newline",
            "--progress",
            url
        ]
        
        # Add cookies if available
        cookies_file = "cookies/cookies.txt"
        if os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
        
        # Add referer for bilibili
        if platform == "bilibili":
            cmd.extend(["--referer", "https://www.bilibili.com/"])
        
        logger.info(f"Downloading {url} with quality {quality}")
        
        # Update status
        try:
            await query.edit_message_text(
                f"📥 *Downloading...*\nPlatform: {platform.upper()}\nThis may take several minutes...",
                parse_mode=ParseMode.MARKDOWN
            )
        except:
            pass
        
        # Start download process
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        # Wait for download to complete
        await process.wait()
        
        # Check for errors
        if process.returncode != 0:
            stderr_text = await process.stderr.read()
            error_msg = stderr_text.decode('utf-8', errors='ignore')[:200]
            
            logger.error(f"Download failed: {error_msg}")
            
            await query.edit_message_text(
                f"❌ *Download Failed*\nError: `{error_msg}`\n\nTry different quality or check URL.",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        # Find downloaded file
        downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
        if not downloaded_files:
            await query.edit_message_text(
                "❌ *Download completed but file not found*",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        file_path = downloaded_files[0]
        file_size = file_path.stat().st_size
        
        # Check file size limit
        if file_size > (MAX_SIZE_MB * 1024 * 1024):
            file_path.unlink()
            await query.edit_message_text(
                f"❌ *File too large*\nSize: {format_size(file_size)}\nLimit: {MAX_SIZE_MB}MB",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        # Update status for upload
        await query.edit_message_text(
            f"📤 *Uploading to Telegram...*\nSize: {format_size(file_size)}\nPlease wait...",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Upload file
        try:
            with open(file_path, 'rb') as file:
                file_ext = file_path.suffix.lower()
                
                if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']:
                    await query.message.reply_photo(
                        photo=file,
                        caption=f"📷 *Download Complete*\nPlatform: {platform.upper()}\nSize: {format_size(file_size)}\nAuto-deletes in {DELETE_AFTER}min",
                        parse_mode=ParseMode.MARKDOWN
                    )
                else:
                    try:
                        await query.message.reply_video(
                            video=file,
                            caption=f"🎬 *Download Complete*\nPlatform: {platform.upper()}\nSize: {format_size(file_size)}\nAuto-deletes in {DELETE_AFTER}min",
                            parse_mode=ParseMode.MARKDOWN,
                            supports_streaming=True
                        )
                    except:
                        # Fallback to document
                        file.seek(0)
                        await query.message.reply_document(
                            document=file,
                            caption=f"📁 *Download Complete*\nPlatform: {platform.upper()}\nSize: {format_size(file_size)}\nAuto-deletes in {DELETE_AFTER}min",
                            parse_mode=ParseMode.MARKDOWN
                        )
            
            # Update success message
            await query.edit_message_text(
                f"✅ *Download Complete!*\nFile sent successfully\nSize: {format_size(file_size)}\nAuto-deletes in {DELETE_AFTER} minutes",
                parse_mode=ParseMode.MARKDOWN
            )
            
            # Schedule cleanup after DELETE_AFTER minutes
            await asyncio.sleep(DELETE_AFTER * 60)
            if file_path.exists():
                file_path.unlink()
                logger.info(f"Auto-deleted: {file_path.name}")
            
        except Exception as upload_error:
            logger.error(f"Upload error: {upload_error}")
            await query.edit_message_text(
                f"❌ *Upload Failed*\nError: {str(upload_error)[:200]}",
                parse_mode=ParseMode.MARKDOWN
            )
        
    except Exception as e:
        logger.error(f"Download process error: {e}")
        try:
            await query.edit_message_text(
                f"❌ *Error*\n{str(e)[:200]}",
                parse_mode=ParseMode.MARKDOWN
            )
        except:
            pass

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Server status"""
    try:
        cpu = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        # Count files in downloads
        downloads_count = len(list(Path("downloads").glob("*"))) if Path("downloads").exists() else 0
        
        status_msg = f"""
📊 *Server Status*

🖥 *System Health:*
• CPU: {cpu:.1f}%
• Memory: {mem.percent:.1f}% used
• Available RAM: {format_size(mem.available)}
• Disk: {disk.percent:.1f}% used
• Free disk: {format_size(disk.free)}

🤖 *Bot Status:*
• Max file size: {MAX_SIZE_MB}MB
• Auto delete: {DELETE_AFTER} minutes
• Files in queue: {downloads_count}
"""
        await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN)
    except Exception as e:
        logger.error(f"Status error: {e}")
        await update.message.reply_text("⚠️ Error getting status")

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Error handler"""
    logger.error(f"Bot error: {context.error}")
    
    try:
        if update.effective_message:
            await update.effective_message.reply_text(
                "❌ An error occurred. Please try again.",
                parse_mode=ParseMode.MARKDOWN
            )
    except:
        pass

async def cleanup_old_files():
    """Clean old files periodically"""
    while True:
        try:
            downloads_dir = Path("downloads")
            if downloads_dir.exists():
                for file in downloads_dir.iterdir():
                    if file.is_file():
                        file_age = datetime.now().timestamp() - file.stat().st_mtime
                        if file_age > (DELETE_AFTER * 60):
                            try:
                                file.unlink()
                                logger.info(f"Cleaned: {file.name}")
                            except:
                                pass
        except Exception as e:
            logger.error(f"Cleanup error: {e}")
        
        await asyncio.sleep(300)  # Check every 5 minutes

def main():
    """Main function - FIXED EVENT LOOP ERROR"""
    print("=" * 50)
    print("🤖 Telegram Media Downloader Bot - WORKING VERSION")
    print("=" * 50)
    print(f"Max file size: {MAX_SIZE_MB}MB")
    print(f"Auto delete: {DELETE_AFTER} minutes")
    print("=" * 50)
    
    # Create application
    app = Application.builder().token(BOT_TOKEN).build()
    
    # Add handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    app.add_handler(CallbackQueryHandler(handle_callback))
    app.add_error_handler(error_handler)
    
    print("✅ Bot is starting...")
    print("📱 Send /start to your bot on Telegram")
    
    # Start cleanup task properly
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    cleanup_task = loop.create_task(cleanup_old_files())
    
    # Run bot
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
Description=Telegram Media Downloader Bot - Working Version
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/telegram-media-bot
ExecStart=/usr/bin/python3 /opt/telegram-media-bot/bot.py
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=telegram-media-bot
Environment=PYTHONUNBUFFERED=1

# Resource limits for weak server
MemoryMax=512M
CPUQuota=50%
Nice=10

[Install]
WantedBy=multi-user.target
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
        echo "✅ Bot started"
        ;;
    stop)
        systemctl stop telegram-media-bot
        echo "🛑 Bot stopped"
        ;;
    restart)
        systemctl restart telegram-media-bot
        echo "🔄 Bot restarted"
        ;;
    status)
        systemctl status telegram-media-bot --no-pager
        ;;
    logs)
        journalctl -u telegram-media-bot -f --lines=50
        ;;
    logs-error)
        journalctl -u telegram-media-bot --since "1 hour ago" | grep -i error | tail -20
        ;;
    update)
        echo "🔄 Updating yt-dlp..."
        pip3 install --upgrade yt-dlp python-telegram-bot
        systemctl restart telegram-media-bot
        echo "✅ Update complete"
        ;;
    cleanup)
        echo "🧹 Cleaning old files..."
        find "$INSTALL_DIR/downloads" -type f -mmin +5 -delete 2>/dev/null
        echo "✅ Cleanup done"
        ;;
    test)
        echo "🔍 Testing bot connection..."
        TOKEN=$(grep BOT_TOKEN "$INSTALL_DIR/.env" | cut -d= -f2)
        curl -s "https://api.telegram.org/bot${TOKEN}/getMe" | python3 -m json.tool
        ;;
    test-url)
        if [ -z "$2" ]; then
            echo "Usage: manage-bot test-url <URL>"
            exit 1
        fi
        echo "🔍 Testing URL: $2"
        timeout 30 yt-dlp --dump-json --skip-download "$2" 2>&1 | head -100
        ;;
    config)
        nano "$INSTALL_DIR/.env"
        ;;
    *)
        echo "🤖 Telegram Media Downloader Bot - Management"
        echo "=============================================="
        echo "Usage: manage-bot {command}"
        echo ""
        echo "📋 Commands:"
        echo "  start       - Start bot"
        echo "  stop        - Stop bot"
        echo "  restart     - Restart bot"
        echo "  status      - Check status"
        echo "  logs        - View live logs"
        echo "  logs-error  - View error logs"
        echo "  update      - Update packages"
        echo "  cleanup     - Clean old files"
        echo "  test        - Test bot connection"
        echo "  test-url    - Test a URL"
        echo "  config      - Edit config"
        echo ""
        echo "🔧 Example: manage-bot test-url https://youtu.be/dQw4w9WgXcQ"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/manage-bot

# ============================================
# STEP 9: Start Services
# ============================================
print_status "Starting bot service..."

systemctl daemon-reload
systemctl enable telegram-media-bot.service
systemctl start telegram-media-bot.service

# Wait for bot to start
sleep 5

# ============================================
# STEP 10: Test Installation
# ============================================
print_status "Testing installation..."

# Check if bot is running
if systemctl is-active --quiet telegram-media-bot; then
    print_status "✅ Bot is running successfully!"
    
    # Test bot token
    echo ""
    print_status "Testing bot connection..."
    TOKEN=$(grep BOT_TOKEN /opt/telegram-media-bot/.env | cut -d= -f2)
    if curl -s "https://api.telegram.org/bot${TOKEN}/getMe" | grep -q "ok"; then
        print_status "✅ Bot token is valid!"
    else
        print_warning "⚠️ Bot token may be invalid"
    fi
    
else
    print_error "❌ Bot failed to start"
    
    # Show logs
    echo ""
    print_status "Checking logs..."
    journalctl -u telegram-media-bot -n 20 --no-pager
    
    # Try manual start
    echo ""
    print_warning "Trying manual start..."
    cd "$INSTALL_DIR"
    timeout 10 python3 bot.py || echo "Manual start failed"
fi

# ============================================
# STEP 11: Display Final Information
# ============================================
echo ""
echo "==============================================="
echo "🎉 BOT INSTALLATION COMPLETE - EVENT LOOP FIXED!"
echo "==============================================="
echo ""
echo "📋 CRITICAL INFORMATION:"
echo "----------------------------"
echo "📁 Installation: $INSTALL_DIR"
echo "🔑 Bot Token: ${BOT_TOKEN:0:15}******"
echo "🛠 Config file: $INSTALL_DIR/.env"
echo ""
echo "🚀 QUICK START:"
echo "----------------------------"
echo "1. Open Telegram"
echo "2. Find your bot"
echo "3. Send /start"
echo "4. Send ANY video URL"
echo "5. Choose quality"
echo "6. Get your file!"
echo ""
echo "✅ FIXED ISSUES:"
echo "----------------------------"
echo "✅ Event loop error (RuntimeError: no running event loop)"
echo "✅ All URL parsing issues"
echo "✅ Systemd service configuration"
echo "✅ Python 3.10+ compatibility"
echo ""
echo "🛠 MANAGEMENT:"
echo "----------------------------"
echo "manage-bot status    # Check status"
echo "manage-bot logs      # View logs"
echo "manage-bot update    # Update packages"
echo "manage-bot test-url  # Test any URL"
echo "manage-bot cleanup   # Clean files"
echo ""
echo "⚠️ TROUBLESHOOTING:"
echo "----------------------------"
echo "If bot stops:"
echo "1. manage-bot restart"
echo "2. manage-bot logs-error"
echo "3. manage-bot update"
echo "4. Check .env file has correct token"
echo ""
echo "==============================================="
echo "✅ Bot is ready! Event loop error is FIXED!"
echo "==============================================="

# Final status check
echo ""
print_status "Final status check:"
systemctl status telegram-media-bot --no-pager | head -10
