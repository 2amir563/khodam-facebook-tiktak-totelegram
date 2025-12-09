#!/bin/bash

# Telegram Facebook & TikTok Downloader Bot Installer
# Fixed Heredoc issue
# GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [ "$EUID" -eq 0 ]; then 
    log_warning "Installing as root user"
fi

log_info "Starting Telegram Video Downloader Bot installation..."

# Update system
log_info "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install dependencies
log_info "Installing dependencies..."
apt-get install -y python3 python3-pip python3-venv git curl wget xz-utils

# Create bot directory
BOT_DIR="/root/telegram-video-bot"
log_info "Creating bot directory at $BOT_DIR..."
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Try to install FFmpeg
log_info "Installing FFmpeg..."
if command -v ffmpeg &> /dev/null; then
    log_success "FFmpeg already installed"
else
    if apt-get install -y ffmpeg 2>/dev/null; then
        log_success "FFmpeg installed via apt"
    else
        log_warning "FFmpeg not available via apt, yt-dlp will use internal FFmpeg"
    fi
fi

# Create virtual environment
log_info "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
log_info "Upgrading pip..."
pip install --upgrade pip

# Install Python packages
log_info "Installing Python packages..."
pip install python-telegram-bot==20.6 yt-dlp requests beautifulsoup4 lxml

# Create config.py
log_info "Creating config.py..."
cat > config.py << 'CONFIGEOF'
#!/usr/bin/env python3
import os

BOT_TOKEN = os.environ.get("BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")

MAX_FILE_SIZE = 1900 * 1024 * 1024
DOWNLOAD_PATH = "./downloads"
SUPPORTED_PLATFORMS = ["facebook.com", "fb.watch", "tiktok.com", "vm.tiktok.com", "instagram.com", "youtube.com", "youtu.be"]

MESSAGES = {
    "start": """
🤖 **Video Downloader Bot**

Send me a link from:
• Facebook (videos, reels)
• TikTok (videos)
• Instagram (reels, posts)
• YouTube (videos, shorts)

I'll download and send it to you!

Commands:
/start - Start bot
/help - Show help
/about - About bot
""",
    
    "help": """
📖 **How to use:**

1. Send a Facebook/TikTok/Instagram/YouTube link
2. Wait for download
3. Receive video in Telegram

⚠️ **Notes:**
- Only public videos
- Max 2GB per file
- Files deleted after sending
""",
    
    "about": """
📱 **Video Downloader Bot**

GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

Made with Python and yt-dlp
"""
}
CONFIGEOF

# Create main bot file
log_info "Creating bot.py..."
cat > bot.py << 'BOTEOF'
#!/usr/bin/env python3
"""
Telegram Video Downloader Bot
Simple and reliable
"""

import os
import re
import sys
import logging
import shutil
import tempfile
from datetime import datetime

from telegram import Update, InputFile
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.constants import ParseMode

import yt_dlp

import config

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Create downloads directory
os.makedirs(config.DOWNLOAD_PATH, exist_ok=True)

def is_supported_url(url: str) -> bool:
    """Check if URL is supported"""
    url_lower = url.lower()
    for platform in config.SUPPORTED_PLATFORMS:
        if platform in url_lower:
            return True
    return False

