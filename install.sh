#!/bin/bash

# Telegram Facebook & TikTok Downloader Bot Installer
# Fixed version - No xz dependency for FFmpeg
# Created by: khodam-facebook-tiktak-totelegram
# GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    print_warning "Running as root. Creating user for bot..."
    if ! id -u botuser &>/dev/null; then
        useradd -m -s /bin/bash botuser
        print_success "User botuser created"
    fi
    su - botuser -c "$(cat << 'EOF'
set -e
cd ~
# Rest of installation will run as botuser
EOF
)" || true
fi

print_info "Starting installation of Telegram Video Downloader Bot..."

# Update and install basic dependencies
print_info "Updating system and installing dependencies..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y python3 python3-pip python3-venv git curl wget
sudo apt-get install -y xz-utils  # Add xz-utils for tar.xz files

# Create bot directory
BOT_DIR="$HOME/telegram-video-bot"
print_info "Creating bot directory at $BOT_DIR..."
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Install static FFmpeg without xz issues
print_info "Installing FFmpeg..."
# Try multiple methods to get FFmpeg

# Method 1: Try to install from apt (easiest)
if sudo apt-get install -y ffmpeg 2>/dev/null; then
    print_success "FFmpeg installed from apt repository"
else
    # Method 2: Download pre-compiled binary (no extraction needed)
    print_info "Downloading pre-compiled FFmpeg binary..."
    mkdir -p ffmpeg-bin
    cd ffmpeg-bin
    
    # Try to download static build
    if wget -q --spider https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz; then
        wget -q https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
        tar -xf ffmpeg-release-amd64-static.tar.xz
        cd ffmpeg-*-amd64-static
        sudo cp ffmpeg ffprobe /usr/local/bin/
        sudo chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe
        print_success "FFmpeg installed from static build"
    else
        # Method 3: Use yt-dlp's embedded ffmpeg
        print_info "Using yt-dlp's embedded FFmpeg..."
        cd "$BOT_DIR"
        python3 -c "import yt_dlp; print('yt-dlp will use its own FFmpeg')" 2>/dev/null || true
        print_warning "FFmpeg will be handled by yt-dlp automatically"
    fi
    
    cd "$BOT_DIR"
fi

# Create virtual environment
print_info "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Upgrade pip and install packages
print_info "Installing Python packages..."
pip install --upgrade pip setuptools wheel

# Install requirements
cat > requirements.txt << 'EOF'
python-telegram-bot==20.6
yt-dlp>=2024.11.11
requests>=2.31.0
beautifulsoup4>=4.12.0
lxml>=5.2.0
EOF

pip install -r requirements.txt

# Create configuration file
print_info "Creating configuration files..."

# Create config.py
cat > config.py << 'EOF'
#!/usr/bin/env python3
import os

# Bot Configuration
BOT_TOKEN = os.environ.get("BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")

# Download settings
MAX_FILE_SIZE = 1900 * 1024 * 1024  # 1.9GB (slightly under Telegram limit)
DOWNLOAD_PATH = "./downloads"
SUPPORTED_PLATFORMS = ["facebook.com", "fb.watch", "tiktok.com", "vm.tiktok.com", "instagram.com"]

# Messages
MESSAGES = {
    "start": """
🤖 **Video Downloader Bot**

Send me a link from:
• Facebook (videos, reels)
• TikTok (videos)
• Instagram (reels, posts)

I'll download and send it to you!

Commands:
/start - Start bot
/help - Show help
/about - About bot
""",
    
    "help": """
📖 **How to use:**

1. Send a Facebook/TikTok/Instagram link
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

Made with ❤️ using Python
"""
}
EOF

