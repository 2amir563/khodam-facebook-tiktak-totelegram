#!/bin/bash

# Telegram Video Downloader Bot - Final Version
# No warnings, fully tested
# GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

log "Starting installation of Telegram Video Downloader Bot..."

# Update system
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install dependencies
log "Installing dependencies..."
apt-get install -y python3 python3-pip python3-venv git curl wget

# Create bot directory
BOT_DIR="/root/telegram-video-bot"
log "Creating bot directory at $BOT_DIR..."
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Create virtual environment
log "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python packages
log "Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.6 yt-dlp requests beautifulsoup4 lxml

# Create config.py
log "Creating configuration files..."

# config.py
cat > config.py << 'EOF'
#!/usr/bin/env python3
import os

BOT_TOKEN = os.environ.get("BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")

MAX_FILE_SIZE = 1800 * 1024 * 1024
DOWNLOAD_PATH = "./downloads"
TEMP_PATH = "./temp"

COOKIE_FILE = "cookies.txt" if os.path.exists("cookies.txt") else None

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

MESSAGES = {
    "start": "🤖 **Video Downloader Bot**\n\nSend me a TikTok, Facebook, or Instagram link and I'll download it for you!\n\nCommands:\n/start - Start bot\n/help - Show help\n/about - About bot",
    "help": "📖 **How to use:**\n\n1. Send a video link\n2. Wait for download\n3. Receive video in Telegram\n\n⚠️ **Note:** Some videos may be private.",
    "about": "📱 **Video Downloader Bot**\n\nGitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram"
}
EOF

# Create main bot file
log "Creating main bot file..."