def download_video(url: str):
    """Download video using yt-dlp"""
    temp_dir = tempfile.mkdtemp(dir=config.DOWNLOAD_PATH)
    
    ydl_opts = {
        'format': 'best[filesize<100M]',
        'outtmpl': os.path.join(temp_dir, '%(title).100s.%(ext)s'),
        'quiet': False,
        'no_warnings': False,
        'extractaudio': False,
        'keepvideo': True,
        'writethumbnail': True,
        'merge_output_format': 'mp4',
        'postprocessors': [
            {
                'key': 'FFmpegVideoConvertor',
                'preferedformat': 'mp4',
            },
        ],
        'http_headers': {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        },
        'cookiefile': 'cookies.txt' if os.path.exists('cookies.txt') else None,
    }
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            filename = ydl.prepare_filename(info)
            
            # Ensure .mp4 extension
            if not filename.endswith('.mp4'):
                mp4_file = os.path.splitext(filename)[0] + '.mp4'
                if os.path.exists(mp4_file):
                    filename = mp4_file
            
            return {
                'success': True,
                'file_path': filename,
                'title': info.get('title', 'Video'),
                'duration': info.get('duration', 0),
                'uploader': info.get('uploader', 'Unknown'),
                'description': info.get('description', ''),
                'temp_dir': temp_dir,
                'url': url
            }
            
    except Exception as e:
        logger.error(f"Download error: {e}")
        try:
            shutil.rmtree(temp_dir, ignore_errors=True)
        except:
            pass
        
        return {
            'success': False,
            'error': str(e)
        }

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    await update.message.reply_text(
        config.MESSAGES['start'],
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    await update.message.reply_text(
        config.MESSAGES['help'],
        parse_mode=ParseMode.MARKDOWN
    )

async def about_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /about command"""
    await update.message.reply_text(
        config.MESSAGES['about'],
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
    )

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming messages"""
    message = update.message
    text = message.text.strip()
    
    # Extract URLs
    urls = re.findall(r'https?://[^\s]+', text)
    
    if not urls:
        await message.reply_text("Please send a valid video URL (Facebook, TikTok, Instagram, YouTube).")
        return
    
    url = urls[0]
    
    # Check if supported
    if not is_supported_url(url):
        supported = ', '.join(config.SUPPORTED_PLATFORMS)
        await message.reply_text(
            f"❌ Unsupported URL.\n\nSupported: {supported}",
            disable_web_page_preview=True
        )
        return
    
    # Send status
    status_msg = await message.reply_text("⏳ Processing...")
    
    try:
        await status_msg.edit_text("📥 Downloading video...")
        
        result = download_video(url)
        
        if not result['success']:
            await status_msg.edit_text(f"❌ Download failed: {result['error'][:200]}")
            return
        
        # Check file size
        try:
            file_size = os.path.getsize(result['file_path'])
            if file_size > config.MAX_FILE_SIZE:
                await status_msg.edit_text(
                    f"❌ File too large ({file_size/(1024*1024):.1f}MB). "
                    f"Max: {config.MAX_FILE_SIZE/(1024*1024):.0f}MB"
                )
                shutil.rmtree(result['temp_dir'], ignore_errors=True)
                return
        except:
            pass
        
        # Create caption
        caption = f"📹 *{result['title']}*\n\n"
        caption += f"👤 *Uploader:* {result['uploader']}\n"
        
        if result['duration'] > 0:
            mins = result['duration'] // 60
            secs = result['duration'] % 60
            caption += f"⏱ *Duration:* {mins}:{secs:02d}\n"
        
        if result['description']:
            desc = result['description'][:300] + "..." if len(result['description']) > 300 else result['description']
            caption += f"\n📝 {desc}\n"
        
        caption += f"\n🔗 *Source:* {result['url']}"
        
        # Send video
        await status_msg.edit_text("📤 Uploading to Telegram...")
        
        with open(result['file_path'], 'rb') as f:
            await message.reply_video(
                video=InputFile(f, filename=os.path.basename(result['file_path'])[:50]),
                caption=caption,
                parse_mode=ParseMode.MARKDOWN,
                duration=result['duration'],
                supports_streaming=True,
                read_timeout=120,
                write_timeout=120
            )
        
        await status_msg.edit_text("✅ Video sent successfully!")
        
        # Cleanup
        try:
            shutil.rmtree(result['temp_dir'], ignore_errors=True)
        except:
            pass
        
    except Exception as e:
        logger.error(f"Error: {e}")
        try:
            await status_msg.edit_text(f"❌ Error: {str(e)[:200]}")
        except:
            pass

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Update {update} caused error {context.error}")

def main():
    """Start the bot"""
    if config.BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("ERROR: Bot token not set!")
        print("="*60)
        print("1. Get token from @BotFather")
        print("2. Edit config.py and replace YOUR_BOT_TOKEN_HERE")
        print("3. Or run: export BOT_TOKEN='your_token_here'")
        print("="*60)
        sys.exit(1)
    
    print("🤖 Starting Telegram Video Downloader Bot...")
    print("📁 Directory:", os.getcwd())
    print("🔧 Using polling (no port needed)")
    print("")
    
    # Create application
    application = Application.builder() \
        .token(config.BOT_TOKEN) \
        .read_timeout(60) \
        .write_timeout(60) \
        .connect_timeout(60) \
        .build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("about", about_command))
    
    # Handle text messages
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND,
        handle_message
    ))
    
    # Error handler
    application.add_error_handler(error_handler)
    
    # Start bot
    print("✅ Bot initialized")
    print("⏳ Starting polling...")
    print("🛑 Press Ctrl+C to stop")
    print("")
    
    try:
        application.run_polling(
            poll_interval=1.0,
            timeout=30,
            drop_pending_updates=True
        )
    except KeyboardInterrupt:
        print("\n👋 Bot stopped")
    except Exception as e:
        logger.error(f"Bot crashed: {e}")
        print(f"\n💥 Error: {e}")

