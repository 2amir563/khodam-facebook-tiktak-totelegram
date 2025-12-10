#!/bin/bash

# =========================================================
#         Universal Social Media Downloader Bot
# =========================================================
# This script installs a Telegram bot that downloads videos from various platforms

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

echo -e "${GREEN}🛠️ Installing Universal Social Media Downloader Bot...${NC}"

# Clean up previous installation
echo -e "${YELLOW}🧹 Cleaning up...${NC}"
rm -rf venv downloads logs cookies 2>/dev/null || true
mkdir -p downloads logs cookies

# 1. Install system dependencies
echo -e "${YELLOW}📦 Installing system dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git curl libmagic1 ffmpeg wget

# 2. Install yt-dlp system-wide
echo -e "${YELLOW}⬇️ Installing yt-dlp...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp
echo -e "${GREEN}✅ yt-dlp version: $(yt-dlp --version)${NC}"

# 3. Create virtual environment
echo -e "${YELLOW}🐍 Creating Python virtual environment...${NC}"

# Find Python executable
PYTHON_EXEC=$(which python3)
echo -e "${YELLOW}Using Python: $PYTHON_EXEC${NC}"

# Create fresh virtual environment
$PYTHON_EXEC -m venv venv --clear

# Activate virtual environment
source venv/bin/activate

# Verify activation
if [ -z "$VIRTUAL_ENV" ]; then
    echo -e "${RED}❌ Virtual environment activation failed${NC}"
    echo -e "${YELLOW}Trying alternative...${NC}"
    if [ -f "venv/bin/activate" ]; then
        . venv/bin/activate
    fi
fi

echo -e "${GREEN}✅ Virtual environment: $VIRTUAL_ENV${NC}"

# 4. Install Python packages
echo -e "${YELLOW}📦 Installing Python packages...${NC}"

# Upgrade pip
python3 -m pip install --upgrade pip

# Install packages with retry logic
install_package() {
    local package=$1
    echo -e "${YELLOW}Installing $package...${NC}"
    
    # Try normal installation
    if python3 -m pip install "$package" --no-cache-dir; then
        echo -e "${GREEN}✅ $package installed${NC}"
        return 0
    fi
    
    # Try without dependencies
    echo -e "${YELLOW}Retrying $package without dependencies...${NC}"
    if python3 -m pip install "$package" --no-deps --no-cache-dir; then
        echo -e "${GREEN}✅ $package installed (no deps)${NC}"
        return 0
    fi
    
    # Try alternative versions
    case "$package" in
        "python-telegram-bot[job-queue]")
            echo -e "${YELLOW}Trying basic python-telegram-bot...${NC}"
            python3 -m pip install "python-telegram-bot" --no-cache-dir && \
            echo -e "${GREEN}✅ python-telegram-bot installed${NC}" && return 0
            ;;
        "yt-dlp")
            # yt-dlp is already installed system-wide
            echo -e "${GREEN}✅ yt-dlp available system-wide${NC}"
            return 0
            ;;
    esac
    
    echo -e "${RED}❌ Failed to install $package${NC}"
    return 1
}

# Install packages
PACKAGES=(
    "python-telegram-bot[job-queue]"
    "python-dotenv"
    "requests"
    "yt-dlp"
)

for package in "${PACKAGES[@]}"; do
    install_package "$package" || true
done

# Install browser-cookie3 if possible (optional for Facebook)
echo -e "${YELLOW}🍪 Installing browser-cookie3 (optional)...${NC}"
python3 -m pip install browser-cookie3 --no-cache-dir 2>/dev/null || \
echo -e "${YELLOW}⚠️ browser-cookie3 not installed (optional)${NC}"

# 5. Get Bot Token
echo -e "${GREEN}🤖 Telegram Bot Configuration${NC}"
echo -e "${YELLOW}Enter your Telegram Bot Token (from @BotFather):${NC}"
read -r BOT_TOKEN