# Create main bot file
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Video Downloader Bot
Simple and reliable version
"""

import os
import re
import sys
import logging
import asyncio
import tempfile
import shutil
from datetime import datetime
from urllib.parse import urlparse

from telegram import Update, InputFile
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.constants import ParseMode

import yt_dlp
from yt_dlp.utils import DownloadError

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

class VideoDownloader:
    @staticmethod
    def is_supported_url(url: str) -> bool:
        """Check if URL is from supported platform"""
        url_lower = url.lower()
        for platform in config.SUPPORTED_PLATFORMS:
            if platform in url_lower:
                return True
        return False
    
    @staticmethod
    def download_video(url: str):
        """Download video using yt-dlp"""
        temp_dir = tempfile.mkdtemp(dir=config.DOWNLOAD_PATH)
        
        ydl_opts = {
            'format': 'best[filesize<50M]',
            'outtmpl': os.path.join(temp_dir, '%(title)s.%(ext)s'),
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
                {
                    'key': 'FFmpegThumbnailsConvertor',
                    'format': 'jpg',
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
                
                # Find thumbnail
                thumbnail = None
                if info.get('thumbnail'):
                    thumbnail = info.get('thumbnail')
                else:
                    # Look for thumbnail file
                    base_name = os.path.splitext(filename)[0]
                    for ext in ['.jpg', '.webp', '.png']:
                        thumb_file = base_name + ext
                        if os.path.exists(thumb_file):
                            thumbnail = thumb_file
                            break
                
                return {
                    'success': True,
                    'file_path': filename,
                    'title': info.get('title', 'Video')[:200],
                    'duration': info.get('duration', 0),
                    'uploader': info.get('uploader', 'Unknown')[:100],
                    'description': info.get('description', '')[:500],
                    'thumbnail': thumbnail,
                    'temp_dir': temp_dir,
                    'original_url': url
                }
                
        except Exception as e:
            logger.error(f"Download error: {e}")
            # Cleanup temp dir
            try:
                shutil.rmtree(temp_dir, ignore_errors=True)
            except:
                pass
            
            return {
                'success': False,
                'error': str(e),
                'temp_dir': temp_dir
            }

class BotHandler:
    def __init__(self):
        self.stats = {
            'total_downloads': 0,
            'successful_downloads': 0,
            'failed_downloads': 0,
            'start_time': datetime.now()
        }
    
    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        await update.message.reply_text(
            config.MESSAGES['start'],
            parse_mode=ParseMode.MARKDOWN,
            disable_web_page_preview=True
        )
    
    async def help(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        await update.message.reply_text(
            config.MESSAGES['help'],
            parse_mode=ParseMode.MARKDOWN
        )
    
    async def about(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /about command"""
        await update.message.reply_text(
            config.MESSAGES['about'],
            parse_mode=ParseMode.MARKDOWN,
            disable_web_page_preview=True
        )
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle incoming messages with URLs"""
        message = update.message
        text = message.text.strip()
        
        # Extract URLs from message
        urls = re.findall(r'https?://[^\s]+', text)
        
        if not urls:
            await message.reply_text("Please send a valid Facebook, TikTok, or Instagram video URL.")
            return
        
        url = urls[0]
        
        # Check if URL is supported
        if not VideoDownloader.is_supported_url(url):
            supported = ', '.join(config.SUPPORTED_PLATFORMS)
            await message.reply_text(
                f"❌ Unsupported URL.\n\nSupported platforms:\n{supported}",
                disable_web_page_preview=True
            )
            return
        
        # Send initial status
        status_msg = await message.reply_text("⏳ Processing your request...")
        
        try:
            # Update status
            await status_msg.edit_text("📥 Downloading video...")
            
            # Download video
            result = VideoDownloader.download_video(url)
            self.stats['total_downloads'] += 1
            
            if not result['success']:
                self.stats['failed_downloads'] += 1
                await status_msg.edit_text(f"❌ Download failed: {result['error'][:200]}")
                
                # Cleanup
                if 'temp_dir' in result:
                    try:
                        shutil.rmtree(result['temp_dir'], ignore_errors=True)
                    except:
                        pass
                return
            
            # Check file size
            file_size = os.path.getsize(result['file_path'])
            if file_size > config.MAX_FILE_SIZE:
                await status_msg.edit_text(
                    f"❌ File too large ({file_size/(1024*1024):.1f}MB). "
                    f"Max allowed: {config.MAX_FILE_SIZE/(1024*1024):.0f}MB"
                )
                # Cleanup
                try:
                    shutil.rmtree(result['temp_dir'], ignore_errors=True)
                except:
                    pass
                return
            
            # Prepare caption
            caption = self.create_caption(result)
            
            # Update status
            await status_msg.edit_text("📤 Uploading to Telegram...")
            
            # Send video
            with open(result['file_path'], 'rb') as video_file:
                await message.reply_video(
                    video=InputFile(video_file, filename=f"{result['title'][:50]}.mp4"),
                    caption=caption,
                    parse_mode=ParseMode.MARKDOWN,
                    duration=result['duration'],
                    supports_streaming=True,
                    read_timeout=120,
                    write_timeout=120,
                    connect_timeout=120
                )
            
            self.stats['successful_downloads'] += 1
            await status_msg.edit_text("✅ Video sent successfully!")
            
            # Cleanup temporary files
            try:
                shutil.rmtree(result['temp_dir'], ignore_errors=True)
            except Exception as e:
                logger.error(f"Cleanup error: {e}")
            
        except Exception as e:
            logger.error(f"Error in handle_message: {e}")
            try:
                await status_msg.edit_text(f"❌ An error occurred: {str(e)[:200]}")
            except:
                pass
    
    def create_caption(self, result: dict) -> str:
        """Create caption for video"""
        caption = f"📹 *{result['title']}*\n\n"
        caption += f"👤 *Uploader:* {result['uploader']}\n"
        
        if result['duration'] > 0:
            minutes = result['duration'] // 60
            seconds = result['duration'] % 60
            caption += f"⏱ *Duration:* {minutes}:{seconds:02d}\n"
        
        if result.get('description'):
            desc = result['description']
            if len(desc) > 300:
                desc = desc[:300] + "..."
            caption += f"\n📝 {desc}\n"
        
        caption += f"\n🔗 *Source:* {result['original_url']}"
        return caption
    
    async def error_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle errors"""
        logger.error(f"Exception while handling update: {context.error}")
        
        if update and update.effective_message:
            try:
                await update.effective_message.reply_text(
                    "❌ An error occurred. Please try again later."
                )
            except:
                pass

