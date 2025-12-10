#!/bin/bash

# =========================================================
#         Integrated Telegram Downloader Bot Setup
# =========================================================
# This single script handles the installation, configuration, and execution
# of a Telegram downloader bot using yt-dlp and Python.

set -e  # Stop on any error

BOT_FILE="bot.py"
ENV_FILE=".env"
CONFIG_FILE="bot_config.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🛠️ Starting Telegram Downloader Bot Installation...${NC}"

# 1. Update packages and install prerequisites
echo -e "${YELLOW}📦 Updating system packages and installing dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip git curl libmagic1 ffmpeg python3-venv wget

# 2. Install yt-dlp with Facebook cookies support
echo -e "${YELLOW}⬇️ Installing yt-dlp with Facebook support...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp

# Install cookies browser extensions for yt-dlp
echo -e "${YELLOW}🍪 Installing Facebook cookies extractor...${NC}"
python3 -m venv venv 2>/dev/null || true
source venv/bin/activate
pip install yt-dlp --upgrade
pip install browser-cookie3

# Test yt-dlp
yt-dlp --version
echo -e "${GREEN}✅ yt-dlp installed successfully${NC}"

# 3. Create directory structure
echo -e "${YELLOW}📁 Creating directory structure...${NC}"
mkdir -p downloads
mkdir -p logs
mkdir -p cookies

# 4. Recreate virtual environment and install Python libraries
echo -e "${YELLOW}🐍 Setting up Python virtual environment...${NC}"
python3 -m venv venv --clear
source venv/bin/activate

# Upgrade pip first
pip install --upgrade pip

# Install required packages
pip install python-telegram-bot python-dotenv uuid browser-cookie3 requests

# 5. Configure Bot Token
echo -e "${GREEN}🤖 Telegram Bot Configuration${NC}"
echo -e "${YELLOW}Please enter your Telegram Bot Token (from @BotFather):${NC}"
read -r BOT_TOKEN

# Validate token format
if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Invalid bot token format! Example: 1234567890:ABCdefGHIJKLMnopQRSTuvwXYZ${NC}"
    exit 1
fi

echo "BOT_TOKEN=$BOT_TOKEN" > $ENV_FILE
echo -e "${GREEN}✅ Token saved to $ENV_FILE${NC}"

# 6. Create configuration file with Facebook-specific settings
cat << 'EOF' > $CONFIG_FILE
# =========================================================
#                     Configuration
# =========================================================
import os
import re
from dotenv import load_dotenv

load_dotenv()

# Bot Configuration
BOT_TOKEN = os.getenv("BOT_TOKEN")

# Download Settings
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
DOWNLOAD_TIMEOUT = 300  # 5 minutes
MAX_CONCURRENT_DOWNLOADS = 3

# Paths
DOWNLOAD_BASE_DIR = "./downloads"
LOG_FILE = "./logs/bot.log"
COOKIES_DIR = "./cookies"

# Supported Platforms with detailed patterns
SUPPORTED_PLATFORMS = {
    "facebook": [
        # Video patterns
        r'facebook\.com/(?:watch/\?v=|video\.php\?v=|.*?/videos/|reel/|share/v/)',
        r'fb\.watch/',
        # Post patterns
        r'facebook\.com/(?:photo\.php\?fbid=|share/p|permalink\.php\?story_fbid=)',
        # Share patterns (new format)
        r'facebook\.com/share/[^/]+/?'
    ],
    "tiktok": [
        r'tiktok\.com/',
        r'vm\.tiktok\.com/',
        r'vt\.tiktok\.com/'
    ],
    "youtube": [
        r'youtube\.com/',
        r'youtu\.be/'
    ],
    "instagram": [
        r'instagram\.com/',
        r'instagr\.am/'
    ],
    "twitter": [
        r'twitter\.com/',
        r'x\.com/'
    ],
    "all_platforms": [
        "terabox.com",
        "streamable.com",
        "pinterest.com",
        "pin.it",
        "snapchat.com",
        "reddit.com",
        "likee.video",
        "like.com",
        "loom.com",
        "dailymotion.com",
        "bilibili.com",
        "twitch.tv",
        "vimeo.com"
    ]
}

# Facebook URL patterns for validation
FACEBOOK_PATTERNS = {
    "video": [
        r'facebook\.com/watch/\?v=(\d+)',
        r'facebook\.com/video\.php\?v=(\d+)',
        r'facebook\.com/([^/]+)/videos/(\d+)',
        r'fb\.watch/([a-zA-Z0-9_-]+)',
        r'facebook\.com/reel/(\d+)',
        r'facebook\.com/share/v/\?id=(\d+)'
    ],
    "post": [
        r'facebook\.com/photo\.php\?fbid=(\d+)',
        r'facebook\.com/share/p/[^/]+/(\d+)',
        r'facebook\.com/permalink\.php\?story_fbid=(\d+)'
    ],
    "share": [
        r'facebook\.com/share/([^/]+)/?'
    ]
}