# bot.py
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Video Downloader Bot
Fixed version - No entity parsing errors
"""

import os
import re
import sys
import logging
import shutil
import tempfile
import html
from urllib.parse import unquote

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

# Create directories
os.makedirs(config.DOWNLOAD_PATH, exist_ok=True)
os.makedirs(config.TEMP_PATH, exist_ok=True)

def clean_text(text):
    """Clean text for Telegram"""
    if not text:
        return ""
    
    # Decode URL encoding
    try:
        text = unquote(text)
    except:
        pass
    
    # Unescape HTML
    text = html.unescape(text)
    
    # Escape Markdown characters
    for char in ['_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!']:
        text = text.replace(char, f'\\{char}')
    
    # Remove control characters
    text = re.sub(r'[\x00-\x1F\x7F-\x9F]', '', text)
    
    # Limit length
    if len(text) > 500:
        text = text[:497] + "..."
    
    return text.strip()

def is_valid_video_url(url):
    """Check if URL is a valid video URL"""
    url_lower = url.lower()
    
    # TikTok patterns
    if 'tiktok.com' in url_lower and '/video/' in url_lower:
        return "tiktok"
    
    if 'vm.tiktok.com' in url_lower or 'vt.tiktok.com' in url_lower:
        return "tiktok"
    
    # Facebook patterns (avoid login pages)
    if 'facebook.com' in url_lower and 'login' not in url_lower:
        if '/videos/' in url_lower or '/reel/' in url_lower or '/watch/' in url_lower:
            return "facebook"
    
    if 'fb.watch' in url_lower:
        return "facebook"
    
    # Instagram
    if 'instagram.com' in url_lower and ('/reel/' in url_lower or '/p/' in url_lower):
        return "instagram"
    
    return False

def fix_url(url, platform):
    """Fix common URL issues"""
    if platform == "facebook" and 'login' in url:
        # Try to extract actual video URL from redirect
        match = re.search(r'next=(https?%3A%2F%2F[^&]+)', url)
        if match:
            try:
                decoded = unquote(unquote(match.group(1)))
                if 'facebook.com' in decoded:
                    return decoded
            except:
                pass
    
    # Remove tracking parameters
    url = re.sub(r'[?&](share_|rdid|set)=[^&]+', '', url)
    url = re.sub(r'[?&]t=\d+s', '', url)
    
    return url

def download_video(url, platform):
    """Download video with retry logic"""
    temp_dir = tempfile.mkdtemp(dir=config.TEMP_PATH)
    
    ydl_opts = {
        'outtmpl': os.path.join(temp_dir, '%(title).80s.%(ext)s'),
        'quiet': False,
        'no_warnings': False,
        'extractaudio': False,
        'keepvideo': True,
        'writethumbnail': True,
        'merge_output_format': 'mp4',
        'http_headers': {
            'User-Agent': config.USER_AGENT,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
        },
        'cookiefile': config.COOKIE_FILE,
        'ignoreerrors': True,
        'retries': 3,
        'fragment_retries': 3,
    }
    
    # Platform specific settings
    if platform == "tiktok":
        ydl_opts['format'] = 'best[height<=720]'
    else:
        ydl_opts['format'] = 'best[filesize<100M]'
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # Get info first
            info = ydl.extract_info(url, download=False)
            
            if not info:
                return {'success': False, 'error': 'Cannot get video info'}
            
            # Check if video is accessible
            if info.get('availability') in ['needs_auth', 'subscriber_only']:
                return {'success': False, 'error': 'Video requires login or is private'}
            
            # Download
            ydl.download([url])
            
            # Find downloaded file
            for file in os.listdir(temp_dir):
                if file.endswith(('.mp4', '.webm', '.mkv')):
                    file_path = os.path.join(temp_dir, file)
                    
                    # Clean metadata
                    title = clean_text(info.get('title', 'Video'))
                    uploader = clean_text(info.get('uploader', 'Unknown'))
                    description = clean_text(info.get('description', ''))
                    
                    return {
                        'success': True,
                        'file_path': file_path,
                        'title': title or 'Video',
                        'duration': info.get('duration', 0),
                        'uploader': uploader or 'Unknown',
                        'description': description,
                        'temp_dir': temp_dir,
                        'url': url,
                        'platform': platform
                    }
            
            return {'success': False, 'error': 'No video file found'}
            
    except Exception as e:
        logger.error(f"Download error: {e}")
        # Cleanup on error
        try:
            shutil.rmtree(temp_dir, ignore_errors=True)
        except:
            pass
        return {'success': False, 'error': str(e)}

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        config.MESSAGES['start'],
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        config.MESSAGES['help'],
        parse_mode=ParseMode.MARKDOWN
    )

async def about_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        config.MESSAGES['about'],
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
    )

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    message = update.message
    text = message.text.strip()
    
    # Extract URL
    urls = re.findall(r'https?://[^\s]+', text)
    
    if not urls:
        await message.reply_text("Please send a valid video URL (TikTok, Facebook, Instagram).")
        return
    
    url = urls[0]
    
    # Validate URL
    platform = is_valid_video_url(url)
    if not platform:
        await message.reply_text(
            "❌ Invalid or unsupported URL.\n\n"
            "Please send a direct video link from:\n"
            "• TikTok\n• Facebook\n• Instagram"
        )
        return
    
    # Fix URL
    url = fix_url(url, platform)
    
    # Send status
    status_msg = await message.reply_text(f"🔍 Checking {platform} link...")
    
    try:
        await status_msg.edit_text(f"📥 Downloading from {platform}...")
        
        result = download_video(url, platform)
        
        if not result['success']:
            error_msg = result['error']
            await status_msg.edit_text(f"❌ Download failed: {error_msg}")
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
        caption = f"📹 *{result['title']}*\n"
        caption += f"👤 *From:* {result['uploader']}\n"
        
        if result['duration'] > 0:
            mins = result['duration'] // 60
            secs = result['duration'] % 60
            caption += f"⏱ *Duration:* {mins}:{secs:02d}\n"
        
        # Send video
        await status_msg.edit_text("📤 Uploading to Telegram...")
        
        with open(result['file_path'], 'rb') as f:
            await message.reply_video(
                video=InputFile(f, filename="video.mp4"),
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
            await status_msg.edit_text(f"❌ Error: {str(e)[:100]}")
        except:
            pass

def main():
    if config.BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("ERROR: Bot token not set!")
        print("="*60)
        print("1. Get token from @BotFather")
        print("2. Edit config.py")
        print("3. Replace YOUR_BOT_TOKEN_HERE with your token")
        print("="*60)
        sys.exit(1)
    
    print("🤖 Telegram Video Downloader Bot")
    print("✅ Fixed: No entity parsing errors")
    print("✅ Better URL validation")
    print("")
    
    application = Application.builder() \
        .token(config.BOT_TOKEN) \
        .read_timeout(120) \
        .write_timeout(120) \
        .build()
    
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("about", about_command))
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND,
        handle_message
    ))
    
    print("🚀 Starting bot...")
    print("📝 Logs: bot.log")
    print("🛑 Stop with Ctrl+C")
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
        print(f"\n💥 Error: {e}")

if __name__ == '__main__':
    main()
EOF

# Create start script
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Telegram Video Downloader Bot"
echo "================================"

# Check if running
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "⚠️ Bot is already running!"
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
    exit 1
fi

# Activate venv
source venv/bin/activate

# Check token
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "❌ Bot token not configured!"
    echo ""
    echo "To fix:"
    echo "1. Get token from @BotFather"
    echo "2. Edit config.py"
    echo "3. Replace YOUR_BOT_TOKEN_HERE"
    echo ""
    exit 1
fi

# Create directories
mkdir -p downloads temp

echo ""
echo "✅ All checks passed"
echo "🚀 Starting bot..."
echo ""
echo "📝 Logs: tail -f bot.log"
echo "🛑 Stop: Ctrl+C"
echo ""

python3 bot.py
EOF

chmod +x start.sh

# Create stop script
cat > stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null
sleep 2
echo "✅ Bot stopped"
EOF

chmod +x stop.sh

# Create setup script
cat > setup.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Bot Setup"
echo "============"

if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "Enter your Telegram Bot Token:"
    read -p "Token: " TOKEN
    
    if [ -z "$TOKEN" ]; then
        echo "❌ Token cannot be empty"
        exit 1
    fi
    
    sed -i "s/YOUR_BOT_TOKEN_HERE/$TOKEN/g" config.py
    echo "✅ Token saved"
    
    echo ""
    echo "🎉 Setup complete!"
    echo "Start bot: ./start.sh"
else
    echo "✅ Bot already configured"
    echo "Start bot: ./start.sh"
fi
EOF

chmod +x setup.sh

# Create status script
cat > status.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Bot Status"
echo "============"

if pgrep -f "python3 bot.py" > /dev/null; then
    echo "✅ Bot is running"
    echo ""
    echo "Process info:"
    ps aux | grep "python3 bot.py" | grep -v grep
    
    if [ -f "bot.log" ]; then
        echo ""
        echo "📝 Last logs:"
        tail -10 bot.log
    fi
else
    echo "❌ Bot is not running"
    echo ""
    echo "To start: ./start.sh"
fi
EOF

chmod +x status.sh

# Make bot.py executable
chmod +x bot.py

success "✅ Installation completed successfully!"
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
echo "📱 Send a TikTok/Facebook/Instagram link to your bot!"
echo ""
success "🎉 Bot is ready to use!"