# Validate token
if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Invalid token format! Example: 1234567890:ABCdefGHIJKLMnopQRSTuvwXYZ${NC}"
    echo -e "${YELLOW}Enter token:${NC}"
    read -r BOT_TOKEN
    
    if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}❌ Invalid token. Exiting...${NC}"
        exit 1
    fi
fi

echo "BOT_TOKEN=$BOT_TOKEN" > $ENV_FILE
echo -e "${GREEN}✅ Token saved to $ENV_FILE${NC}"

# 6. Create configuration file
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

# Platform URL patterns
PLATFORM_PATTERNS = {
    "facebook": {
        "valid": [
            r'facebook\.com/watch/\?v=\d+',
            r'fb\.watch/[a-zA-Z0-9_-]+',
            r'facebook\.com/[^/]+/videos/\d+',
            r'facebook\.com/reel/\d+',
            r'facebook\.com/video\.php\?v=\d+',
            r'facebook\.com/share/v/\?id=\d+'
        ],
        "invalid": [
            r'facebook\.com/login',
            r'facebook\.com/dialog',
            r'facebook\.com/share/r/',
            r'_fb_noscript=1'
        ]
    },
    "tiktok": {
        "valid": [
            r'tiktok\.com/@[^/]+/video/\d+',
            r'tiktok\.com/t/[^/]+',
            r'vm\.tiktok\.com/[^/]+',
            r'vt\.tiktok\.com/[^/]+'
        ],
        "invalid": []
    },
    "youtube": {
        "valid": [
            r'youtube\.com/watch\?v=[^&]+',
            r'youtu\.be/[^/]+',
            r'youtube\.com/shorts/[^/]+'
        ],
        "invalid": []
    },
    "instagram": {
        "valid": [
            r'instagram\.com/p/[^/]+',
            r'instagram\.com/reel/[^/]+',
            r'instagram\.com/tv/[^/]+'
        ],
        "invalid": [
            r'instagram\.com/accounts/login'
        ]
    },
    "twitter": {
        "valid": [
            r'twitter\.com/[^/]+/status/\d+',
            r'x\.com/[^/]+/status/\d+'
        ],
        "invalid": []
    },
    "reddit": {
        "valid": [
            r'reddit\.com/r/[^/]+/comments/[^/]+'
        ],
        "invalid": []
    }
}

# yt-dlp Configuration for each platform
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
        '--format', 'best[height<=720][filesize<=50M]/best[height<=480]/best[height<=360]/best',
        '--max-filesize', '50M',
        '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        '--cookies-from-browser', 'chrome'
    ],
    'tiktok': [
        '--format', 'best[filesize<=50M]/worst',
        '--max-filesize', '50M'
    ],
    'youtube': [
        '--format', 'best[height<=720][filesize<=50M]/best[height<=480]/best[height<=360]/best',
        '--max-filesize', '50M'
    ],
    'instagram': [
        '--format', 'best[filesize<=50M]/worst',
        '--max-filesize', '50M'
    ],
    'twitter': [
        '--format', 'best[filesize<=50M]/worst',
        '--max-filesize', '50M'
    ],
    'reddit': [
        '--format', 'best[filesize<=50M]/worst',
        '--max-filesize', '50M'
    ],
    'default': [
        '--format', 'best[filesize<=50M]/worst',
        '--max-filesize', '50M'
    ]
}

def get_ytdlp_options(platform):
    """Get yt-dlp options for specific platform"""
    options = YT_DLP_OPTIONS['common'].copy()
    
    if platform in YT_DLP_OPTIONS:
        options.extend(YT_DLP_OPTIONS[platform])
    else:
        options.extend(YT_DLP_OPTIONS['default'])
    
    return options

def clean_url(url: str) -> str:
    """Clean URL by removing tracking parameters"""
    import urllib.parse
    
    # Remove Facebook specific tracking
    params_to_remove = [
        '_fb_noscript', '__tn__', '__cft__', '__xts__', 'rdid', 'e',
        'utm_source', 'utm_medium', 'utm_campaign', 'fbclid'
    ]
    
    try:
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
        
        # Remove double question marks
        cleaned = cleaned.replace('??', '?').replace('?&', '?')
        cleaned = cleaned.rstrip('&?')
        
        return cleaned
    except:
        return url