# yt-dlp Configuration
YT_DLP_OPTIONS = {
    'common': [
        '--no-warnings',
        '--no-progress',
        '--restrict-filenames',
        '--socket-timeout', '30',
        '--retries', '3',
        '--fragment-retries', '3',
        '--concurrent-fragments', '4',
    ],
    'facebook': [
        '--format', 'best[height<=720][filesize<=50M]',
        '--max-filesize', '50M',
        '--cookies-from-browser', 'chrome',
        '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    ],
    'tiktok': [
        '--format', 'best[filesize<=50M]',
        '--max-filesize', '50M'
    ],
    'youtube': [
        '--format', 'best[filesize<=50M]',
        '--max-filesize', '50M'
    ],
    'default': [
        '--format', 'best[filesize<=50M]',
        '--max-filesize', '50M'
    ]
}

def clean_facebook_url(url: str) -> str:
    """Clean Facebook URL from tracking parameters"""
    # Remove common tracking parameters
    patterns_to_remove = [
        r'&_fb_noscript=1',
        r'&__tn__=[^&]+',
        r'&__cft__\[0\]=[^&]+',
        r'&__xts__\[0\]=[^&]+',
        r'&rdid=[^&]+',
        r'&e=[^&]+'
    ]
    
    cleaned = url
    for pattern in patterns_to_remove:
        cleaned = re.sub(pattern, '', cleaned)
    
    # Decode URL-encoded characters
    import urllib.parse
    cleaned = urllib.parse.unquote(cleaned)
    
    # Remove double question marks
    cleaned = cleaned.replace('??', '?').replace('?&', '?')
    
    # Remove trailing & or ?
    cleaned = cleaned.rstrip('&?')
    
    return cleaned
EOF

# 7. Create the main bot file with enhanced Facebook support
echo -e "${YELLOW}📝 Creating bot.py with improved Facebook handling...${NC}"

cat << 'EOF' > $BOT_FILE
#!/usr/bin/env python3
# =========================================================
#                 Telegram Downloader Bot
# =========================================================
import os
import sys
import re
import logging
import subprocess
import asyncio
import json
import urllib.parse
from pathlib import Path
from uuid import uuid4
from datetime import datetime
from typing import Optional, Tuple, Dict

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.error import TelegramError
import bot_config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(bot_config.LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class URLProcessor:
    """Process and validate URLs"""
    
    @staticmethod
    def is_valid_url(url: str) -> bool:
        """Check if URL has valid format"""
        try:
            result = urllib.parse.urlparse(url)
            return all([result.scheme in ['http', 'https'], result.netloc])
        except:
            return False
    
    @staticmethod
    def get_platform(url: str) -> Optional[str]:
        """Determine platform from URL"""
        url_lower = url.lower()
        
        # Check Facebook patterns
        for pattern in bot_config.SUPPORTED_PLATFORMS['facebook']:
            if re.search(pattern, url_lower):
                return 'facebook'
        
        # Check TikTok
        for pattern in bot_config.SUPPORTED_PLATFORMS['tiktok']:
            if re.search(pattern, url_lower):
                return 'tiktok'
        
        # Check YouTube
        for pattern in bot_config.SUPPORTED_PLATFORMS['youtube']:
            if re.search(pattern, url_lower):
                return 'youtube'
        
        # Check Instagram
        for pattern in bot_config.SUPPORTED_PLATFORMS['instagram']:
            if re.search(pattern, url_lower):
                return 'instagram'
        
        # Check Twitter
        for pattern in bot_config.SUPPORTED_PLATFORMS['twitter']:
            if re.search(pattern, url_lower):
                return 'twitter'
        
        # Check other platforms
        for platform in bot_config.SUPPORTED_PLATFORMS['all_platforms']:
            if platform in url_lower:
                return platform.split('.')[0]  # Return domain without .com
        
        return None
    
    @staticmethod
    def process_facebook_url(url: str) -> Dict:
        """Process Facebook URL and extract info"""
        # Clean URL first
        cleaned_url = bot_config.clean_facebook_url(url)
        
        # Check for login/redirect URLs
        if 'facebook.com/login' in cleaned_url or 'facebook.com/dialog' in cleaned_url:
            # Try to extract real URL from parameters
            parsed = urllib.parse.urlparse(cleaned_url)
            query = urllib.parse.parse_qs(parsed.query)
            
            extracted_url = None
            if 'next' in query:
                extracted_url = query['next'][0]
            elif 'share_url' in query:
                extracted_url = query['share_url'][0]
            
            if extracted_url and 'facebook.com' in extracted_url:
                cleaned_url = urllib.parse.unquote(extracted_url)
                logger.info(f"Extracted Facebook URL from login page: {cleaned_url}")
        
        # Validate Facebook URL type
        url_type = None
        video_id = None
        
        # Check for video patterns
        for pattern in bot_config.FACEBOOK_PATTERNS['video']:
            match = re.search(pattern, cleaned_url, re.IGNORECASE)
            if match:
                url_type = 'video'
                video_id = match.group(1) if match.groups() else None
                break
        
        # Check for post patterns
        if not url_type:
            for pattern in bot_config.FACEBOOK_PATTERNS['post']:
                match = re.search(pattern, cleaned_url, re.IGNORECASE)
                if match:
                    url_type = 'post'
                    video_id = match.group(1) if match.groups() else None
                    break
        
        # Check for share patterns (new format)
        if not url_type:
            for pattern in bot_config.FACEBOOK_PATTERNS['share']:
                match = re.search(pattern, cleaned_url, re.IGNORECASE)
                if match:
                    url_type = 'share'
                    break
        
        return {
            'cleaned_url': cleaned_url,
            'original_url': url,
            'type': url_type,
            'video_id': video_id,
            'is_valid': url_type is not None
        }
    
    @staticmethod
    def validate_url(url: str) -> Dict:
        """Validate URL and return platform info"""
        # Basic URL validation
        if not URLProcessor.is_valid_url(url):
            return {
                'valid': False,
                'error': "Invalid URL format. Please send a valid URL starting with http:// or https://"
            }
        
        # Get platform
        platform = URLProcessor.get_platform(url)
        if not platform:
            return {
                'valid': False,
                'error': "Platform not supported. Send /start to see supported platforms."
            }
        
        # Platform-specific processing
        if platform == 'facebook':
            facebook_info = URLProcessor.process_facebook_url(url)
            
            if not facebook_info['is_valid']:
                error_msg = (
                    "Invalid Facebook link format!\n\n"
                    "✅ *Valid Facebook links should look like:*\n"
                    "• https://www.facebook.com/watch/?v=123456789\n"
                    "• https://fb.watch/abc123def/\n"
                    "• https://www.facebook.com/username/videos/123456789\n"
                    "• https://www.facebook.com/reel/123456789\n\n"
                    "❌ *Avoid these:*\n"
                    "• Login pages (facebook.com/login)\n"
                    "• Messaging links\n"
                    "• Private/share links with tokens\n\n"
                    "Send /fbhelp for detailed instructions."
                )
                return {'valid': False, 'error': error_msg}
            
            return {
                'valid': True,
                'platform': platform,
                'url': facebook_info['cleaned_url'],
                'original_url': facebook_info['original_url'],
                'type': facebook_info['type'],
                'video_id': facebook_info['video_id']
            }
        else:
            return {
                'valid': True,
                'platform': platform,
                'url': url,
                'original_url': url,
                'type': 'video',
                'video_id': None
            }

class DownloadManager:
    def __init__(self):
        self.download_dir = Path(bot_config.DOWNLOAD_BASE_DIR)
        self.download_dir.mkdir(exist_ok=True)
    
    def get_download_path(self, chat_id: int) -> Path:
        """Get download path for specific chat"""
        chat_dir = self.download_dir / str(chat_id)
        chat_dir.mkdir(exist_ok=True)
        return chat_dir
    
    def cleanup_old_files(self, chat_dir: Path, max_age_hours: int = 24):
        """Clean up files older than specified hours"""
        try:
            now = datetime.now()
            for file_path in chat_dir.glob("*"):
                if file_path.is_file():
                    file_age = now - datetime.fromtimestamp(file_path.stat().st_mtime)
                    if file_age.total_seconds() > max_age_hours * 3600:
                        file_path.unlink()
                        logger.info(f"Cleaned up old file: {file_path}")
        except Exception as e:
            logger.warning(f"Cleanup error: {e}")

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome_msg = (
        "👋 *Welcome to Downloader Bot!*\n\n"
        "📥 *Supported Platforms:*\n"
        "• *Facebook*: Videos, Reels, Public posts\n"
        "• *TikTok*: All videos\n"
        "• *YouTube*: Videos, Shorts (50MB max)\n"
        "• *Instagram*: Posts, Reels, Stories\n"
        "• *Twitter/X*: Videos\n"
        "• *Reddit*: Videos\n"
        "• *Terabox*: Videos\n"
        "• *Streamable*: Videos\n"
        "• *Pinterest*: Images & Videos\n"
        "• *Snapchat*: Spotlight\n"
        "• *Loom*: Videos\n\n"
        "📝 *How to use:*\n"
        "Just send me a link from any supported platform!\n\n"
        "⚠️ *Important:*\n"
        "• Max file size: 50MB\n"
        "• Only public content\n"
        "• Videos must be accessible\n\n"
        "🔧 *Commands:*\n"
        "/start - Show this message\n"
        "/help - Get help\n"
        "/fbhelp - Facebook download guide\n"
        "/examples - Example links"
    )
    await update.message.reply_text(welcome_msg, parse_mode='Markdown')

async def fbhelp_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Facebook download guide"""
    guide_msg = (
        "📘 *Facebook Download Guide*\n\n"
        "1. *Get the RIGHT link:*\n"
        "   • Open Facebook in *browser* (not app)\n"
        "   • Find the video you want\n"
        "   • Click on the *timestamp* (e.g., '2 hours ago')\n"
        "   • Copy URL from address bar\n\n"
        "2. *Good link examples:*\n"
        "   ```\n"
        "   https://www.facebook.com/watch/?v=123456789\n"
        "   https://fb.watch/abc123def/\n"
        "   https://www.facebook.com/username/videos/123456789\n"
        "   https://www.facebook.com/reel/123456789\n"
        "   ```\n\n"
        "3. *Bad links (WON'T WORK):*\n"
        "   ```\n"
        "   https://www.facebook.com/login/...\n"
        "   https://www.facebook.com/share/r/...\n"
        "   https://www.facebook.com/share/video/...\n"
        "   ```\n\n"
        "4. *Quick fix for bad links:*\n"
        "   • Go to the video\n"
        "   • Click ••• (more options)\n"
        "   • Click 'Copy link'\n"
        "   • Send that link here\n\n"
        "Need more help? Send your link and I'll check it!"
    )
    await update.message.reply_text(guide_msg, parse_mode='Markdown')

async def examples_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show example links"""
    examples_msg = (
        "🔗 *Example Links for Testing:*\n\n"
        "*Facebook Video:*\n"
        "`https://www.facebook.com/facebook/videos/10153231379946729/`\n"
        "`https://fb.watch/abcExample/`\n\n"
        "*TikTok:*\n"
        "`https://www.tiktok.com/@example/video/123456789`\n"
        "`https://vm.tiktok.com/abcdef/`\n\n"
        "*YouTube:*\n"
        "`https://www.youtube.com/shorts/abc123def`\n"
        "`https://youtu.be/abc123def`\n\n"
        "*Instagram:*\n"
        "`https://www.instagram.com/reel/abc123def/`\n\n"
        "Try one of these or send your own link!"
    )
    await update.message.reply_text(examples_msg, parse_mode='Markdown')

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_msg = (
        "❓ *Help*\n\n"
        "*How to download:*\n"
        "1. Copy link from supported platform\n"
        "2. Send link to this bot\n"
        "3. Wait for download\n"
        "4. Receive file\n\n"
        "*Common issues:*\n"
        "• *Facebook login link*: Send /fbhelp\n"
        "• *File too large*: Max 50MB\n"
        "• *Private video*: Must be public\n"
        "• *Unsupported link*: Check /start\n\n"
        "*Commands:*\n"
        "/start - Welcome message\n"
        "/fbhelp - Facebook guide\n"
        "/examples - Example links\n"
        "/help - This message"
    )
    await update.message.reply_text(help_msg, parse_mode='Markdown')

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming messages"""
    user = update.effective_user
    chat_id = update.effective_chat.id
    text = update.message.text.strip()
    
    logger.info(f"Message from {user.id} ({user.username}): {text[:100]}...")
    
    # Validate URL
    validation = URLProcessor.validate_url(text)
    if not validation["valid"]:
        await update.message.reply_text(validation["error"], parse_mode='Markdown')
        return
    
    platform = validation["platform"]
    url = validation["url"]
    
    # Special handling for Facebook share links
    if platform == 'facebook' and validation.get('type') == 'share':
        await update.message.reply_text(
            "⚠️ *Facebook Share Link Detected*\n\n"
            "This type of link (facebook.com/share/r/...) usually doesn't work for downloading.\n\n"
            "Please get the *direct video link* instead:\n"
            "1. Open the video in browser\n"
            "2. Click on the timestamp\n"
            "3. Copy that URL\n"
            "4. Send it here\n\n"
            "Send /fbhelp for detailed instructions.",
            parse_mode='Markdown'
        )
        return
    
    # Initialize download manager
    dm = DownloadManager()
    chat_dir = dm.get_download_path(chat_id)
    dm.cleanup_old_files(chat_dir)
    
    # Send initial message
    status_msg = await update.message.reply_text(
        f"⏳ *Processing {platform.upper()} link...*\n"
        f"URL: `{url[:100]}{'...' if len(url) > 100 else ''}`\n"
        f"Platform: {platform}\n"
        f"Please wait...",
        parse_mode='Markdown'
    )
    
    downloaded_file = None
    
    try:
        # Update status
        await status_msg.edit_text(f"⬇️ *Downloading from {platform}...* This may take a moment.", parse_mode='Markdown')
        
        # Download file
        downloaded_file = await download_with_ytdlp(url, platform, chat_dir)
        
        if not downloaded_file or not downloaded_file.exists():
            raise FileNotFoundError("File not found after download")
        
        file_size = downloaded_file.stat().st_size
        if file_size > bot_config.MAX_FILE_SIZE:
            raise Exception(f"File too large ({file_size/1024/1024:.1f}MB > 50MB)")
        
        # Update status
        await status_msg.edit_text("📤 *Uploading to Telegram...*", parse_mode='Markdown')
        
        # Determine file type
        mime_type = await get_mime_type(downloaded_file)
        
        # Send file
        await send_file_to_telegram(update, context, downloaded_file, url, mime_type)
        
        # Final success message
        await status_msg.edit_text(
            f"✅ *Download complete!*\n"
            f"Platform: {platform}\n"
            f"Size: {file_size/1024/1024:.1f}MB",
            parse_mode='Markdown'
        )
        
        logger.info(f"Successfully sent {platform} file to {user.id}")
        
    except FileNotFoundError as e:
        error_msg = f"❌ *File Not Found*\nThe file was downloaded but could not be located.\n\nError: `{str(e)}`"
        await status_msg.edit_text(error_msg, parse_mode='Markdown')
        logger.error(f"File not found for {url}: {e}")
        
    except Exception as e:
        error_msg = f"❌ *Download Failed*\n\nPlatform: {platform}\nError: `{str(e)}`\n\n"
        
        # Platform-specific advice
        if platform == 'facebook':
            error_msg += "*Facebook tips:*\n"
            error_msg += "• Video must be public\n"
            error_msg += "• Try getting direct link\n"
            error_msg += "• Send /fbhelp for guide\n"
        elif platform == 'tiktok':
            error_msg += "*TikTok tips:*\n"
            error_msg += "• Video might be private\n"
            error_msg += "• Try different link\n"
        else:
            error_msg += "Please try again or use a different link."
        
        await status_msg.edit_text(error_msg, parse_mode='Markdown')
        logger.error(f"Download failed for {url}: {e}")
        
    finally:
        # Cleanup
        if downloaded_file and downloaded_file.exists():
            try:
                downloaded_file.unlink()
                logger.info(f"Cleaned up: {downloaded_file}")
            except Exception as e:
                logger.warning(f"Failed to cleanup {downloaded_file}: {e}")

async def download_with_ytdlp(url: str, platform: str, output_path: Path) -> Path:
    """Download using yt-dlp with platform-specific options"""
    unique_id = uuid4().hex
    filename_template = f"{unique_id}.%(ext)s"
    output_template = str(output_path / filename_template)
    
    # Get platform-specific options
    yt_dlp_options = bot_config.YT_DLP_OPTIONS['common'].copy()
    
    if platform in bot_config.YT_DLP_OPTIONS:
        yt_dlp_options.extend(bot_config.YT_DLP_OPTIONS[platform])
    else:
        yt_dlp_options.extend(bot_config.YT_DLP_OPTIONS['default'])
    
    # Build command
    cmd = ["yt-dlp"] + yt_dlp_options + ["--output", output_template, url]
    
    logger.info(f"Executing yt-dlp for {platform}: {' '.join(cmd[:10])}...")
    
    try:
        # Run yt-dlp
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=bot_config.DOWNLOAD_TIMEOUT)
        
        if process.returncode != 0:
            error_text = stderr.decode('utf-8', errors='ignore').strip()
            error_lines = [line.strip() for line in error_text.split('\n') if line.strip()]
            
            # Parse common errors
            if "Unsupported URL" in error_text:
                if platform == 'facebook':
                    raise Exception("Facebook link not supported. Video might be private or requires login.")
                else:
                    raise Exception("Link not supported by yt-dlp.")
            elif "Private video" in error_text or "Video unavailable" in error_text:
                raise Exception("Video is private or unavailable.")
            elif "Sign in to confirm" in error_text:
                raise Exception("Facebook requires login. Try a different public video.")
            elif error_lines:
                last_error = error_lines[-1]
                raise Exception(f"Download error: {last_error}")
            else:
                raise Exception("Unknown download error.")
        
        # Find downloaded file
        downloaded_file = None
        
        # Method 1: Look in yt-dlp output
        output_text = stdout.decode('utf-8', errors='ignore')
        for line in output_text.split('\n'):
            line = line.strip()
            if line and os.path.exists(line) and output_path in Path(line).parents:
                downloaded_file = Path(line)
                break
        
        # Method 2: Search for file with unique ID
        if not downloaded_file:
            for file_path in output_path.glob(f"{unique_id}.*"):
                if file_path.is_file() and file_path.stat().st_size > 0:
                    downloaded_file = file_path
                    break
        
        # Method 3: Find newest file in directory
        if not downloaded_file:
            files = list(output_path.glob("*"))
            if files:
                files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
                newest_file = files[0]
                # Check if file was created recently
                file_age = datetime.now().timestamp() - newest_file.stat().st_mtime
                if file_age < 300:  # Created in last 5 minutes
                    downloaded_file = newest_file
        
        if not downloaded_file or not downloaded_file.exists():
            raise FileNotFoundError(f"Downloaded file not found. Searched for pattern: {unique_id}.*")
        
        return downloaded_file
        
    except asyncio.TimeoutError:
        raise Exception(f"Download timed out after {bot_config.DOWNLOAD_TIMEOUT//60} minutes")
    except Exception as e:
        raise e

async def get_mime_type(file_path: Path) -> str:
    """Get MIME type of file"""
    try:
        result = subprocess.run(
            ['file', '-b', '--mime-type', str(file_path)],
            capture_output=True, text=True
        )
        return result.stdout.strip()
    except:
        # Fallback based on extension
        ext = file_path.suffix.lower()
        if ext in ['.mp4', '.avi', '.mov', '.mkv', '.webm']:
            return 'video/mp4'
        elif ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
            return 'image/jpeg'
        else:
            return 'application/octet-stream'

async def send_file_to_telegram(update: Update, context: ContextTypes.DEFAULT_TYPE, 
                               file_path: Path, url: str, mime_type: str):
    """Send file to Telegram"""
    chat_id = update.effective_chat.id
    
    with open(file_path, 'rb') as f:
        if mime_type.startswith('video'):
            await context.bot.send_video(
                chat_id=chat_id,
                video=f,
                caption=f"✅ Downloaded from: {url}",
                supports_streaming=True,
                read_timeout=60,
                write_timeout=60,
                connect_timeout=60
            )
        elif mime_type.startswith('image'):
            await context.bot.send_photo(
                chat_id=chat_id,
                photo=f,
                caption=f"✅ Downloaded from: {url}",
                read_timeout=60
            )
        else:
            await context.bot.send_document(
                chat_id=chat_id,
                document=f,
                caption=f"✅ Downloaded from: {url}",
                read_timeout=60
            )

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Update {update} caused error: {context.error}")
    
    if update and update.effective_chat:
        try:
            await update.effective_chat.send_message(
                "⚠️ An error occurred. Please try again later."
            )
        except:
            pass

def main():
    """Main function to run the bot"""
    if not bot_config.BOT_TOKEN:
        logger.error("❌ BOT_TOKEN not found in .env file!")
        sys.exit(1)
    
    # Create application
    application = Application.builder() \
        .token(bot_config.BOT_TOKEN) \
        .read_timeout(30) \
        .write_timeout(30) \
        .connect_timeout(30) \
        .build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("fbhelp", fbhelp_command))
    application.add_handler(CommandHandler("examples", examples_command))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    # Add error handler
    application.add_error_handler(error_handler)
    
    # Start bot
    logger.info("🤖 Bot is starting...")
    print("=" * 60)
    print("✅ Bot is running! Press Ctrl+C to stop.")
    print("=" * 60)
    
    application.run_polling(
        allowed_updates=Update.ALL_TYPES,
        drop_pending_updates=True
    )

if __name__ == "__main__":
    main()
EOF

# Make bot.py executable
chmod +x $BOT_FILE

# 8. Create startup script
cat << 'EOF' > start_bot.sh
#!/bin/bash
# Start Telegram Downloader Bot

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting Telegram Downloader Bot...${NC}"

# Check if bot is already running
if pgrep -f "python3.*bot.py" > /dev/null; then
    echo -e "${YELLOW}⚠️ Bot is already running!${NC}"
    echo -e "To restart: ${YELLOW}pkill -f bot.py && ./start_bot.sh${NC}"
    exit 1
fi

# Check .env
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Create .env with: BOT_TOKEN=your_token_here"
    exit 1
fi

# Create directories
mkdir -p downloads logs cookies

# Activate venv
source venv/bin/activate

# Check dependencies
echo -e "${YELLOW}🔧 Checking dependencies...${NC}"
if ! python3 -c "import telegram, yt_dlp, browser_cookie3" &> /dev/null; then
    echo -e "${YELLOW}Installing missing packages...${NC}"
    pip install python-telegram-bot yt-dlp python-dotenv browser-cookie3 requests --upgrade
fi

# Update yt-dlp
echo -e "${YELLOW}⬆️ Updating yt-dlp...${NC}"
yt-dlp -U

# Start bot
echo -e "${GREEN}🤖 Starting bot...${NC}"
echo -e "${YELLOW}📝 Logs: tail -f logs/bot.log${NC}"
echo -e "${YELLOW}🛑 Press Ctrl+C to stop${NC}"

# Run bot
exec python3 bot.py
EOF

chmod +x start_bot.sh

# 9. Create requirements file
cat << 'EOF' > requirements.txt
python-telegram-bot>=20.7
yt-dlp>=2024.4.9
python-dotenv>=1.0.0
browser-cookie3>=0.19.1
requests>=2.31.0
EOF

# 10. Create management scripts
cat << 'EOF' > stop_bot.sh
#!/bin/bash
# Stop Telegram Downloader Bot

echo "🛑 Stopping bot..."

# Kill bot process
pkill -f "python3.*bot.py" 2>/dev/null && echo "✅ Bot stopped" || echo "ℹ️ Bot was not running"

# Kill yt-dlp processes if any
pkill -f "yt-dlp" 2>/dev/null && echo "✅ Cleaned up yt-dlp processes"

sleep 2
EOF

cat << 'EOF' > restart_bot.sh
#!/bin/bash
# Restart Telegram Downloader Bot

echo "🔄 Restarting bot..."
./stop_bot.sh
sleep 3
./start_bot.sh
EOF

cat << 'EOF' > view_logs.sh
#!/bin/bash
# View bot logs

LOG_FILE="logs/bot.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "No log file found. Starting bot first..."
    ./start_bot.sh
else
    echo "📋 Showing logs. Press Ctrl+C to exit."
    echo "=" * 60
    tail -100f "$LOG_FILE"
fi
EOF

cat << 'EOF' > status_bot.sh
#!/bin/bash
# Check bot status

echo "🤖 Bot Status Check"
echo "=================="

# Check if bot is running
if pgrep -f "python3.*bot.py" > /dev/null; then
    echo "✅ Bot is RUNNING"
    echo "PID: $(pgrep -f "python3.*bot.py")"
else
    echo "❌ Bot is STOPPED"
fi

# Check yt-dlp processes
yt_dlp_count=$(pgrep -f "yt-dlp" | wc -l)
if [ $yt_dlp_count -gt 0 ]; then
    echo "📥 Active downloads: $yt_dlp_count"
fi

# Check log file
if [ -f "logs/bot.log" ]; then
    echo "📊 Last log entry:"
    tail -1 logs/bot.log 2>/dev/null || echo "No recent logs"
fi

echo "=================="
EOF

chmod +x stop_bot.sh restart_bot.sh view_logs.sh status_bot.sh

# 11. Create Facebook link tester
cat << 'EOF' > test_facebook_link.py
#!/usr/bin/env python3
"""
Facebook Link Tester
Test if a Facebook link is valid for downloading
"""
import re
import sys
import urllib.parse

def test_facebook_link(url):
    """Test Facebook link and provide feedback"""
    print(f"\n🔍 Testing Facebook link: {url[:100]}...")
    
    # Common patterns that WON'T work
    bad_patterns = [
        (r'facebook\.com/login', "❌ LOGIN PAGE - Won't work"),
        (r'facebook\.com/share/r/', "❌ SHARE REDIRECT - Get direct link"),
        (r'facebook\.com/share/video/', "❌ VIDEO SHARE - Get direct link"),
        (r'facebook\.com/dialog/', "❌ DIALOG PAGE - Won't work"),
        (r'_fb_noscript=1', "❌ NOSCRIPT - Remove this parameter"),
        (r'messenger\.com', "❌ MESSENGER - Use Facebook.com link"),
    ]
    
    for pattern, message in bad_patterns:
        if re.search(pattern, url, re.IGNORECASE):
            print(message)
            return False
    
    # Good patterns that SHOULD work
    good_patterns = [
        (r'facebook\.com/watch/\?v=\d+', "✅ DIRECT VIDEO LINK - Should work"),
        (r'fb\.watch/[a-zA-Z0-9_-]+', "✅ FB.WATCH LINK - Should work"),
        (r'facebook\.com/[^/]+/videos/\d+', "✅ PROFILE VIDEO - Should work"),
        (r'facebook\.com/reel/\d+', "✅ REEL - Should work"),
        (r'facebook\.com/video\.php\?v=\d+', "✅ OLD FORMAT - Should work"),
    ]
    
    for pattern, message in good_patterns:
        if re.search(pattern, url, re.IGNORECASE):
            print(message)
            return True
    
    print("⚠️ UNKNOWN FORMAT - Might not work")
    print("\n💡 Tips:")
    print("1. Get direct link by clicking on video timestamp")
    print("2. Avoid links with 'login', 'share/r', or 'dialog'")
    print("3. Use browser (not app) to copy link")
    return False

def clean_url(url):
    """Try to clean Facebook URL"""
    # Remove tracking parameters
    params_to_remove = ['_fb_noscript', '__tn__', '__cft__', '__xts__', 'rdid', 'e']
    
    parsed = urllib.parse.urlparse(url)
    query_dict = urllib.parse.parse_qs(parsed.query)
    
    # Remove unwanted parameters
    for param in params_to_remove:
        query_dict.pop(param, None)
    
    # Rebuild query
    new_query = '&'.join([f"{k}={v[0]}" for k, v in query_dict.items()])
    
    # Rebuild URL
    cleaned = parsed._replace(query=new_query if new_query else '').geturl()
    
    # Decode URL
    cleaned = urllib.parse.unquote(cleaned)
    
    return cleaned

if __name__ == "__main__":
    print("=" * 60)
    print("Facebook Link Tester")
    print("=" * 60)
    
    if len(sys.argv) > 1:
        url = sys.argv[1]
        test_facebook_link(url)
        
        # Try to clean it
        cleaned = clean_url(url)
        if cleaned != url:
            print(f"\n🔄 Cleaned URL: {cleaned[:100]}...")
            print("Try this cleaned version:")
            test_facebook_link(cleaned)
    else:
        print("\nUsage: python3 test_facebook_link.py <facebook_url>")
        print("\nExample bad links that WON'T work:")
        print("https://www.facebook.com/share/r/1GffigLR68/")
        print("https://www.facebook.com/login/...")
        print("\nExample good links that SHOULD work:")
        print("https://www.facebook.com/watch/?v=123456789")
        print("https://fb.watch/abc123def/")
        print("https://www.facebook.com/username/videos/123456789")
EOF

chmod +x test_facebook_link.py

# 12. Final instructions
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "\n📁 ${YELLOW}Project Structure:${NC}"
echo -e "  ├── 📄 bot.py                 # Main bot file"
echo -e "  ├── 📄 .env                   # Bot token"
echo -e "  ├── 📄 bot_config.py          # Configuration"
echo -e "  ├── 📄 test_facebook_link.py  # Link tester"
echo -e "  ├── 📁 downloads/             # Temporary downloads"
echo -e "  ├── 📁 logs/                  # Log files"
echo -e "  ├── 📁 cookies/               # Browser cookies"
echo -e "  └── 📁 venv/                  # Python environment"
echo -e "\n🚀 ${YELLOW}How to start:${NC}"
echo -e "  ${GREEN}./start_bot.sh${NC}              # Start bot"
echo -e "  ${GREEN}nohup ./start_bot.sh &${NC}      # Start in background"
echo -e "\n⚙️ ${YELLOW}Management commands:${NC}"
echo -e "  ${GREEN}./stop_bot.sh${NC}               # Stop bot"
echo -e "  ${GREEN}./restart_bot.sh${NC}            # Restart bot"
echo -e "  ${GREEN}./status_bot.sh${NC}             # Check status"
echo -e "  ${GREEN}./view_logs.sh${NC}              # View logs"
echo -e "\n🔧 ${YELLOW}Test Facebook links:${NC}"
echo -e "  ${GREEN}python3 test_facebook_link.py \"URL\"${NC}"
echo -e "\n📝 ${YELLOW}Testing the bot:${NC}"
echo -e "  1. Send /start to your bot"
echo -e "  2. Send a valid Facebook link (not login/share link)"
echo -e "  3. Example: https://www.facebook.com/watch/?v=123456789"
echo -e "\n${RED}⚠️  Important for Facebook:${NC}"
echo -e "  • Use DIRECT video links, not login/share links"
echo -e "  • Links should contain 'watch/?v=' or '/videos/'"
echo -e "  • Avoid 'facebook.com/share/r/' links"
echo -e "  • Send /fbhelp in bot for instructions"
echo -e "\n${GREEN}🤖 Bot is ready!${NC}"
echo -e "${GREEN}==================================================${NC}"

# 13. Start bot in background
echo -e "\n${YELLOW}Starting bot in background...${NC}"
source venv/bin/activate
nohup python3 bot.py > logs/bot.log 2>&1 &

sleep 5

if pgrep -f "python3.*bot.py" > /dev/null; then
    echo -e "${GREEN}✅ Bot started successfully!${NC}"
    echo -e "${YELLOW}📝 Check logs: tail -f logs/bot.log${NC}"
    echo -e "${YELLOW}🔧 Check status: ./status_bot.sh${NC}"
else
    echo -e "${RED}⚠️  Bot might not have started. Check logs.${NC}"
    echo -e "${YELLOW}Run manually: ./start_bot.sh${NC}"
fi
