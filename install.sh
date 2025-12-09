#!/bin/bash

# Telegram Video Downloader Bot - Fixed Version
# Fixes: 
# 1. Telegram entity parsing error
# 2. Facebook/TikTok download issues
# 3. Better error handling

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

log_info "Starting installation of Fixed Video Downloader Bot..."

# Update system
log_info "Updating system..."
apt-get update -y
apt-get upgrade -y

# Install dependencies
log_info "Installing dependencies..."
apt-get install -y python3 python3-pip python3-venv git curl wget

# Create bot directory
BOT_DIR="/root/telegram-video-bot"
log_info "Creating bot directory at $BOT_DIR..."
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Create virtual environment
log_info "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python packages
log_info "Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.6 yt-dlp requests beautifulsoup4 lxml

# Create improved config.py
log_info "Creating configuration files..."
cat > config.py << 'CONFIGEOF'
#!/usr/bin/env python3
import os

BOT_TOKEN = os.environ.get("BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")

# Download settings
MAX_FILE_SIZE = 1800 * 1024 * 1024  # 1.8GB (safe limit)
DOWNLOAD_PATH = "./downloads"
TEMP_PATH = "./temp"

# Cookie files for better access
COOKIE_FILE = "cookies.txt" if os.path.exists("cookies.txt") else None

# User agent for requests
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

MESSAGES = {
    "start": """
🤖 **Video Downloader Bot**

Send me a link from:
• TikTok (videos)
• Facebook (videos, reels)
• Instagram (reels, posts)

I'll download and send it to you!

📌 **Note:** Some videos may require login or have restrictions.

Commands:
/start - Start bot
/help - Show help
/about - About bot
""",
    
    "help": """
📖 **How to use:**

1. Send a TikTok/Facebook/Instagram link
2. Wait for download
3. Receive video in Telegram

⚠️ **Important:**
- TikTok links should be like: https://www.tiktok.com/@username/video/123456789
- Facebook links should be direct video links
- Some private videos cannot be downloaded
""",
    
    "about": """
📱 **Video Downloader Bot**

GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

Uses yt-dlp for downloading videos.
"""
}
CONFIGEOF

# Create main bot file with fixes
log_info "Creating improved bot.py..."
cat > bot.py << 'BOTEOF'
#!/usr/bin/env python3
"""
Improved Telegram Video Downloader Bot
Fixed: 
1. Telegram entity parsing error
2. Facebook/TikTok download issues
3. Better error handling
"""

import os
import re
import sys
import logging
import shutil
import tempfile
import html
from datetime import datetime
from urllib.parse import urlparse, unquote

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

# Create directories
os.makedirs(config.DOWNLOAD_PATH, exist_ok=True)
os.makedirs(config.TEMP_PATH, exist_ok=True)

def clean_text(text):
    """Clean text for Telegram to avoid entity parsing errors"""
    if not text:
        return ""
    
    # Escape Markdown special characters
    special_chars = ['_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!']
    
    # First decode URL encoded characters
    try:
        text = unquote(text)
    except:
        pass
    
    # Escape HTML entities
    text = html.unescape(text)
    
    # Escape Markdown characters
    for char in special_chars:
        text = text.replace(char, f'\\{char}')
    
    # Remove or replace other problematic characters
    text = re.sub(r'[\x00-\x1F\x7F-\x9F]', '', text)  # Remove control characters
    text = re.sub(r'[^\x20-\x7E\u0600-\u06FF\uFB50-\uFDFF\uFE70-\uFEFF]', '', text)  # Keep common Unicode
    
    # Limit length
    if len(text) > 1000:
        text = text[:997] + "..."
    
    return text.strip()

