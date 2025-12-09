#!/bin/bash

# Telegram Facebook & TikTok Downloader Bot Installer - Portless Version
# Created by: khodam-facebook-tiktak-totelegram
# GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [ "$EUID" -eq 0 ]; then 
    print_warning "Running as root is not recommended."
fi

print_info "Starting installation of Portless Telegram Video Downloader Bot..."

# Update system
print_info "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install dependencies
print_info "Installing dependencies..."
sudo apt-get install -y python3 python3-pip python3-venv git curl wget unzip

# Download and install static FFmpeg
print_info "Installing static FFmpeg..."
FFMPEG_DIR="$HOME/ffmpeg-static"
mkdir -p "$FFMPEG_DIR"
cd "$FFMPEG_DIR"

# Download latest static FFmpeg
FFMPEG_URL=$(curl -s https://api.github.com/repos/yt-dlp/FFmpeg-Builds/releases/latest | grep -o 'https://.*linux64.*.tar.xz' | head -1)
if [ -z "$FFMPEG_URL" ]; then
    FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-lgpl.tar.xz"
fi

wget -q "$FFMPEG_URL" -O ffmpeg.tar.xz
tar -xf ffmpeg.tar.xz --strip-components=1
chmod +x ffmpeg ffprobe
sudo cp ffmpeg ffprobe /usr/local/bin/
print_success "FFmpeg installed successfully"

# Create bot directory
BOT_DIR="$HOME/telegram-video-bot"
print_info "Creating bot directory at $BOT_DIR..."
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Create virtual environment
print_info "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python packages
print_info "Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.6
pip install yt-dlp
pip install requests
pip install beautifulsoup4
pip install lxml

# Create config.py
print_info "Creating configuration files..."
cat > config.py << 'EOF'
#!/usr/bin/env python3
import os

# Bot Configuration
BOT_TOKEN = os.environ.get("BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")
ADMIN_IDS = [int(x) for x in os.environ.get("ADMIN_IDS", "").split(",") if x]

# FFmpeg path
FFMPEG_PATH = "/usr/local/bin/ffmpeg"
FFPROBE_PATH = "/usr/local/bin/ffprobe"

# Download settings
MAX_FILE_SIZE = 2000 * 1024 * 1024  # 2GB
DOWNLOAD_PATH = "./downloads"
SUPPORTED_PLATFORMS = ["facebook.com", "fb.watch", "tiktok.com", "instagram.com"]

# Bot messages
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
/stats - Bot statistics
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

**Technologies:**
• Python Telegram Bot
• yt-dlp
• FFmpeg (static)

⚠️ For personal use only
"""
}
EOF

# Create main bot file
print_info "Creating main bot file..."
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Video Downloader Bot - Portless Version
Uses polling method without opening ports
"""

import os
import re
import sys
import time
import logging
import asyncio
import tempfile
from datetime import datetime
from urllib.parse import urlparse
from pathlib import Path

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
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Statistics
bot_stats = {
    "start_time": datetime.now(),
    "downloads": 0,
    "errors": 0,
    "users": set()
}

# Ensure download directory exists
os.makedirs(config.DOWNLOAD_PATH, exist_ok=True)

class VideoDownloader:
    """Handles video downloading and processing"""
    
    @staticmethod
    def is_supported_url(url: str) -> bool:
        """Check if URL is supported"""
        url_lower = url.lower()
        for platform in config.SUPPORTED_PLATFORMS:
            if platform in url_lower:
                return True
        return False
    
    @staticmethod
    def extract_video_info(url: str):
        """Extract video information"""
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': True,
            'ffmpeg_location': config.FFMPEG_PATH,
        }
        
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                return {
                    'title': info.get('title', 'Video'),
                    'duration': info.get('duration', 0),
                    'uploader': info.get('uploader', 'Unknown'),
                    'thumbnail': info.get('thumbnail'),
                    'description': info.get('description', ''),
                    'url': url
                }
        except Exception as e:
            logger.error(f"Info extraction failed: {e}")
            return None
    
    @staticmethod
    def download_video(url: str, user_id: int):
        """Download video and return file path"""
        temp_dir = tempfile.mkdtemp(dir=config.DOWNLOAD_PATH)
        output_template = os.path.join(temp_dir, '%(title).100s.%(ext)s')
        
        ydl_opts = {
            'format': 'best[filesize<50M]',
            'outtmpl': output_template,
            'quiet': False,
            'no_warnings': False,
            'ffmpeg_location': config.FFMPEG_PATH,
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
            'progress_hooks': [VideoDownloader.progress_hook],
            'cookiefile': 'cookies.txt' if os.path.exists('cookies.txt') else None,
        }
        
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                downloaded_file = ydl.prepare_filename(info)
                
                # Convert to MP4 if needed
                if not downloaded_file.endswith('.mp4'):
                    mp4_file = os.path.splitext(downloaded_file)[0] + '.mp4'
                    if os.path.exists(mp4_file):
                        downloaded_file = mp4_file
                
                # Get thumbnail
                thumbnail = None
                if info.get('thumbnail'):
                    thumbnail = info.get('thumbnail')
                else:
                    thumb_candidates = [
                        os.path.splitext(downloaded_file)[0] + '.jpg',
                        os.path.splitext(downloaded_file)[0] + '.webp',
                    ]
                    for thumb in thumb_candidates:
                        if os.path.exists(thumb):
                            thumbnail = thumb
                            break
                
                return {
                    'success': True,
                    'file_path': downloaded_file,
                    'thumbnail': thumbnail,
                    'title': info.get('title', 'Video'),
                    'duration': info.get('duration', 0),
                    'uploader': info.get('uploader', 'Unknown'),
                    'description': info.get('description', ''),
                    'temp_dir': temp_dir
                }
                
        except Exception as e:
            logger.error(f"Download failed: {e}")
            # Cleanup temp dir
            try:
                import shutil
                shutil.rmtree(temp_dir, ignore_errors=True)
            except:
                pass
            return {
                'success': False,
                'error': str(e)
            }
    
    @staticmethod
    def progress_hook(d):
        """Progress hook for yt-dlp"""
        if d['status'] == 'downloading':
            percent = d.get('_percent_str', '0%').strip()
            speed = d.get('_speed_str', 'N/A')
            eta = d.get('_eta_str', 'N/A')
            logger.info(f"Downloading: {percent} | Speed: {speed} | ETA: {eta}")