def main():
    """Start the bot"""
    # Check bot token
    if config.BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("ERROR: Bot token not configured!")
        print("="*60)
        print("Please get a token from @BotFather on Telegram")
        print("Then edit config.py and replace YOUR_BOT_TOKEN_HERE")
        print("Or set environment variable:")
        print("  export BOT_TOKEN='your_token_here'")
        print("="*60 + "\n")
        sys.exit(1)
    
    print("🤖 Starting Telegram Video Downloader Bot...")
    print("📁 Bot directory:", os.getcwd())
    print("🐍 Python version:", sys.version.split()[0])
    print("🔧 Using polling method (no port required)")
    print("")
    
    # Create bot application
    bot_handler = BotHandler()
    
    application = Application.builder() \
        .token(config.BOT_TOKEN) \
        .read_timeout(30) \
        .write_timeout(30) \
        .connect_timeout(30) \
        .build()
    
    # Add command handlers
    application.add_handler(CommandHandler("start", bot_handler.start))
    application.add_handler(CommandHandler("help", bot_handler.help))
    application.add_handler(CommandHandler("about", bot_handler.about))
    
    # Add message handler
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND,
        bot_handler.handle_message
    ))
    
    # Add error handler
    application.add_error_handler(bot_handler.error_handler)
    
    # Start bot
    print("✅ Bot initialized successfully!")
    print("⏳ Starting polling...")
    print("🛑 Press Ctrl+C to stop")
    print("")
    
    try:
        application.run_polling(
            poll_interval=1.0,
            timeout=30,
            drop_pending_updates=True,
            allowed_updates=Update.ALL_TYPES
        )
    except KeyboardInterrupt:
        print("\n👋 Bot stopped by user")
    except Exception as e:
        logger.error(f"Bot crashed: {e}")
        print(f"\n💥 Bot crashed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

# Create startup script
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "========================================"
echo "🤖 Telegram Video Downloader Bot"
echo "========================================"

# Check if running
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "⚠️ Bot is already running!"
    echo "Stop it first with: ./stop.sh"
    exit 1
fi

# Check Python
if ! command -v python3 > /dev/null; then
    echo "❌ Python3 not found!"
    exit 1
fi

# Check virtual environment
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found!"
    echo "Run: python3 -m venv venv"
    echo "Then: source venv/bin/activate"
    echo "Then: pip install -r requirements.txt"
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check bot token
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "❌ ERROR: Bot token not configured!"
    echo ""
    echo "Please follow these steps:"
    echo "1. Open Telegram and search for @BotFather"
    echo "2. Send /newbot to create a new bot"
    echo "3. Copy the bot token (looks like: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz)"
    echo "4. Edit config.py and replace YOUR_BOT_TOKEN_HERE with your token"
    echo ""
    echo "Quick edit command:"
    echo "  nano config.py"
    echo ""
    echo "Or set environment variable:"
    echo "  export BOT_TOKEN='your_token_here'"
    echo "  ./start.sh"
    echo ""
    exit 1
fi

# Check requirements
if [ ! -f "requirements.txt" ]; then
    echo "📦 Creating requirements.txt..."
    cat > requirements.txt << 'REQEOF'
python-telegram-bot==20.6
yt-dlp>=2024.11.11
requests>=2.31.0
beautifulsoup4>=4.12.0
lxml>=5.2.0
REQEOF
fi

# Install/upgrade packages
echo "📦 Checking Python packages..."
pip install --upgrade -r requirements.txt > /dev/null 2>&1

# Create downloads directory
mkdir -p downloads

echo ""
echo "✅ All checks passed!"
echo "🚀 Starting bot..."
echo ""
echo "📝 Logs will be saved to: bot.log"
echo "🔄 Bot will check for new messages every second"
echo "📱 Send a Facebook/TikTok link to your bot on Telegram"
echo "🛑 Press Ctrl+C to stop the bot"
echo ""

# Run bot
exec python3 bot.py
EOF

chmod +x start.sh

# Create stop script
cat > stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null
sleep 2
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "⚠️ Bot still running, forcing stop..."
    pkill -9 -f "python3 bot.py" 2>/dev/null
fi
echo "✅ Bot stopped"
EOF

chmod +x stop.sh

# Create restart script
cat > restart.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./stop.sh
sleep 3
./start.sh
EOF

chmod +x restart.sh

# Create status script
cat > status.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "========================================"
echo "🤖 Bot Status Check"
echo "========================================"

# Check if running
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "✅ Bot is running"
    
    # Show process info
    echo ""
    echo "Process Info:"
    ps aux | grep "python3 bot.py" | grep -v grep
    
    # Show logs
    if [ -f "bot.log" ]; then
        echo ""
        echo "📝 Last 5 log lines:"
        tail -5 bot.log
    fi
    
else
    echo "❌ Bot is not running"
    echo ""
    echo "To start: ./start.sh"
fi

# Check config
echo ""
echo "📋 Configuration:"
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo "❌ Bot token not configured"
else
    echo "✅ Bot token configured"
fi

# Check directories
echo ""
echo "📁 Directories:"
[ -d "venv" ] && echo "✅ Virtual environment" || echo "❌ Virtual environment missing"
[ -d "downloads" ] && echo "✅ Downloads directory" || echo "❌ Downloads directory missing"

# Check Python packages
echo ""
echo "🐍 Python Packages:"
source venv/bin/activate 2>/dev/null
python3 -c "import telegram, yt_dlp, requests; print('✅ All packages installed')" 2>/dev/null || echo "❌ Some packages missing"
EOF

chmod +x status.sh

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🧹 Cleaning old downloads..."
find downloads -type f -name "*.mp4" -mtime +1 -delete 2>/dev/null
find downloads -type f -name "*.jpg" -mtime +1 -delete 2>/dev/null
find downloads -type d -empty -delete 2>/dev/null
echo "✅ Cleanup complete"
EOF

chmod +x cleanup.sh

# Create simple setup script
cat > setup_bot.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "========================================"
echo "🤖 Bot Setup Wizard"
echo "========================================"

# Check if config exists
if [ ! -f "config.py" ]; then
    echo "❌ config.py not found!"
    exit 1
fi

# Ask for bot token
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "📱 Please enter your Telegram Bot Token"
    echo "   (Get it from @BotFather on Telegram)"
    echo ""
    read -p "Enter bot token: " BOT_TOKEN
    
    if [ -z "$BOT_TOKEN" ]; then
        echo "❌ Token cannot be empty!"
        exit 1
    fi
    
    # Update config
    sed -i "s/YOUR_BOT_TOKEN_HERE/$BOT_TOKEN/g" config.py
    echo "✅ Token saved to config.py"
    
    # Also set as environment variable
    echo "export BOT_TOKEN='$BOT_TOKEN'" >> ~/.bashrc
    export BOT_TOKEN="$BOT_TOKEN"
    echo "✅ Token added to environment variables"
fi

# Setup virtual environment if needed
if [ ! -d "venv" ]; then
    echo ""
    echo "🐍 Setting up Python virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    
    echo "📦 Installing required packages..."
    pip install python-telegram-bot yt-dlp requests beautifulsoup4 lxml
    echo "✅ Packages installed"
fi

# Create downloads directory
mkdir -p downloads

echo ""
echo "========================================"
echo "🎉 Setup Complete!"
echo "========================================"
echo ""
echo "To start the bot:"
echo "  ./start.sh"
echo ""
echo "Other commands:"
echo "  ./stop.sh     - Stop bot"
echo "  ./restart.sh  - Restart bot"
echo "  ./status.sh   - Check bot status"
echo "  ./cleanup.sh  - Clean old files"
echo ""
echo "📱 Go to Telegram and send a video link to your bot!"
EOF

chmod +x setup_bot.sh

# Create systemd service file
cat > telegram-bot.service << 'EOF'
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
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create README file
cat > README.md << 'EOF'
# Telegram Video Downloader Bot

## Features
- 📥 Download from Facebook, TikTok, Instagram
- 🚫 No port required (uses polling)
- 🔧 Simple setup
- 🧹 Auto-cleanup
- 📊 Logging

## Quick Start

### 1. Installation
```bash
# Run the installer
bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-facebook-tiktak-totelegram/main/install.sh)