def is_valid_url(url):
    """Check if URL is valid and from supported platform"""
    try:
        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            return False
        
        # Decode URL first
        decoded_url = unquote(url.lower())
        
        # Check for TikTok patterns
        tiktok_patterns = [
            r'tiktok\.com/.+/video/',
            r'tiktok\.com/@[^/]+/video/',
            r'vm\.tiktok\.com/',
            r'vt\.tiktok\.com/',
            r'www\.tiktok\.com/t/',
        ]
        
        for pattern in tiktok_patterns:
            if re.search(pattern, decoded_url):
                return "tiktok"
        
        # Check for Facebook patterns (avoid login pages)
        if 'facebook.com' in decoded_url:
            if 'login' in decoded_url or 'dialog' in decoded_url:
                return False
            facebook_patterns = [
                r'facebook\.com/.+/videos/',
                r'facebook\.com/watch/?\?v=',
                r'fb\.watch/',
                r'facebook\.com/reel/',
                r'facebook\.com/.+/reel/',
            ]
            for pattern in facebook_patterns:
                if re.search(pattern, decoded_url):
                    return "facebook"
        
        # Check for Instagram
        if 'instagram.com' in decoded_url:
            instagram_patterns = [
                r'instagram\.com/(p|reel|tv)/',
                r'instagram\.com/.+/(p|reel|tv)/',
            ]
            for pattern in instagram_patterns:
                if re.search(pattern, decoded_url):
                    return "instagram"
        
        return False
        
    except Exception:
        return False

def fix_tiktok_url(url):
    """Fix TikTok URL if needed"""
    # Remove tracking parameters
    url = re.sub(r'\?.*', '', url)
    
    # If it's a shortened URL, we'll let yt-dlp handle it
    if 'vm.tiktok.com' in url or 'vt.tiktok.com' in url:
        return url
    
    # Ensure it's a proper video URL
    if '/video/' not in url:
        # Try to extract video ID
        match = re.search(r'/video/(\d+)', url)
        if match:
            return f"https://www.tiktok.com/@tiktok/video/{match.group(1)}"
    
    return url

def fix_facebook_url(url):
    """Fix Facebook URL if needed"""
    # Remove login redirects
    if 'facebook.com/login' in url:
        # Try to extract the actual video URL from redirect
        match = re.search(r'next=(https?%3A%2F%2F[^&]+)', url)
        if match:
            decoded = unquote(unquote(match.group(1)))
            return decoded
    
    # Remove tracking parameters
    url = re.sub(r'(&|\?)rdid=[^&]+', '', url)
    url = re.sub(r'(&|\?)share_[^&]+', '', url)
    url = re.sub(r'(&|\?)set=[^&]+', '', url)
    
    return url

def download_video(url, platform):
    """Download video with improved error handling"""
    temp_dir = tempfile.mkdtemp(dir=config.TEMP_PATH)
    
    # Platform-specific options
    ydl_opts = {
        'outtmpl': os.path.join(temp_dir, '%(title).100s.%(ext)s'),
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
            'Accept-Encoding': 'gzip, deflate',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
        },
        'cookiefile': config.COOKIE_FILE,
        'no_check_certificate': True,
        'ignoreerrors': True,
        'retries': 3,
        'fragment_retries': 3,
        'skip_unavailable_fragments': True,
        'extractor_args': {
            'facebook': {
                'credentials': None,
                'formats': 'hd'
            },
            'tiktok': {
                'app_version': '29.0.0',
                'manifest_app_version': '29.0.0',
                'fp': 'verify_random_string'
            }
        },
    }
    
    # Platform-specific format selection
    if platform == "tiktok":
        ydl_opts['format'] = 'best[height<=720]'  # Lower quality for TikTok (usually works better)
    elif platform == "facebook":
        ydl_opts['format'] = 'best[height<=720][filesize<100M]'
    else:
        ydl_opts['format'] = 'best[filesize<100M]'
    
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # First get info without downloading
            info = ydl.extract_info(url, download=False)
            
            if not info:
                return {
                    'success': False,
                    'error': 'Could not extract video information'
                }
            
            # Check if video is available
            if info.get('availability') == 'needs_auth' or info.get('availability') == 'subscriber_only':
                return {
                    'success': False,
                    'error': 'Video requires login or is private'
                }
            
            # Now download
            ydl.download([url])
            
            # Find downloaded file
            files = os.listdir(temp_dir)
            video_files = [f for f in files if f.endswith(('.mp4', '.webm', '.mkv'))]
            
            if not video_files:
                # Try to find any video file
                all_files = os.listdir(temp_dir)
                for f in all_files:
                    if os.path.getsize(os.path.join(temp_dir, f)) > 100000:  # More than 100KB
                        video_files = [f]
                        break
            
            if not video_files:
                return {
                    'success': False,
                    'error': 'No video file found after download'
                }
            
            video_file = video_files[0]
            file_path = os.path.join(temp_dir, video_file)
            
            # Get thumbnail if exists
            thumbnail = None
            thumb_files = [f for f in files if f.endswith(('.jpg', '.jpeg', '.png', '.webp'))]
            if thumb_files:
                thumbnail = os.path.join(temp_dir, thumb_files[0])
            
            # Clean title and description
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
                'thumbnail': thumbnail,
                'temp_dir': temp_dir,
                'url': url,
                'platform': platform
            }
            
    except DownloadError as e:
        logger.error(f"Download error for {url}: {e}")
        # Try alternative approach for TikTok
        if platform == "tiktok":
            return try_alternative_tiktok_download(url, temp_dir)
        
        return {
            'success': False,
            'error': str(e)
        }
    except Exception as e:
        logger.error(f"Unexpected error for {url}: {e}")
        return {
            'success': False,
            'error': f'Unexpected error: {str(e)[:100]}'
        }
    finally:
        # Don't cleanup here, cleanup after sending
        pass