if __name__ == '__main__':
    main()
BOTEOF

# Create start script
log_info "Creating start.sh..."
cat > start.sh << 'STARTEOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "========================================"
echo "🤖 Telegram Video Downloader Bot"
echo "========================================"

# Check if already running
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "⚠️ Bot is already running!"
    echo "Stop it with: ./stop.sh"
    exit 1
fi

# Check Python
if ! command -v python3 > /dev/null; then
    echo "❌ Python3 not found!"
    exit 1
fi

# Check venv
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found!"
    echo "Run: python3 -m venv venv"
    exit 1
fi

# Activate venv
source venv/bin/activate

# Check token
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "❌ ERROR: Bot token not set!"
    echo ""
    echo "To fix:"
    echo "1. Edit config.py"
    echo "2. Replace YOUR_BOT_TOKEN_HERE with your token"
    echo ""
    echo "Get token from @BotFather on Telegram"
    echo ""
    exit 1
fi

# Create downloads dir
mkdir -p downloads

echo ""
echo "✅ All checks passed"
echo "🚀 Starting bot..."
echo ""
echo "📝 Logs: bot.log"
echo "📁 Downloads: downloads/"
echo "🛑 Stop with Ctrl+C"
echo ""

# Run bot
python3 bot.py
STARTEOF

chmod +x start.sh

# Create stop script
log_info "Creating stop.sh..."
cat > stop.sh << 'STOPEOF'
#!/bin/bash
echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null
sleep 2
if pgrep -f "python3 bot.py" > /dev/null; then
    pkill -9 -f "python3 bot.py" 2>/dev/null
fi
echo "✅ Bot stopped"
STOPEOF

chmod +x stop.sh

# Create restart script
cat > restart.sh << 'RESTARTEOF'
#!/bin/bash
cd "$(dirname "$0")"
./stop.sh
sleep 3
./start.sh
RESTARTEOF

chmod +x restart.sh

# Create setup script
cat > setup.sh << 'SETUPEOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Bot Setup"
echo "============"

if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "Please enter your bot token from @BotFather:"
    read -p "Token: " TOKEN
    
    if [ -z "$TOKEN" ]; then
        echo "❌ Token cannot be empty"
        exit 1
    fi
    
    sed -i "s/YOUR_BOT_TOKEN_HERE/$TOKEN/g" config.py
    echo "✅ Token saved"
    
    echo ""
    echo "🎉 Setup complete!"
    echo "Start bot with: ./start.sh"
else
    echo "✅ Bot token already configured"
    echo "Start bot with: ./start.sh"
fi
SETUPEOF

chmod +x setup.sh

# Create status script
cat > status.sh << 'STATUSEOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Bot Status"
echo "============="

if pgrep -f "python3 bot.py" > /dev/null; then
    echo "✅ Bot is running"
    echo ""
    echo "Process info:"
    ps aux | grep "python3 bot.py" | grep -v grep
    
    if [ -f "bot.log" ]; then
        echo ""
        echo "📝 Last logs:"
        tail -5 bot.log
    fi
else
    echo "❌ Bot is not running"
    echo ""
    echo "To start: ./start.sh"
fi

echo ""
echo "📁 Downloads folder:"
ls -la downloads/ 2>/dev/null | head -10
STATUSEOF

chmod +x status.sh

# Create service file
cat > /etc/systemd/system/telegram-bot.service << 'SERVICEEOF'
[Unit]
Description=Telegram Video Downloader Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/telegram-video-bot
Environment="PATH=/root/telegram-video-bot/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/root/telegram-video-bot/start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Make bot.py executable
chmod +x bot.py

log_success "✅ Installation completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Go to bot directory:"
echo "   cd $BOT_DIR"
echo ""
echo "2. Setup bot token:"
echo "   ./setup.sh"
echo ""
echo "3. Start bot:"
echo "   ./start.sh"
echo ""
echo "4. Or run as service:"
echo "   systemctl daemon-reload"
echo "   systemctl enable telegram-bot"
echo "   systemctl start telegram-bot"
echo ""
echo "📱 Send a video link to your bot on Telegram!"
echo ""
log_success "🎉 Bot is ready to use!"
