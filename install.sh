#!/bin/bash

# Professional Telegram Video Downloader Bot
# Enhanced version with better TikTok/Facebook support
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

log "Installing Professional Video Downloader Bot..."

# Update system
log "Updating system..."
apt-get update -y
apt-get upgrade -y

# Install dependencies
log "Installing dependencies..."
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg

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
pip install python-telegram-bot==20.6 yt-dlp==2025.12.8 requests==2.31.0 beautifulsoup4==4.12.0 lxml==5.2.0

# Create enhanced config
log "Creating configuration files..."

# config.py
cat > config.py << 'EOF'
#!/usr/bin/env python3
import os

BOT_TOKEN = os.environ.get("BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")

MAX_FILE_SIZE = 2000 * 1024 * 1024
DOWNLOAD_PATH = "./downloads"
TEMP_PATH = "./temp"

# Multiple user agents for better compatibility
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.210 Mobile Safari/537.36"
]

MESSAGES = {
    "start": "🤖 **Video Downloader Bot**\n\nSend me TikTok, Facebook, or Instagram links\n\n✅ Better download success rate\n✅ Multiple retry methods\n✅ Automatic link fixing",
    "help": "📖 **Tips for better results:**\n\n• Use fresh links from mobile apps\n• TikTok: Share → Copy Link\n• Facebook: Direct video URLs\n• Some videos are private",
    "about": "📱 **Enhanced Video Downloader**\n\nMultiple download methods for better success rate"
}
EOF

# Create main bot with multiple download methods
log "Creating enhanced bot.py..."

cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Enhanced Telegram Video Downloader
Multiple download methods for better success rate
"""

import os
import re
import sys
import json
import logging
import shutil
import tempfile
import random
import time
from urllib.parse import urlparse, unquote, quote
from datetime import datetime

from telegram import Update, InputFile
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.constants import ParseMode

import yt_dlp
import requests
from bs4 import BeautifulSoup

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

class VideoDownloader:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': random.choice(config.USER_AGENTS),
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate, br',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'none',
            'Sec-Fetch-User': '?1',
        })
    
    def extract_tiktok_info(self, url):
        """Extract TikTok video info using multiple methods"""
        try:
            # Method 1: Direct yt-dlp
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': True,
                'user_agent': random.choice(config.USER_AGENTS),
                'referer': 'https://www.tiktok.com/',
                'cookiefile': 'cookies.txt' if os.path.exists('cookies.txt') else None,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                if info:
                    return {
                        'success': True,
                        'title': info.get('title', 'TikTok Video'),
                        'uploader': info.get('uploader', 'TikTok User'),
                        'duration': info.get('duration', 0),
                        'url': info.get('webpage_url', url)
                    }
            
            # Method 2: Try with different user agent
            ydl_opts['user_agent'] = config.USER_AGENTS[2]  # Mobile user agent
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                if info:
                    return {
                        'success': True,
                        'title': info.get('title', 'TikTok Video'),
                        'uploader': info.get('uploader', 'TikTok User'),
                        'duration': info.get('duration', 0),
                        'url': info.get('webpage_url', url)
                    }
            
            # Method 3: Try to get from HTML
            response = self.session.get(url, timeout=10)
            if response.status_code == 200:
                soup = BeautifulSoup(response.text, 'html.parser')
                
                # Look for JSON-LD data
                script_tags = soup.find_all('script', type='application/ld+json')
                for script in script_tags:
                    try:
                        data = json.loads(script.string)
                        if isinstance(data, dict) and 'name' in data:
                            return {
                                'success': True,
                                'title': data.get('name', 'TikTok Video'),
                                'uploader': data.get('author', {}).get('name', 'TikTok User'),
                                'duration': 0,
                                'url': url
                            }
                    except:
                        pass
                
                # Look for Open Graph data
                title = soup.find('meta', property='og:title')
                if title and title.get('content'):
                    return {
                        'success': True,
                        'title': title['content'],
                        'uploader': 'TikTok User',
                        'duration': 0,
                        'url': url
                    }
            
            return {'success': False, 'error': 'Cannot extract TikTok info'}
            
        except Exception as e:
            logger.error(f"TikTok info extraction error: {e}")
            return {'success': False, 'error': str(e)}
    
    def extract_facebook_info(self, url):
        """Extract Facebook video info"""
        try:
            # Clean URL
            url = re.sub(r'\?.*', '', url)  # Remove query parameters
            url = re.sub(r'#.*', '', url)   # Remove fragments
            
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': True,
                'user_agent': random.choice(config.USER_AGENTS),
                'referer': 'https://www.facebook.com/',
                'cookiefile': 'cookies.txt' if os.path.exists('cookies.txt') else None,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                if info:
                    return {
                        'success': True,
                        'title': info.get('title', 'Facebook Video'),
                        'uploader': info.get('uploader', 'Facebook User'),
                        'duration': info.get('duration', 0),
                        'url': info.get('webpage_url', url)
                    }
            
            # Try with mobile URL
            mobile_url = url.replace('www.facebook.com', 'm.facebook.com')
            ydl_opts['user_agent'] = config.USER_AGENTS[2]  # Mobile user agent
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(mobile_url, download=False)
                if info:
                    return {
                        'success': True,
                        'title': info.get('title', 'Facebook Video'),
                        'uploader': info.get('uploader', 'Facebook User'),
                        'duration': info.get('duration', 0),
                        'url': info.get('webpage_url', mobile_url)
                    }
            
            return {'success': False, 'error': 'Cannot extract Facebook info'}
            
        except Exception as e:
            logger.error(f"Facebook info extraction error: {e}")
            return {'success': False, 'error': str(e)}
    
    def download_with_ytdlp(self, url, platform, temp_dir):
        """Download using yt-dlp with optimized settings"""
        output_template = os.path.join(temp_dir, f'video.%(ext)s')
        
        ydl_opts = {
            'outtmpl': output_template,
            'quiet': False,
            'no_warnings': False,
            'extractaudio': False,
            'keepvideo': True,
            'writethumbnail': True,
            'merge_output_format': 'mp4',
            'http_headers': {
                'User-Agent': random.choice(config.USER_AGENTS),
                'Accept': '*/*',
                'Accept-Language': 'en-US,en;q=0.9',
                'Referer': 'https://www.tiktok.com/' if platform == 'tiktok' else 'https://www.facebook.com/',
                'Origin': 'https://www.tiktok.com' if platform == 'tiktok' else 'https://www.facebook.com',
                'Sec-Fetch-Dest': 'video',
                'Sec-Fetch-Mode': 'cors',
                'Sec-Fetch-Site': 'same-site',
            },
            'cookiefile': 'cookies.txt' if os.path.exists('cookies.txt') else None,
            'ignoreerrors': True,
            'retries': 10,
            'fragment_retries': 10,
            'skip_unavailable_fragments': True,
            'no_check_certificate': True,
            'geo_bypass': True,
            'geo_bypass_country': 'US',
            'extractor_args': {
                'tiktok': {
                    'app_version': '29.0.0',
                    'manifest_app_version': '29.0.0',
                },
                'facebook': {
                    'credentials': None,
                }
            },
            'postprocessors': [
                {
                    'key': 'FFmpegVideoConvertor',
                    'preferedformat': 'mp4',
                }
            ],
        }
        
        # Platform specific format
        if platform == 'tiktok':
            ydl_opts['format'] = 'best[height<=720]'
            # Try multiple format selections
            format_preferences = [
                'best[height<=720]',
                'best',
                'worst',
                'bestvideo[height<=720]+bestaudio',
                'bestvideo+bestaudio',
            ]
        else:
            ydl_opts['format'] = 'best[filesize<100M]'
            format_preferences = [
                'best[filesize<100M]',
                'best',
                'best[height<=720]',
                'bestvideo[height<=720]+bestaudio/best[height<=720]',
            ]
        
        # Try different format preferences
        for fmt in format_preferences:
            ydl_opts['format'] = fmt
            try:
                logger.info(f"Trying format: {fmt} for {platform}")
                
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=True)
                    
                    # Find downloaded file
                    for file in os.listdir(temp_dir):
                        if file.endswith(('.mp4', '.webm', '.mkv', '.avi', '.mov')):
                            file_path = os.path.join(temp_dir, file)
                            
                            # Get video info if not in info
                            if not info:
                                info = {'title': 'Video', 'uploader': 'Unknown', 'duration': 0}
                            
                            return {
                                'success': True,
                                'file_path': file_path,
                                'title': info.get('title', 'Video'),
                                'uploader': info.get('uploader', 'Unknown'),
                                'duration': info.get('duration', 0),
                                'url': url,
                                'platform': platform
                            }
                
            except Exception as e:
                logger.warning(f"Format {fmt} failed: {e}")
                continue
        
        return {'success': False, 'error': 'All download methods failed'}
    
    def download_video(self, url, platform):
        """Main download method with multiple fallbacks"""
        temp_dir = tempfile.mkdtemp(dir=config.TEMP_PATH)
        logger.info(f"Downloading {platform} video to {temp_dir}")
        
        try:
            # Method 1: yt-dlp with optimized settings
            result = self.download_with_ytdlp(url, platform, temp_dir)
            if result['success']:
                return result
            
            # Method 2: Try alternative URL formats
            if platform == 'tiktok':
                # Try to fix TikTok URL
                fixed_urls = self.get_tiktok_alternatives(url)
                for alt_url in fixed_urls:
                    logger.info(f"Trying alternative URL: {alt_url}")
                    result = self.download_with_ytdlp(alt_url, platform, temp_dir)
                    if result['success']:
                        return result
            
            # Method 3: Try direct download for TikTok
            if platform == 'tiktok':
                direct_result = self.try_direct_tiktok_download(url, temp_dir)
                if direct_result['success']:
                    return direct_result
            
            # Cleanup and return error
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {'success': False, 'error': 'All download attempts failed'}
            
        except Exception as e:
            logger.error(f"Download error: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {'success': False, 'error': str(e)}
    
    def get_tiktok_alternatives(self, url):
        """Generate alternative TikTok URLs"""
        alternatives = []
        
        # Extract video ID
        video_id_match = re.search(r'/video/(\d+)', url)
        if video_id_match:
            video_id = video_id_match.group(1)
            alternatives = [
                f"https://www.tiktok.com/@tiktok/video/{video_id}",
                f"https://www.tiktok.com/video/{video_id}",
                f"https://vt.tiktok.com/{video_id}",
                f"https://vm.tiktok.com/{video_id}",
            ]
        
        return alternatives
    
    def try_direct_tiktok_download(self, url, temp_dir):
        """Try direct TikTok download method"""
        try:
            # Use requests to get video URL
            headers = {
                'User-Agent': config.USER_AGENTS[2],  # Mobile user agent
                'Accept': '*/*',
                'Accept-Language': 'en-US,en;q=0.9',
                'Referer': 'https://www.tiktok.com/',
                'Origin': 'https://www.tiktok.com',
            }
            
            response = self.session.get(url, headers=headers, timeout=10)
            
            # Look for video URL in response
            video_url_match = re.search(r'"playAddr":"([^"]+)"', response.text)
            if video_url_match:
                video_url = video_url_match.group(1).replace('\\u0026', '&')
                
                # Download video
                video_response = self.session.get(video_url, headers=headers, timeout=30, stream=True)
                if video_response.status_code == 200:
                    video_path = os.path.join(temp_dir, 'video.mp4')
                    with open(video_path, 'wb') as f:
                        for chunk in video_response.iter_content(chunk_size=8192):
                            if chunk:
                                f.write(chunk)
                    
                    # Extract title
                    title_match = re.search(r'"desc":"([^"]+)"', response.text)
                    title = title_match.group(1) if title_match else 'TikTok Video'
                    
                    return {
                        'success': True,
                        'file_path': video_path,
                        'title': title,
                        'uploader': 'TikTok User',
                        'duration': 0,
                        'url': url,
                        'platform': 'tiktok'
                    }
            
            return {'success': False, 'error': 'Direct download failed'}
            
        except Exception as e:
            logger.error(f"Direct TikTok download error: {e}")
            return {'success': False, 'error': str(e)}

# Global downloader instance
downloader = VideoDownloader()

def extract_platform(url):
    """Extract platform from URL"""
    url_lower = url.lower()
    
    if 'tiktok.com' in url_lower or 'vm.tiktok' in url_lower or 'vt.tiktok' in url_lower:
        return 'tiktok'
    elif 'facebook.com' in url_lower or 'fb.watch' in url_lower:
        return 'facebook'
    elif 'instagram.com' in url_lower:
        return 'instagram'
    else:
        return 'unknown'

def clean_url(url):
    """Clean and normalize URL"""
    # Decode URL encoding
    url = unquote(url)
    
    # Remove tracking parameters
    url = re.sub(r'[?&](share_|rdid|set|t|utm_|fbclid|gclid)=[^&]+', '', url)
    url = re.sub(r'[?&]$', '', url)  # Remove trailing ? or &
    
    # Fix TikTok URLs
    if 'tiktok.com' in url.lower():
        # Ensure proper format
        url = re.sub(r'\?.*', '', url)
        if '/video/' in url:
            # Extract video ID
            match = re.search(r'/video/(\d+)', url)
            if match:
                return f"https://www.tiktok.com/@tiktok/video/{match.group(1)}"
    
    return url

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
        await message.reply_text("Please send a video URL (TikTok, Facebook, Instagram)")
        return
    
    url = urls[0]
    
    # Determine platform
    platform = extract_platform(url)
    if platform == 'unknown':
        await message.reply_text("❌ Unsupported platform. Send TikTok, Facebook, or Instagram links only.")
        return
    
    # Clean URL
    url = clean_url(url)
    
    # Send status
    status_msg = await message.reply_text(f"🔍 Processing {platform} link...")
    
    try:
        await status_msg.edit_text(f"📥 Downloading from {platform}...")
        
        # Download video
        result = downloader.download_video(url, platform)
        
        if not result['success']:
            error_msg = result['error']
            
            # Provide helpful suggestions
            suggestions = ""
            if platform == 'tiktok':
                suggestions = "\n\n💡 Tips for TikTok:\n• Get fresh link from TikTok app (Share → Copy Link)\n• Some videos are private/region-locked"
            elif platform == 'facebook':
                suggestions = "\n\n💡 Tips for Facebook:\n• Make sure video is public\n• Try mobile link (m.facebook.com)"
            
            await status_msg.edit_text(f"❌ Download failed: {error_msg}{suggestions}")
            return
        
        # Check file size
        try:
            file_size = os.path.getsize(result['file_path'])
            if file_size > config.MAX_FILE_SIZE:
                await status_msg.edit_text(
                    f"❌ File too large ({file_size/(1024*1024):.1f}MB). "
                    f"Telegram limit is 2GB"
                )
                shutil.rmtree(os.path.dirname(result['file_path']), ignore_errors=True)
                return
        except:
            pass
        
        # Create caption
        caption = f"📹 *{result['title'][:100]}*\n"
        caption += f"👤 *From:* {result['uploader']}\n"
        
        if result['duration'] > 0:
            mins = result['duration'] // 60
            secs = result['duration'] % 60
            caption += f"⏱ *Duration:* {mins}:{secs:02d}\n"
        
        caption += f"🔗 *Platform:* {platform.title()}\n"
        
        # Send video
        await status_msg.edit_text("📤 Uploading to Telegram...")
        
        with open(result['file_path'], 'rb') as f:
            await message.reply_video(
                video=InputFile(f, filename=f"{platform}_video.mp4"),
                caption=caption,
                parse_mode=ParseMode.MARKDOWN,
                duration=result['duration'],
                supports_streaming=True,
                read_timeout=180,
                write_timeout=180,
                connect_timeout=180
            )
        
        await status_msg.edit_text("✅ Video sent successfully!")
        
        # Cleanup
        try:
            temp_dir = os.path.dirname(result['file_path'])
            shutil.rmtree(temp_dir, ignore_errors=True)
        except:
            pass
        
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        try:
            await status_msg.edit_text(f"❌ Error: {str(e)[:100]}")
        except:
            pass

def main():
    if config.BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("ERROR: Bot token not configured!")
        print("="*60)
        print("1. Get token from @BotFather")
        print("2. Edit config.py")
        print("3. Replace YOUR_BOT_TOKEN_HERE")
        print("="*60)
        sys.exit(1)
    
    print("🤖 Enhanced Video Downloader Bot")
    print("✅ Multiple download methods")
    print("✅ Better TikTok/Facebook support")
    print("✅ Automatic retry and fallback")
    print("")
    
    application = Application.builder() \
        .token(config.BOT_TOKEN) \
        .read_timeout(180) \
        .write_timeout(180) \
        .connect_timeout(180) \
        .build()
    
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("about", about_command))
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND,
        handle_message
    ))
    
    print("🚀 Starting enhanced bot...")
    print("📝 Logs: bot.log")
    print("🛑 Stop with Ctrl+C")
    print("")
    
    try:
        application.run_polling(
            poll_interval=1.0,
            timeout=60,
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

echo "🤖 Enhanced Video Downloader Bot"
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
echo "🚀 Starting enhanced bot..."
echo ""
echo "Features:"
echo "• Multiple download methods"
echo "• Automatic retry"
echo "• Better TikTok/Facebook support"
echo ""
echo "📝 Logs: tail -f bot.log"
echo "🛑 Stop: Ctrl+C"
echo ""

python3 bot.py
EOF

chmod +x start.sh

cat > stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null
sleep 3
echo "✅ Bot stopped"
EOF

chmod +x stop.sh

cat > setup.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Bot Setup"
echo "============"

if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "Enter your bot token from @BotFather:"
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

# Make files executable
chmod +x bot.py

success "✅ Enhanced bot installed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Configure bot token:"
echo "   cd $BOT_DIR && ./setup.sh"
echo ""
echo "2. Start the bot:"
echo "   ./start.sh"
echo ""
echo "3. For best results:"
echo "   - Use fresh links from mobile apps"
echo "   - TikTok: Share → Copy Link"
echo "   - Some videos are private"
echo ""
success "🎉 Bot ready with enhanced download methods!"