def try_alternative_tiktok_download(url, temp_dir):
    """Try alternative method for TikTok downloads"""
    try:
        # Alternative yt-dlp options for TikTok
        alt_opts = {
            'outtmpl': os.path.join(temp_dir, 'video.%(ext)s'),
            'format': 'best',
            'http_headers': {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Referer': 'https://www.tiktok.com/',
            },
            'cookiefile': config.COOKIE_FILE,
        }
        
        with yt_dlp.YoutubeDL(alt_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            
            files = os.listdir(temp_dir)
            video_files = [f for f in files if f.endswith('.mp4')]
            
            if video_files:
                file_path = os.path.join(temp_dir, video_files[0])
                
                return {
                    'success': True,
                    'file_path': file_path,
                    'title': clean_text(info.get('title', 'TikTok Video')),
                    'duration': info.get('duration', 0),
                    'uploader': clean_text(info.get('uploader', 'TikTok User')),
                    'description': '',
                    'thumbnail': None,
                    'temp_dir': temp_dir,
                    'url': url,
                    'platform': 'tiktok'
                }
            
    except Exception as e:
        logger.error(f"Alternative TikTok download failed: {e}")
    
    # Cleanup on failure
    try:
        shutil.rmtree(temp_dir, ignore_errors=True)
    except:
        pass
    
    return {
        'success': False,
        'error': 'Failed to download TikTok video. Video may be private or require login.'
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
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
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
    
    # Extract URL
    urls = re.findall(r'https?://[^\s]+', text)
    
    if not urls:
        await message.reply_text(
            "Please send a valid TikTok, Facebook, or Instagram video URL.\n\n"
            "Examples:\n"
            "• TikTok: https://www.tiktok.com/@username/video/123456789\n"
            "• Facebook: https://www.facebook.com/username/videos/123456789\n"
            "• Instagram: https://www.instagram.com/reel/ABC123DEF456/"
        )
        return
    
    url = urls[0]
    
    # Validate URL
    platform = is_valid_url(url)
    if not platform:
        await message.reply_text(
            "❌ Invalid or unsupported URL.\n\n"
            "Please make sure:\n"
            "1. URL is from TikTok, Facebook, or Instagram\n"
            "2. It's a direct video link (not a login page)\n"
            "3. Video is public and accessible"
        )
        return
    
    # Fix URL if needed
    if platform == "tiktok":
        url = fix_tiktok_url(url)
    elif platform == "facebook":
        url = fix_facebook_url(url)
    
    # Send status
    status_msg = await message.reply_text(f"🔍 Detected {platform} link...\n⏳ Processing...")
    
    try:
        await status_msg.edit_text(f"📥 Downloading from {platform}...")
        
        result = download_video(url, platform)
        
        if not result['success']:
            error_msg = result['error']
            
            # Provide helpful suggestions based on error
            suggestions = ""
            if "login" in error_msg.lower() or "private" in error_msg.lower():
                suggestions = "\n\nℹ️ This video may be private or require login."
            elif "tiktok" in platform:
                suggestions = "\n\nℹ️ Try getting a fresh link from TikTok app by clicking 'Share' -> 'Copy Link'"
            
            await status_msg.edit_text(f"❌ Download failed: {error_msg}{suggestions}")
            
            # Cleanup
            if 'temp_dir' in result:
                try:
                    shutil.rmtree(result['temp_dir'], ignore_errors=True)
                except:
                    pass
            return
        
        # Check file size
        try:
            file_size = os.path.getsize(result['file_path'])
            if file_size > config.MAX_FILE_SIZE:
                await status_msg.edit_text(
                    f"❌ File too large ({file_size/(1024*1024):.1f}MB). "
                    f"Telegram limit is {config.MAX_FILE_SIZE/(1024*1024):.0f}MB"
                )
                shutil.rmtree(result['temp_dir'], ignore_errors=True)
                return
        except:
            pass
        
        # Prepare caption (with cleaned text)
        caption = f"📹 *{result['title']}*\n\n"
        caption += f"👤 *Uploader:* {result['uploader']}\n"
        caption += f"📱 *Platform:* {result['platform'].title()}\n"
        
        if result['duration'] > 0:
            mins = result['duration'] // 60
            secs = result['duration'] % 60
            caption += f"⏱ *Duration:* {mins}:{secs:02d}\n"
        
        if result['description']:
            desc = result['description']
            if len(desc) > 200:
                desc = desc[:197] + "..."
            caption += f"\n{desc}\n"
        
        # Send video
        await status_msg.edit_text("📤 Uploading to Telegram...")
        
        try:
            with open(result['file_path'], 'rb') as f:
                await message.reply_video(
                    video=InputFile(f, filename=f"{result['platform']}_video.mp4"),
                    caption=caption,
                    parse_mode=ParseMode.MARKDOWN,
                    duration=result['duration'],
                    supports_streaming=True,
                    read_timeout=180,
                    write_timeout=180,
                    connect_timeout=180
                )
            
            await status_msg.edit_text("✅ Video sent successfully!")
            
        except Exception as e:
            logger.error(f"Upload error: {e}")
            await status_msg.edit_text(f"❌ Failed to upload: {str(e)[:100]}")
        
        # Cleanup
        try:
            shutil.rmtree(result['temp_dir'], ignore_errors=True)
        except:
            pass
        
    except Exception as e:
        logger.error(f"Processing error: {e}")
        try:
            await status_msg.edit_text(f"❌ Processing error: {str(e)[:100]}")
        except:
            pass

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    error = context.error
    logger.error(f"Update {update} caused error: {error}")
    
    # Ignore minor errors
    if "Connection refused" in str(error):
        return
    
    if update and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "❌ An error occurred. Please try again with a different link."
            )
        except:
            pass

def main():
    """Start the bot"""
    if config.BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("ERROR: Bot token not configured!")
        print("="*60)
        print("Please follow these steps:")
        print("1. Open Telegram and search for @BotFather")
        print("2. Create a new bot with /newbot")
        print("3. Copy the bot token")
        print("4. Edit config.py and replace YOUR_BOT_TOKEN_HERE")
        print("="*60)
        sys.exit(1)
    
    print("🤖 Improved Video Downloader Bot")
    print("✅ Fixed: Telegram entity parsing error")
    print("✅ Fixed: TikTok/Facebook download issues")
    print("✅ Better error handling and URL validation")
    print("")
    
    # Create application
    application = Application.builder() \
        .token(config.BOT_TOKEN) \
        .read_timeout(180) \
        .write_timeout(180) \
        .connect_timeout(180) \
        .pool_timeout(180) \
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
    print("🚀 Starting bot...")
    print("📝 Logs: bot.log")
    print("🛑 Stop with Ctrl+C")
    print("")
    
    try:
        application.run_polling(
            poll_interval=1.0,
            timeout=30,
            drop_pending_updates=True,
            allowed_updates=Update.ALL_TYPES
        )
    except KeyboardInterrupt:
        print("\n👋 Bot stopped")
    except Exception as e:
        logger.error(f"Bot crashed: {e}")
        print(f"\n💥 Fatal error: {e}")

if __name__ == '__main__':
    main()
BOTEOF

# Create start script
cat > start.sh << 'STARTEOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "========================================"
echo "🤖 Improved Video Downloader Bot"
echo "========================================"

# Check if running
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "⚠️ Bot is already running!"
    echo "Stop with: ./stop.sh"
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
    echo "Creating venv..."
    python3 -m venv venv
fi

# Activate venv
source venv/bin/activate

# Check/install packages
echo "📦 Checking Python packages..."
pip install --upgrade python-telegram-bot==20.6 yt-dlp requests beautifulsoup4 lxml > /dev/null 2>&1

# Check token
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "❌ Bot token not configured!"
    echo ""
    echo "To fix:"
    echo "1. Get token from @BotFather"
    echo "2. Edit config.py"
    echo "3. Replace YOUR_BOT_TOKEN_HERE with your token"
    echo ""
    exit 1
fi

# Create directories
mkdir -p downloads temp

echo ""
echo "✅ All checks passed"
echo "🚀 Starting improved bot..."
echo ""
echo "Fixes applied:"
echo "• Fixed Telegram entity parsing errors"
echo "• Better TikTok/Facebook download support"
echo "• Improved error messages"
echo ""
echo "📝 Logs: tail -f bot.log"
echo "🛑 Stop: Ctrl+C or ./stop.sh"
echo ""

exec python3 bot.py
STARTEOF

chmod +x start.sh

# Create stop script
cat > stop.sh << 'STOPEOF'
#!/bin/bash
echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null
sleep 3
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "⚠️ Force stopping..."
    pkill -9 -f "python3 bot.py" 2>/dev/null
fi
echo "✅ Bot stopped"
STOPEOF

chmod +x stop.sh

# Create setup script
cat > setup.sh << 'SETUPEOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Bot Setup"
echo "============"

if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "Enter your Telegram Bot Token from @BotFather:"
    read -p "Token: " TOKEN
    
    if [ -z "$TOKEN" ]; then
        echo "❌ Token cannot be empty"
        exit 1
    fi
    
    # Update config
    sed -i "s/YOUR_BOT_TOKEN_HERE/$TOKEN/g" config.py
    
    echo "✅ Token saved to config.py"
    echo ""
    echo "Optional: For better success rate with TikTok/Facebook:"
    echo "1. You can add cookies to cookies.txt file"
    echo "2. Export cookies from your browser"
    echo "3. Save as cookies.txt in bot directory"
    echo ""
    
    echo "🎉 Setup complete!"
    echo "Start bot: ./start.sh"
else
    echo "✅ Bot already configured"
    echo "Start bot: ./start.sh"
fi
SETUPEOF

chmod +x setup.sh

# Create README
cat > README.md << 'READMEEOF'
# Improved Video Downloader Bot

## Fixed Issues:
1. ✅ Telegram entity parsing error (special characters in captions)
2. ✅ TikTok download failures
3. ✅ Facebook login redirect issues
4. ✅ Better error handling and messages

## How to use:
1. Make sure you have a fresh video link:
   - TikTok: Use "Share" -> "Copy Link" from TikTok app
   - Facebook: Use direct video URL (not login pages)
   - Instagram: Use direct reel/post URL

2. Common issues and solutions:
   - "Video requires login": Video is private
   - "Unsupported URL": Not a direct video link
   - "Download failed": Try getting a fresh link

## Start bot:
```bash
./start.sh