class BotHandlers:
    """Telegram bot handlers"""
    
    @staticmethod
    async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        bot_stats["users"].add(user.id)
        
        await update.message.reply_text(
            config.MESSAGES["start"],
            parse_mode=ParseMode.MARKDOWN
        )
    
    @staticmethod
    async def help(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        await update.message.reply_text(
            config.MESSAGES["help"],
            parse_mode=ParseMode.MARKDOWN
        )
    
    @staticmethod
    async def about(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /about command"""
        await update.message.reply_text(
            config.MESSAGES["about"],
            parse_mode=ParseMode.MARKDOWN
        )
    
    @staticmethod
    async def stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /stats command"""
        if update.effective_user.id not in config.ADMIN_IDS and config.ADMIN_IDS:
            await update.message.reply_text("⚠️ Admin only command")
            return
        
        uptime = datetime.now() - bot_stats["start_time"]
        stats_text = f"""
📊 **Bot Statistics**

⏱ **Uptime:** {str(uptime).split('.')[0]}
📥 **Downloads:** {bot_stats["downloads"]}
❌ **Errors:** {bot_stats["errors"]}
👥 **Users:** {len(bot_stats["users"])}
💾 **Free Space:** {BotHandlers.get_free_space()}

**Last Update:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
"""
        await update.message.reply_text(stats_text, parse_mode=ParseMode.MARKDOWN)
    
    @staticmethod
    def get_free_space():
        """Get free disk space"""
        try:
            import shutil
            total, used, free = shutil.disk_usage(".")
            return f"{free // (2**30)}GB free"
        except:
            return "Unknown"
    
    @staticmethod
    async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle incoming messages"""
        user = update.effective_user
        message = update.message
        text = message.text.strip()
        
        # Extract URL
        url_pattern = r'https?://[^\s]+'
        urls = re.findall(url_pattern, text)
        
        if not urls:
            await message.reply_text("Please send a valid video URL.")
            return
        
        url = urls[0]
        
        # Check if supported
        if not VideoDownloader.is_supported_url(url):
            platforms = ", ".join(config.SUPPORTED_PLATFORMS)
            await message.reply_text(
                f"❌ Unsupported URL.\n\nSupported platforms:\n{platforms}"
            )
            return
        
        # Send processing message
        status_msg = await message.reply_text(
            "🔄 Processing your request...\n"
            "⏳ Downloading video, please wait..."
        )
        
        try:
            # Get video info first
            video_info = VideoDownloader.extract_video_info(url)
            if not video_info:
                await status_msg.edit_text("❌ Failed to get video information.")
                return
            
            # Update status
            await status_msg.edit_text(
                f"📥 Downloading: *{video_info['title']}*\n"
                f"👤 From: {video_info['uploader']}\n"
                f"⏱ Duration: {video_info['duration']}s"
            )
            
            # Download video
            result = VideoDownloader.download_video(url, user.id)
            
            if not result['success']:
                bot_stats["errors"] += 1
                await status_msg.edit_text(f"❌ Download failed:\n{result['error']}")
                return
            
            # Check file size
            file_size = os.path.getsize(result['file_path'])
            if file_size > config.MAX_FILE_SIZE:
                await status_msg.edit_text(
                    f"❌ File too large ({file_size/(1024*1024):.2f}MB).\n"
                    f"Max allowed: {config.MAX_FILE_SIZE/(1024*1024)}MB"
                )
                BotHandlers.cleanup_temp(result['temp_dir'])
                return
            
            # Prepare caption
            caption = BotHandlers.create_caption(result, url)
            
            # Send video
            await status_msg.edit_text("📤 Uploading to Telegram...")
            
            with open(result['file_path'], 'rb') as video_file:
                await message.reply_video(
                    video=InputFile(video_file, filename=f"{result['title'][:50]}.mp4"),
                    caption=caption,
                    parse_mode=ParseMode.MARKDOWN,
                    duration=result['duration'],
                    supports_streaming=True,
                    read_timeout=60,
                    write_timeout=60,
                    connect_timeout=60
                )
            
            bot_stats["downloads"] += 1
            await status_msg.edit_text("✅ Video sent successfully!")
            
            # Cleanup
            BotHandlers.cleanup_temp(result['temp_dir'])
            
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            bot_stats["errors"] += 1
            try:
                await status_msg.edit_text(f"❌ Error: {str(e)[:200]}")
            except:
                pass
    
    @staticmethod
    def create_caption(result: dict, original_url: str) -> str:
        """Create caption for video"""
        title = result['title'][:100]
        uploader = result['uploader'][:50]
        duration = result['duration']
        
        caption = f"📹 *{title}*\n\n"
        caption += f"👤 *Uploader:* {uploader}\n"
        
        if duration > 0:
            mins, secs = divmod(duration, 60)
            caption += f"⏱ *Duration:* {int(mins)}:{int(secs):02d}\n"
        
        if result.get('description'):
            desc = result['description'][:150]
            if len(result['description']) > 150:
                desc += "..."
            caption += f"\n📝 {desc}\n"
        
        caption += f"\n🔗 *Source:* [Click Here]({original_url})"
        caption += f"\n\n🤖 *Sent by:* @{(await context.bot.get_me()).username}"
        
        return caption
    
    @staticmethod
    def cleanup_temp(temp_dir: str):
        """Cleanup temporary files"""
        try:
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
        except:
            pass
    
    @staticmethod
    async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle errors"""
        logger.error(f"Error: {context.error}")
        if update and update.effective_message:
            try:
                await update.effective_message.reply_text(
                    "❌ An error occurred. Please try again."
                )
            except:
                pass

def main():
    """Main function to start the bot"""
    # Check token
    if config.BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("ERROR: Bot token not set!")
        print("="*60)
        print("1. Get a token from @BotFather on Telegram")
        print("2. Edit config.py or set BOT_TOKEN environment variable")
        print("3. Example: export BOT_TOKEN='your_token_here'")
        print("="*60 + "\n")
        sys.exit(1)
    
    # Create application
    print("🤖 Initializing bot...")
    
    # Set bot options
    application = Application.builder() \
        .token(config.BOT_TOKEN) \
        .read_timeout(60) \
        .write_timeout(60) \
        .connect_timeout(60) \
        .pool_timeout(60) \
        .build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", BotHandlers.start))
    application.add_handler(CommandHandler("help", BotHandlers.help))
    application.add_handler(CommandHandler("about", BotHandlers.about))
    application.add_handler(CommandHandler("stats", BotHandlers.stats))
    
    # Handle text messages
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND,
        BotHandlers.handle_message
    ))
    
    # Error handler
    application.add_error_handler(BotHandlers.error_handler)
    
    # Start bot
    print("\n" + "="*60)
    print("🎉 Bot is starting...")
    print("📱 Bot uses polling (no port needed)")
    print("🛑 Press Ctrl+C to stop")
    print("="*60 + "\n")
    
    try:
        # Run bot with polling
        application.run_polling(
            poll_interval=1.0,
            timeout=60,
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

# Create requirements.txt
cat > requirements.txt << 'EOF'
python-telegram-bot==20.6
yt-dlp>=2024.4.9
requests>=2.31.0
beautifulsoup4>=4.12.0
lxml>=5.2.0
EOF

# Create startup script
cat > start_bot.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Starting Telegram Video Downloader Bot..."
echo "📍 Directory: $(pwd)"
echo "🐍 Python: $(python3 --version)"
echo "🔄 Using polling method (no port required)"

# Check if venv exists
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found. Run install.sh first."
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ FFmpeg not found. Installing..."
    wget -q https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-lgpl.tar.xz -O ffmpeg.tar.xz
    tar -xf ffmpeg.tar.xz --strip-components=1
    chmod +x ffmpeg ffprobe
    sudo mv ffmpeg ffprobe /usr/local/bin/
    echo "✅ FFmpeg installed"
fi

# Check bot token
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "❌ Bot token not configured!"
    echo ""
    echo "Please set your bot token:"
    echo "1. Get token from @BotFather"
    echo "2. Edit config.py and replace YOUR_BOT_TOKEN_HERE"
    echo "3. Or run: export BOT_TOKEN='your_token_here'"
    echo ""
    read -p "Enter bot token now (or press Enter to skip): " BOT_TOKEN
    if [ ! -z "$BOT_TOKEN" ]; then
        sed -i "s/YOUR_BOT_TOKEN_HERE/$BOT_TOKEN/g" config.py
        echo "✅ Token updated in config.py"
    else
        echo "⚠️  Using environment variable BOT_TOKEN"
    fi
fi

# Run bot
echo ""
echo "🚀 Starting bot..."
echo "📝 Logs will be saved to bot.log"
echo "🛑 Press Ctrl+C to stop"
echo ""

exec python3 bot.py
EOF

chmod +x start_bot.sh

# Create systemd service
cat > telegram-bot.service << EOF
[Unit]
Description=Telegram Video Downloader Bot (Portless)
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$BOT_DIR
Environment="PATH=$BOT_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="BOT_TOKEN=YOUR_BOT_TOKEN_HERE"
ExecStart=$BOT_DIR/start_bot.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create quick setup script
cat > quick_setup.sh << 'EOF'
#!/bin/bash
echo "⚡ Quick Setup for Telegram Video Bot"
echo ""

# Get bot token
read -p "Enter your Telegram Bot Token: " BOT_TOKEN
if [ -z "$BOT_TOKEN" ]; then
    echo "❌ Token is required!"
    exit 1
fi

# Update config
cd "$(dirname "$0")"
sed -i "s/YOUR_BOT_TOKEN_HERE/$BOT_TOKEN/g" config.py

# Set as environment variable
echo "export BOT_TOKEN='$BOT_TOKEN'" >> ~/.bashrc
export BOT_TOKEN="$BOT_TOKEN"

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start bot manually:"
echo "  cd ~/telegram-video-bot && ./start_bot.sh"
echo ""
echo "To run as service:"
echo "  sudo cp telegram-bot.service /etc/systemd/system/"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable telegram-bot"
echo "  sudo systemctl start telegram-bot"
EOF

chmod +x quick_setup.sh

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash
echo "🧹 Cleaning up old downloads..."
cd "$(dirname "$0")"
find ./downloads -type f -name "*.mp4" -mtime +1 -delete
find ./downloads -type f -name "*.jpg" -mtime +1 -delete
find ./downloads -type d -empty -delete
echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

# Create README
cat > README.md << 'EOF'
# Telegram Video Downloader Bot (Portless)

## Features
- 📥 Downloads from Facebook, TikTok, Instagram
- 🚫 No port required (uses polling)
- 📦 Includes FFmpeg (no separate installation)
- 💾 Auto-cleanup of temp files
- 📊 Statistics tracking

## Quick Start

1. **Set bot token:**
   ```bash
   ./quick_setup.sh