def validate_url_for_platform(url: str, platform: str) -> dict:
    """Validate URL for specific platform"""
    url_lower = url.lower()
    
    # Check invalid patterns first
    if platform in PLATFORM_PATTERNS:
        for pattern in PLATFORM_PATTERNS[platform].get("invalid", []):
            if re.search(pattern, url_lower):
                return {
                    "valid": False,
                    "error": f"Invalid {platform} link format detected."
                }
    
    # Check valid patterns
    if platform in PLATFORM_PATTERNS:
        for pattern in PLATFORM_PATTERNS[platform].get("valid", []):
            if re.search(pattern, url_lower):
                return {"valid": True}
    
    return {"valid": False, "error": "Link format not recognized."}
EOF

# 7. Create the main bot file
echo -e "${YELLOW}📝 Creating bot.py...${NC}"

cat << 'EOF' > $BOT_FILE
#!/usr/bin/env python3
# =========================================================
#           Universal Social Media Downloader Bot
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
from typing import Optional, Dict

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
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

class URLValidator:
    """Validate and process URLs for all platforms"""
    
    @staticmethod
    def get_platform(url: str) -> str:
        """Detect platform from URL"""
        url_lower = url.lower()
        
        if any(pattern in url_lower for pattern in ['facebook.com', 'fb.watch']):
            return 'facebook'
        elif any(pattern in url_lower for pattern in ['tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com']):
            return 'tiktok'
        elif any(pattern in url_lower for pattern in ['youtube.com', 'youtu.be']):
            return 'youtube'
        elif 'instagram.com' in url_lower:
            return 'instagram'
        elif any(pattern in url_lower for pattern in ['twitter.com', 'x.com']):
            return 'twitter'
        elif 'reddit.com' in url_lower:
            return 'reddit'
        elif 'terabox.com' in url_lower:
            return 'terabox'
        elif 'streamable.com' in url_lower:
            return 'streamable'
        elif any(pattern in url_lower for pattern in ['pinterest.com', 'pin.it']):
            return 'pinterest'
        elif 'snapchat.com' in url_lower:
            return 'snapchat'
        elif 'loom.com' in url_lower:
            return 'loom'
        elif any(pattern in url_lower for pattern in ['likee.video', 'like.com']):
            return 'likee'
        elif 'dailymotion.com' in url_lower:
            return 'dailymotion'
        elif 'bilibili.com' in url_lower:
            return 'bilibili'
        elif 'twitch.tv' in url_lower:
            return 'twitch'
        elif 'vimeo.com' in url_lower:
            return 'vimeo'
        else:
            return 'unknown'
    
    @staticmethod
    def validate_url(url: str) -> Dict:
        """Validate URL and return platform info"""
        # Basic URL validation
        if not url.startswith(('http://', 'https://')):
            return {
                "valid": False,
                "error": "❌ Invalid URL format. Please send a valid URL starting with http:// or https://"
            }
        
        # Clean URL
        cleaned_url = bot_config.clean_url(url)
        
        # Detect platform
        platform = URLValidator.get_platform(cleaned_url)
        
        if platform == 'unknown':
            return {
                "valid": False,
                "error": "❌ Platform not supported. Send /start to see supported platforms."
            }
        
        # Platform-specific validation
        validation = bot_config.validate_url_for_platform(cleaned_url, platform)
        
        if not validation["valid"]:
            error_msg = validation.get("error", f"Invalid {platform} link.")
            
            # Add guidance for Facebook
            if platform == 'facebook':
                error_msg += "\n\n📘 *Facebook Guide:*\n"
                error_msg += "• Use direct video links like:\n"
                error_msg += "  `https://www.facebook.com/watch/?v=123456789`\n"
                error_msg += "  `https://fb.watch/abc123def/`\n"
                error_msg += "• Avoid login/share redirect links"
            
            return {
                "valid": False,
                "error": error_msg,
                "platform": platform,
                "url": cleaned_url
            }
        
        return {
            "valid": True,
            "platform": platform,
            "url": cleaned_url,
            "original_url": url
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
    
    def cleanup_old_files(self, chat_dir: Path, max_age_hours: int = 6):
        """Clean up files older than specified hours"""
        try:
            now = datetime.now()
            for file_path in chat_dir.glob("*"):
                if file_path.is_file():
                    file_age = now - datetime.fromtimestamp(file_path.stat().st_mtime)
                    if file_age.total_seconds() > max_age_hours * 3600:
                        file_path.unlink()
        except Exception as e:
            logger.warning(f"Cleanup error: {e}")

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome_msg = (
        "👋 *Universal Downloader Bot*\n\n"
        "📥 *Supported Platforms:*\n"
        "• Facebook (Videos, Reels)\n"
        "• TikTok (All videos)\n"
        "• YouTube (Videos, Shorts)\n"
        "• Instagram (Posts, Reels)\n"
        "• Twitter/X (Videos)\n"
        "• Reddit (Videos)\n"
        "• 10+ other platforms\n\n"
        "📝 *How to use:*\n"
        "Send me a link from any supported platform!\n\n"
        "⚠️ *Limitations:*\n"
        "• Max file size: 50MB\n"
        "• Public content only\n"
        "• Direct video links (no login pages)\n\n"
        "🔧 *Commands:*\n"
        "/start - Show this message\n"
        "/help - Get help\n"
        "/fbhelp - Facebook specific help\n"
        "/examples - Example links"
    )
    await update.message.reply_text(welcome_msg, parse_mode='Markdown')

async def fbhelp_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Facebook specific help"""
    help_msg = (
        "📘 *Facebook Download Guide*\n\n"
        "✅ *Working links:*\n"
        "```\n"
        "https://www.facebook.com/watch/?v=123456789\n"
        "https://fb.watch/abc123def/\n"
        "https://www.facebook.com/username/videos/123456789\n"
        "https://www.facebook.com/reel/123456789\n"
        "```\n\n"
        "❌ *Non-working links:*\n"
        "• Login pages: `facebook.com/login/...`\n"
        "• Share redirects: `facebook.com/share/r/...`\n"
        "• Links with `_fb_noscript=1`\n\n"
        "💡 *How to get the right link:*\n"
        "1. Open video in browser\n"
        "2. Click on timestamp\n"
        "3. Copy URL from address bar\n"
        "4. Send it here"
    )
    await update.message.reply_text(help_msg, parse_mode='Markdown')

async def examples_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show example links"""
    examples_msg = (
        "🔗 *Example Links:*\n\n"
        "*Facebook:*\n"
        "`https://www.facebook.com/watch/?v=123456789`\n\n"
        "*TikTok:*\n"
        "`https://www.tiktok.com/@user/video/123456789`\n\n"
        "*YouTube:*\n"
        "`https://www.youtube.com/watch?v=dQw4w9WgXcQ`\n\n"
        "*Instagram:*\n"
        "`https://www.instagram.com/p/Cabcdef/`\n\n"
        "Try these or send your own link!"
    )
    await update.message.reply_text(examples_msg, parse_mode='Markdown')

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_msg = (
        "❓ *Help*\n\n"
        "*How to use:*\n"
        "1. Copy link from supported platform\n"
        "2. Send link to this bot\n"
        "3. Wait for processing\n"
        "4. Receive downloaded file\n\n"
        "*Troubleshooting:*\n"
        "• *Invalid link*: Send /fbhelp for Facebook\n"
        "• *File too large*: Max 50MB\n"
        "• *Format error*: Try different video\n"
        "• *Private content*: Must be public\n\n"
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
    
    logger.info(f"Message from {user.id}: {text[:100]}...")
    
    # Validate URL
    validator = URLValidator()
    validation = validator.validate_url(text)
    
    if not validation["valid"]:
        await update.message.reply_text(validation["error"], parse_mode='Markdown')
        return
    
    platform = validation["platform"]
    url = validation["url"]
    
    # Initialize download manager
    dm = DownloadManager()
    chat_dir = dm.get_download_path(chat_id)
    dm.cleanup_old_files(chat_dir)
    
    # Send initial message
    status_msg = await update.message.reply_text(
        f"⏳ *Processing {platform.upper()} link...*\n"
        f"Please wait...",
        parse_mode='Markdown'
    )
    
    downloaded_file = None
    
    try:
        # Update status
        await status_msg.edit_text(f"⬇️ *Downloading from {platform}...*", parse_mode='Markdown')
        
        # Download file with multiple format fallbacks
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
        error_msg = f"❌ *File Not Found*\n\nError: `{str(e)}`"
        await status_msg.edit_text(error_msg, parse_mode='Markdown')
        logger.error(f"File not found for {url}: {e}")
        
    except Exception as e:
        error_msg = f"❌ *Download Failed*\n\nPlatform: {platform}\nError: `{str(e)}`"
        
        # Special handling for format errors
        if "format is not available" in str(e) or "Requested format" in str(e):
            error_msg += "\n\n💡 *Tip:* This video might not have the requested format. Try a different video."
        
        await status_msg.edit_text(error_msg, parse_mode='Markdown')
        logger.error(f"Download failed for {url}: {e}")
        
    finally:
        # Cleanup
        if downloaded_file and downloaded_file.exists():
            try:
                downloaded_file.unlink()
                logger.info(f"Cleaned up: {downloaded_file}")
            except Exception as e:
                logger.warning(f"Failed to cleanup: {e}")

async def download_with_ytdlp(url: str, platform: str, output_path: Path) -> Path:
    """Download using yt-dlp with multiple format fallbacks"""
    unique_id = uuid4().hex
    filename_template = f"{unique_id}.%(ext)s"
    output_template = str(output_path / filename_template)
    
    # Get platform-specific options
    yt_dlp_options = bot_config.get_ytdlp_options(platform)
    
    # Build command
    cmd = ["yt-dlp"] + yt_dlp_options + ["-o", output_template, url]
    
    logger.info(f"Downloading from {platform}: {url[:100]}...")
    
    try:
        # First try: Use platform-specific format
        logger.info(f"First attempt with format options")
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=bot_config.DOWNLOAD_TIMEOUT)
        
        if process.returncode == 0:
            # Success - find downloaded file
            return await find_downloaded_file(output_path, unique_id)
        
        # Check error
        error_text = stderr.decode('utf-8', errors='ignore')
        
        # If format error, try with 'best' format
        if "format is not available" in error_text or "Requested format" in error_text:
            logger.info(f"Format error, trying 'best' format")
            
            # Build new command with simple 'best' format
            simple_cmd = [
                "yt-dlp",
                "--no-warnings",
                "--no-progress",
                "--restrict-filenames",
                "--max-filesize", "50M",
                "--format", "best",
                "-o", output_template,
                url
            ]
            
            process2 = await asyncio.create_subprocess_exec(
                *simple_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout2, stderr2 = await asyncio.wait_for(process2.communicate(), timeout=bot_config.DOWNLOAD_TIMEOUT)
            
            if process2.returncode == 0:
                return await find_downloaded_file(output_path, unique_id)
            else:
                error_text2 = stderr2.decode('utf-8', errors='ignore')
                raise Exception(f"Download failed: {error_text2.splitlines()[-1] if error_text2 else 'Unknown error'}")
        
        # Other errors
        error_lines = [line.strip() for line in error_text.split('\n') if line.strip()]
        last_error = error_lines[-1] if error_lines else "Unknown error"
        
        if "Private video" in error_text or "Video unavailable" in error_text:
            raise Exception("Video is private or unavailable.")
        elif "Sign in" in error_text:
            raise Exception("Content requires login. Try different public content.")
        elif "Unsupported URL" in error_text:
            raise Exception("Link not supported or invalid.")
        else:
            raise Exception(f"Download error: {last_error}")
            
    except asyncio.TimeoutError:
        raise Exception("Download timed out")
    except Exception as e:
        raise e

async def find_downloaded_file(output_path: Path, unique_id: str) -> Path:
    """Find downloaded file in directory"""
    # Search for file with unique ID
    for file_path in output_path.glob(f"{unique_id}.*"):
        if file_path.is_file() and file_path.stat().st_size > 0:
            return file_path
    
    # If not found, look for newest file
    files = list(output_path.glob("*"))
    if files:
        files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
        newest_file = files[0]
        file_age = datetime.now().timestamp() - newest_file.stat().st_mtime
        if file_age < 300:  # Created in last 5 minutes
            return newest_file
    
    raise FileNotFoundError("Downloaded file not found")

async def get_mime_type(file_path: Path) -> str:
    """Get MIME type of file"""
    try:
        result = subprocess.run(
            ['file', '-b', '--mime-type', str(file_path)],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip()
    except:
        # Fallback based on extension
        ext = file_path.suffix.lower()
        if ext in ['.mp4', '.avi', '.mov', '.mkv', '.webm', '.flv']:
            return 'video/mp4'
        elif ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
            return 'image/jpeg'
        elif ext in ['.mp3', '.m4a', '.wav']:
            return 'audio/mpeg'
        else:
            return 'application/octet-stream'

async def send_file_to_telegram(update: Update, context: ContextTypes.DEFAULT_TYPE, 
                               file_path: Path, url: str, mime_type: str):
    """Send file to Telegram"""
    chat_id = update.effective_chat.id
    
    try:
        with open(file_path, 'rb') as f:
            if mime_type.startswith('video'):
                await context.bot.send_video(
                    chat_id=chat_id,
                    video=f,
                    caption="✅ Downloaded successfully",
                    supports_streaming=True,
                    read_timeout=120,
                    write_timeout=120
                )
            elif mime_type.startswith('image'):
                await context.bot.send_photo(
                    chat_id=chat_id,
                    photo=f,
                    caption="✅ Downloaded successfully",
                    read_timeout=60
                )
            elif mime_type.startswith('audio'):
                await context.bot.send_audio(
                    chat_id=chat_id,
                    audio=f,
                    caption="✅ Downloaded successfully",
                    read_timeout=60
                )
            else:
                await context.bot.send_document(
                    chat_id=chat_id,
                    document=f,
                    caption="✅ Downloaded successfully",
                    read_timeout=60
                )
    except Exception as e:
        logger.error(f"Failed to send file: {e}")
        raise Exception(f"Upload failed: {str(e)}")

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Error: {context.error}", exc_info=True)
    
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
        logger.error("❌ BOT_TOKEN not found!")
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
    
    try:
        application.run_polling(
            allowed_updates=Update.ALL_TYPES,
            drop_pending_updates=True
        )
    except KeyboardInterrupt:
        logger.info("Bot stopped by user")
    except Exception as e:
        logger.error(f"Bot crashed: {e}")

if __name__ == "__main__":
    main()
EOF

# Make bot.py executable
chmod +x $BOT_FILE

# 8. Create management scripts
echo -e "${YELLOW}📁 Creating management scripts...${NC}"

# Start script
cat << 'EOF' > start_bot.sh
#!/bin/bash
# Start Telegram Downloader Bot

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting Telegram Downloader Bot...${NC}"

# Check if already running
if pgrep -f "python3.*bot.py" > /dev/null; then
    PID=$(pgrep -f "python3.*bot.py")
    echo -e "${YELLOW}⚠️ Bot is already running (PID: $PID)${NC}"
    echo -e "To restart: ${YELLOW}./restart_bot.sh${NC}"
    exit 0
fi

# Check .env
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Create .env with: BOT_TOKEN=your_token_here"
    exit 1
fi

# Check virtual environment
if [ ! -f "venv/bin/activate" ]; then
    echo -e "${RED}❌ Virtual environment not found!${NC}"
    echo -e "${YELLOW}Please run the installation script again.${NC}"
    exit 1
fi

# Create directories
mkdir -p downloads logs

# Activate venv
source venv/bin/activate

# Start bot
echo -e "${GREEN}🤖 Starting bot...${NC}"
echo -e "${YELLOW}📝 Logs: tail -f logs/bot.log${NC}"
echo -e "${YELLOW}🛑 Press Ctrl+C to stop${NC}"
echo ""

# Run bot
python3 bot.py
EOF

# Stop script
cat << 'EOF' > stop_bot.sh
#!/bin/bash
# Stop Telegram Downloader Bot

echo "🛑 Stopping bot..."

# Kill bot process
if pgrep -f "python3.*bot.py" > /dev/null; then
    pkill -f "python3.*bot.py"
    echo "✅ Bot stopped"
else
    echo "ℹ️ Bot was not running"
fi

# Kill yt-dlp processes
if pgrep -f "yt-dlp" > /dev/null; then
    pkill -f "yt-dlp"
    echo "✅ Cleaned up yt-dlp processes"
fi

sleep 2
EOF

# Restart script
cat << 'EOF' > restart_bot.sh
#!/bin/bash
# Restart Telegram Downloader Bot

echo "🔄 Restarting bot..."
./stop_bot.sh
sleep 3
echo ""
./start_bot.sh
EOF

# Status script
cat << 'EOF' > status_bot.sh
#!/bin/bash
# Check bot status

echo "🤖 Bot Status"
echo "============"

if pgrep -f "python3.*bot.py" > /dev/null; then
    echo "✅ Status: RUNNING"
    echo "📊 PID: $(pgrep -f "python3.*bot.py")"
    if command -v ps >/dev/null 2>&1; then
        echo "⏰ Uptime: $(ps -p $(pgrep -f "python3.*bot.py") -o etime= 2>/dev/null || echo "Unknown")"
    fi
else
    echo "❌ Status: STOPPED"
fi

# Check active downloads
YT_DLP_COUNT=$(pgrep -f "yt-dlp" | wc -l)
if [ $YT_DLP_COUNT -gt 0 ]; then
    echo "📥 Active downloads: $YT_DLP_COUNT"
fi

# Check directories
echo "📁 Directories:"
echo "  downloads/ - $(find downloads -type f 2>/dev/null | wc -l) files"
echo "  logs/ - $(du -sh logs 2>/dev/null | cut -f1) size"

# Check last log
if [ -f "logs/bot.log" ]; then
    echo "📄 Last log entry:"
    tail -1 logs/bot.log 2>/dev/null || echo "  No recent logs"
fi

echo "============"
EOF

# Log viewer
cat << 'EOF' > view_logs.sh
#!/bin/bash
# View bot logs

if [ ! -f "logs/bot.log" ]; then
    echo "No log file found."
    echo "Start the bot first: ./start_bot.sh"
    exit 1
fi

echo "📋 Bot Logs (last 100 lines)"
echo "============================="
echo ""
tail -100 logs/bot.log
echo ""
echo "============================="
echo "For real-time logs, run: tail -f logs/bot.log"
EOF

# Make scripts executable
chmod +x start_bot.sh stop_bot.sh restart_bot.sh status_bot.sh view_logs.sh

# 9. Create test script
cat << 'EOF' > test_install.py
#!/usr/bin/env python3
"""
Test bot installation
"""
import os
import sys

def test():
    print("🔧 Testing Installation")
    print("=" * 40)
    
    tests_passed = 0
    total_tests = 0
    
    # Test 1: Python version
    total_tests += 1
    try:
        import platform
        version = platform.python_version()
        print(f"✅ Python {version}")
        tests_passed += 1
    except:
        print("❌ Python not found")
    
    # Test 2: Required packages
    packages = [
        ("telegram", "python-telegram-bot"),
        ("dotenv", "python-dotenv"),
        ("yt_dlp", "yt-dlp"),
        ("requests", "requests")
    ]
    
    for import_name, package_name in packages:
        total_tests += 1
        try:
            __import__(import_name)
            print(f"✅ {package_name}")
            tests_passed += 1
        except ImportError:
            print(f"❌ {package_name}")
    
    # Test 3: .env file
    total_tests += 1
    if os.path.exists(".env"):
        with open(".env", "r") as f:
            content = f.read()
            if "BOT_TOKEN=" in content:
                print("✅ .env file with BOT_TOKEN")
                tests_passed += 1
            else:
                print("❌ .env missing BOT_TOKEN")
    else:
        print("❌ .env file not found")
    
    # Test 4: Directories
    directories = ["downloads", "logs", "venv"]
    for dir_name in directories:
        total_tests += 1
        if os.path.exists(dir_name):
            print(f"✅ Directory: {dir_name}")
            tests_passed += 1
        else:
            print(f"❌ Missing: {dir_name}")
    
    # Test 5: yt-dlp executable
    total_tests += 1
    try:
        import subprocess
        result = subprocess.run(["yt-dlp", "--version"], capture_output=True, text=True)
        if result.returncode == 0:
            print(f"✅ yt-dlp: {result.stdout.strip()}")
            tests_passed += 1
        else:
            print("❌ yt-dlp not working")
    except:
        print("❌ yt-dlp test failed")
    
    print("=" * 40)
    print(f"Results: {tests_passed}/{total_tests} tests passed")
    
    if tests_passed == total_tests:
        print("🎉 All tests passed! You can start the bot with: ./start_bot.sh")
        return True
    else:
        print("⚠️ Some tests failed. Check the errors above.")
        return False

if __name__ == "__main__":
    success = test()
    sys.exit(0 if success else 1)
EOF

chmod +x test_install.py

# 10. Create requirements.txt
cat << 'EOF' > requirements.txt
python-telegram-bot[job-queue]>=20.0
python-dotenv>=1.0.0
yt-dlp>=2024.4.9
requests>=2.28.0
EOF

# 11. Final instructions
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "\n📁 ${YELLOW}Files created:${NC}"
ls -la

echo -e "\n🚀 ${YELLOW}Quick Start:${NC}"
echo -e "  ${GREEN}./test_install.py${NC}    # Test installation"
echo -e "  ${GREEN}./start_bot.sh${NC}       # Start the bot"
echo -e "\n⚙️ ${YELLOW}Management:${NC}"
echo -e "  ${GREEN}./stop_bot.sh${NC}        # Stop bot"
echo -e "  ${GREEN}./restart_bot.sh${NC}     # Restart bot"
echo -e "  ${GREEN}./status_bot.sh${NC}      # Check status"
echo -e "  ${GREEN}./view_logs.sh${NC}       # View logs"
echo -e "\n📝 ${YELLOW}To test the bot:${NC}"
echo -e "  1. Run: ${GREEN}./start_bot.sh${NC}"
echo -e "  2. Send /start to your bot on Telegram"
echo -e "  3. Send a Facebook link like:"
echo -e "     ${BLUE}https://www.facebook.com/watch/?v=123456789${NC}"
echo -e "\n${RED}⚠️ Important Notes:${NC}"
echo -e "  • Facebook links must be DIRECT video links"
echo -e "  • Avoid login/share redirect links"
echo -e "  • Max file size: 50MB"
echo -e "  • Only public content"
echo -e "\n${GREEN}🤖 Bot is ready!${NC}"
echo -e "${GREEN}==================================================${NC}"

# 12. Test installation
echo -e "\n${YELLOW}🔧 Testing installation...${NC}"
source venv/bin/activate
python3 test_install.py

# 13. Ask to start bot
echo -e "\n${YELLOW}Start bot now? (y/n)${NC}"
read -r START_CHOICE

if [[ "$START_CHOICE" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Starting bot...${NC}"
    ./start_bot.sh
else
    echo -e "${YELLOW}To start later: ./start_bot.sh${NC}"
fi
