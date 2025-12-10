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

# Clean up any existing virtual environment
echo -e "${YELLOW}🧹 Cleaning up previous installation...${NC}"
rm -rf venv downloads logs cookies
mkdir -p downloads logs cookies

# 1. Update packages and install prerequisites
echo -e "${YELLOW}📦 Updating system packages and installing dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git curl libmagic1 ffmpeg wget

# Check Python version
PYTHON_VERSION=$(python3 --version)
echo -e "${GREEN}✅ Python version: $PYTHON_VERSION${NC}"

# 2. Install yt-dlp
echo -e "${YELLOW}⬇️ Installing yt-dlp...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp

# Test yt-dlp
yt-dlp --version
echo -e "${GREEN}✅ yt-dlp installed${NC}"

# 3. Create virtual environment properly
echo -e "${YELLOW}🐍 Creating Python virtual environment...${NC}"

# First, check if we need to clean python3 symlinks
if [ -L "/usr/bin/python3" ]; then
    echo -e "${YELLOW}⚠️ Found symbolic link for python3, checking...${NC}"
    REAL_PYTHON=$(readlink -f /usr/bin/python3)
    echo -e "${GREEN}Real python3 path: $REAL_PYTHON${NC}"
fi

# Remove any broken venv
rm -rf venv

# Create virtual environment with explicit python path
PYTHON_PATH=$(which python3)
echo -e "${YELLOW}Using Python at: $PYTHON_PATH${NC}"

$PYTHON_PATH -m venv venv --clear

# Verify venv creation
if [ ! -f "venv/bin/activate" ]; then
    echo -e "${RED}❌ Failed to create virtual environment${NC}"
    echo -e "${YELLOW}Trying alternative method...${NC}"
    
    # Try pip install virtualenv
    pip3 install virtualenv --user
    virtualenv venv
fi

# Activate virtual environment
source venv/bin/activate

# Check if activation worked
if [ -z "$VIRTUAL_ENV" ]; then
    echo -e "${RED}❌ Virtual environment activation failed${NC}"
    echo -e "${YELLOW}Using system Python instead...${NC}"
else
    echo -e "${GREEN}✅ Virtual environment activated: $VIRTUAL_ENV${NC}"
fi

# 4. Install Python packages
echo -e "${YELLOW}📦 Installing Python packages...${NC}"

# Upgrade pip first
python3 -m pip install --upgrade pip

# Install packages with retry logic
install_packages() {
    local packages=("$@")
    for package in "${packages[@]}"; do
        echo -e "${YELLOW}Installing $package...${NC}"
        
        # Try with default pip
        if python3 -m pip install "$package" --no-cache-dir; then
            echo -e "${GREEN}✅ $package installed${NC}"
        else
            echo -e "${YELLOW}⚠️ Retrying $package with different method...${NC}"
            
            # Try without dependencies first
            if python3 -m pip install "$package" --no-deps --no-cache-dir; then
                echo -e "${GREEN}✅ $package installed (without deps)${NC}"
                
                # Try to install dependencies separately
                if [ "$package" == "python-telegram-bot" ]; then
                    python3 -m pip install "httpx~=0.24.0" "cryptography" --no-cache-dir
                fi
            else
                echo -e "${RED}❌ Failed to install $package${NC}"
                echo -e "${YELLOW}Trying from GitHub...${NC}"
                
                # Try GitHub for specific packages
                case "$package" in
                    "python-telegram-bot")
                        python3 -m pip install "python-telegram-bot[job-queue]" --no-cache-dir || \
                        python3 -m pip install "https://github.com/python-telegram-bot/python-telegram-bot/archive/refs/tags/v20.7.tar.gz" --no-cache-dir
                        ;;
                    "browser-cookie3")
                        python3 -m pip install "browser-cookie3" --no-cache-dir || \
                        echo -e "${YELLOW}⚠️ browser-cookie3 may not be available, skipping...${NC}"
                        ;;
                    *)
                        echo -e "${YELLOW}⚠️ Skipping $package${NC}"
                        ;;
                esac
            fi
        fi
    done
}

# List of packages to install
PACKAGES=(
    "python-telegram-bot[job-queue]"
    "python-dotenv"
    "uuid"
    "requests"
    "yt-dlp"
)

install_packages "${PACKAGES[@]}"

# Try to install browser-cookie3 separately (optional)
echo -e "${YELLOW}🍪 Installing browser-cookie3 (optional for Facebook)...${NC}"
python3 -m pip install "browser-cookie3" --no-cache-dir 2>/dev/null || \
echo -e "${YELLOW}⚠️ browser-cookie3 installation failed (optional package)${NC}"

# 5. Configure Bot Token
echo -e "${GREEN}🤖 Telegram Bot Configuration${NC}"
echo -e "${YELLOW}Please enter your Telegram Bot Token (from @BotFather):${NC}"
read -r BOT_TOKEN

# Validate token format
if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Invalid bot token format! Example: 1234567890:ABCdefGHIJKLMnopQRSTuvwXYZ${NC}"
    echo -e "${YELLOW}Please enter a valid token:${NC}"
    read -r BOT_TOKEN
    
    if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}❌ Invalid token again. Exiting...${NC}"
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

# Platform-specific URL patterns
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
        "invalid": [
            r'tiktok\.com/login',
            r'tiktok\.com/redirect'
        ]
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
    }
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
        '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
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

def clean_url(url: str) -> str:
    """Clean URL by removing tracking parameters"""
    import urllib.parse
    
    # Remove common tracking parameters
    params_to_remove = [
        '_fb_noscript', '__tn__', '__cft__', '__xts__', 'rdid', 'e',
        'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
        'fbclid', 'gclid', 'msclkid'
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
                    "error": f"Invalid {platform} link detected. This appears to be a login/redirect/tracking link."
                }
    
    # Check valid patterns
    if platform in PLATFORM_PATTERNS:
        for pattern in PLATFORM_PATTERNS[platform].get("valid", []):
            if re.search(pattern, url_lower):
                return {"valid": True}
    
    return {"valid": False, "error": "Link format not recognized for this platform."}
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
import urllib.parse
from pathlib import Path
from uuid import uuid4
from datetime import datetime

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
    def validate_url(url: str) -> dict:
        """Validate URL and return platform info with detailed feedback"""
        # Basic URL validation
        if not url.startswith(('http://', 'https://')):
            return {
                "valid": False,
                "error": "❌ Invalid URL format. Please send a valid URL starting with http:// or https://"
            }
        
        # Clean URL first
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
            
            # Add platform-specific guidance
            guidance = URLValidator.get_platform_guidance(platform)
            if guidance:
                error_msg += f"\n\n{guidance}"
            
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
    
    @staticmethod
    def get_platform_guidance(platform: str) -> str:
        """Get guidance for specific platform"""
        guidance = {
            "facebook": (
                "📘 *Facebook Link Guide:*\n"
                "✅ Use DIRECT video links like:\n"
                "• https://www.facebook.com/watch/?v=123456789\n"
                "• https://fb.watch/abc123def/\n"
                "• https://www.facebook.com/username/videos/123456789\n\n"
                "❌ Avoid these:\n"
                "• Login pages (facebook.com/login)\n"
                "• Share redirects (facebook.com/share/r/)\n"
                "• Links with '_fb_noscript=1'\n\n"
                "💡 *Tip:* Click on video timestamp to get direct link."
            ),
            "tiktok": (
                "📘 *TikTok Link Guide:*\n"
                "✅ Use standard TikTok links:\n"
                "• https://www.tiktok.com/@username/video/123456789\n"
                "• https://vm.tiktok.com/abc123def/\n\n"
                "❌ Avoid:\n"
                "• Private/direct message links\n"
                "• Deleted videos\n"
                "• Login/redirect pages"
            ),
            "instagram": (
                "📘 *Instagram Link Guide:*\n"
                "✅ Use public post links:\n"
                "• https://www.instagram.com/p/abc123def/\n"
                "• https://www.instagram.com/reel/abc123def/\n\n"
                "❌ Avoid:\n"
                "• Private account posts\n"
                "• Stories (unless public)\n"
                "• Login pages"
            ),
            "youtube": (
                "📘 *YouTube Link Guide:*\n"
                "✅ Standard links work fine:\n"
                "• https://www.youtube.com/watch?v=abc123def\n"
                "• https://youtu.be/abc123def\n"
                "• https://www.youtube.com/shorts/abc123def\n\n"
                "⚠️ Note: Max 50MB file size"
            )
        }
        
        return guidance.get(platform, "Please ensure the content is public and accessible.")

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
                        logger.debug(f"Cleaned up old file: {file_path}")
        except Exception as e:
            logger.warning(f"Cleanup error: {e}")

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome_msg = (
        "👋 *Universal Downloader Bot*\n\n"
        "📥 *Supported Platforms:*\n"
        "• *Facebook*: Public videos\n"
        "• *TikTok*: All public videos\n"
        "• *YouTube*: Videos, Shorts (50MB max)\n"
        "• *Instagram*: Posts, Reels\n"
        "• *Twitter/X*: Videos\n"
        "• *Reddit*: Videos\n"
        "• *Terabox*: Videos\n"
        "• *Streamable*: Videos\n"
        "• *Pinterest*: Images & Videos\n"
        "• *Snapchat*: Spotlight\n"
        "• *Loom*: Videos\n"
        "• *Likee*: Videos\n"
        "• *DailyMotion*: Videos\n"
        "• *Bilibili*: Videos\n"
        "• *Twitch*: Clips\n"
        "• *Vimeo*: Videos\n\n"
        "📝 *How to use:*\n"
        "Send me a link from any supported platform!\n\n"
        "⚠️ *Important:*\n"
        "• Max file size: 50MB\n"
        "• Only public content\n"
        "• No login/redirect links\n\n"
        "🔧 *Commands:*\n"
        "/start - Show this message\n"
        "/help - Get help\n"
        "/guide - Platform-specific guides\n"
        "/examples - Example links"
    )
    await update.message.reply_text(welcome_msg, parse_mode='Markdown')

async def guide_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show platform guides"""
    guide_msg = (
        "📘 *Platform Guides*\n\n"
        "*Facebook:*\n"
        "Use direct video links:\n"
        "`https://www.facebook.com/watch/?v=123456789`\n"
        "`https://fb.watch/abc123def/`\n\n"
        "*TikTok:*\n"
        "`https://www.tiktok.com/@user/video/123456789`\n"
        "`https://vm.tiktok.com/abc123def/`\n\n"
        "*YouTube:*\n"
        "`https://www.youtube.com/watch?v=abc123def`\n"
        "`https://youtu.be/abc123def`\n\n"
        "*Instagram:*\n"
        "`https://www.instagram.com/p/abc123def/`\n"
        "`https://www.instagram.com/reel/abc123def/`\n\n"
        "Need specific help? Send your link!"
    )
    await update.message.reply_text(guide_msg, parse_mode='Markdown')

async def examples_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Show example links"""
    examples_msg = (
        "🔗 *Example Links:*\n\n"
        "*Facebook:*\n"
        "`https://www.facebook.com/watch/?v=123456789`\n\n"
        "*TikTok:*\n"
        "`https://www.tiktok.com/@example/video/123456789`\n\n"
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
        "*How to download:*\n"
        "1. Copy link from supported platform\n"
        "2. Send link to this bot\n"
        "3. Wait for processing\n"
        "4. Receive downloaded file\n\n"
        "*Common issues:*\n"
        "• *Invalid link*: Send /guide for correct formats\n"
        "• *File too large*: Max 50MB\n"
        "• *Private content*: Must be public\n"
        "• *Login/redirect links*: Get direct link\n\n"
        "*Commands:*\n"
        "/start - Welcome message\n"
        "/guide - Link format guide\n"
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
        f"Platform: {platform}\n"
        f"Please wait...",
        parse_mode='Markdown'
    )
    
    downloaded_file = None
    
    try:
        # Update status
        await status_msg.edit_text(f"⬇️ *Downloading from {platform}...*", parse_mode='Markdown')
        
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
        error_msg = f"❌ *File Not Found*\n\nError: `{str(e)}`"
        await status_msg.edit_text(error_msg, parse_mode='Markdown')
        logger.error(f"File not found for {url}: {e}")
        
    except Exception as e:
        error_msg = f"❌ *Download Failed*\n\nPlatform: {platform}\nError: `{str(e)}`"
        
        # Add platform-specific advice
        if platform == 'facebook':
            error_msg += "\n\n💡 *Facebook Tip:* Ensure you're using a direct video link, not a login/share link."
        elif platform == 'tiktok':
            error_msg += "\n\n💡 *TikTok Tip:* Video might be private or region-restricted."
        
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
    cmd = ["yt-dlp"] + yt_dlp_options + ["-o", output_template, url]
    
    logger.info(f"Executing yt-dlp for {platform}")
    
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
            
            # Parse common errors
            if "Unsupported URL" in error_text:
                raise Exception("Link not supported or requires login.")
            elif "Private video" in error_text or "Video unavailable" in error_text:
                raise Exception("Video is private or unavailable.")
            elif "Sign in" in error_text:
                raise Exception("Content requires login. Try different public content.")
            else:
                # Get last meaningful error line
                error_lines = [line.strip() for line in error_text.split('\n') if line.strip()]
                last_error = error_lines[-1] if error_lines else "Unknown error"
                raise Exception(f"Download error: {last_error}")
        
        # Find downloaded file
        downloaded_file = None
        
        # Method 1: Search for file with unique ID
        for file_path in output_path.glob(f"{unique_id}.*"):
            if file_path.is_file() and file_path.stat().st_size > 0:
                downloaded_file = file_path
                break
        
        # Method 2: Look for newest file
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
            raise FileNotFoundError("Downloaded file not found")
        
        return downloaded_file
        
    except asyncio.TimeoutError:
        raise Exception("Download timed out")
    except Exception as e:
        raise e

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
        elif ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']:
            return 'image/jpeg'
        elif ext in ['.mp3', '.m4a', '.wav', '.ogg']:
            return 'audio/mpeg'
        else:
            return 'application/octet-stream'

async def send_file_to_telegram(update: Update, context: ContextTypes.DEFAULT_TYPE, 
                               file_path: Path, url: str, mime_type: str):
    """Send file to Telegram"""
    chat_id = update.effective_chat.id
    file_size = file_path.stat().st_size
    
    try:
        with open(file_path, 'rb') as f:
            if mime_type.startswith('video'):
                await context.bot.send_video(
                    chat_id=chat_id,
                    video=f,
                    caption=f"✅ Downloaded\nSize: {file_size/1024/1024:.1f}MB",
                    supports_streaming=True,
                    read_timeout=120,
                    write_timeout=120,
                    connect_timeout=120
                )
            elif mime_type.startswith('image'):
                await context.bot.send_photo(
                    chat_id=chat_id,
                    photo=f,
                    caption=f"✅ Downloaded\nSize: {file_size/1024/1024:.1f}MB",
                    read_timeout=60
                )
            elif mime_type.startswith('audio'):
                await context.bot.send_audio(
                    chat_id=chat_id,
                    audio=f,
                    caption=f"✅ Downloaded\nSize: {file_size/1024/1024:.1f}MB",
                    read_timeout=60
                )
            else:
                await context.bot.send_document(
                    chat_id=chat_id,
                    document=f,
                    caption=f"✅ Downloaded\nSize: {file_size/1024/1024:.1f}MB",
                    read_timeout=60
                )
    except Exception as e:
        logger.error(f"Failed to send file: {e}")
        raise Exception(f"Failed to upload to Telegram: {str(e)}")

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
    application.add_handler(CommandHandler("guide", guide_command))
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
            drop_pending_updates=True,
            close_loop=False
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
    echo -e "${YELLOW}⚠️ Bot is already running!${NC}"
    echo -e "PID: $(pgrep -f "python3.*bot.py")"
    echo -e "To restart: ${YELLOW}./restart_bot.sh${NC}"
    exit 0
fi

# Check .env
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Create .env with: BOT_TOKEN=your_token_here"
    exit 1
fi

# Create directories
mkdir -p downloads logs

# Check Python
if [ ! -f "venv/bin/activate" ]; then
    echo -e "${RED}❌ Virtual environment not found!${NC}"
    echo -e "${YELLOW}Please run the installation script first.${NC}"
    exit 1
fi

# Activate venv
source venv/bin/activate

# Update yt-dlp if possible
echo -e "${YELLOW}🔧 Checking for updates...${NC}"
python3 -m pip install --upgrade yt-dlp 2>/dev/null || true

# Start bot
echo -e "${GREEN}🤖 Starting bot...${NC}"
echo -e "${YELLOW}📝 Logs: tail -f logs/bot.log${NC}"
echo -e "${YELLOW}🛑 Press Ctrl+C to stop${NC}"

# Run bot
exec python3 bot.py
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
    echo "⏰ Uptime: $(ps -p $(pgrep -f "python3.*bot.py") -o etime= 2>/dev/null || echo "Unknown")"
else
    echo "❌ Status: STOPPED"
fi

# Check active downloads
YT_DLP_COUNT=$(pgrep -f "yt-dlp" | wc -l)
if [ $YT_DLP_COUNT -gt 0 ]; then
    echo "📥 Active downloads: $YT_DLP_COUNT"
fi

# Check log file
if [ -f "logs/bot.log" ]; then
    LOG_SIZE=$(du -h logs/bot.log | cut -f1)
    echo "📄 Log size: $LOG_SIZE"
    echo "📋 Last activity:"
    tail -3 logs/bot.log 2>/dev/null | while read line; do echo "  $line"; done
fi

echo "============"
EOF

# Log viewer
cat << 'EOF' > view_logs.sh
#!/bin/bash
# View bot logs

echo "📋 Bot Logs"
echo "==========="

if [ ! -f "logs/bot.log" ]; then
    echo "No log file found."
    echo "Starting bot to create logs..."
    ./start_bot.sh
    exit 0
fi

echo "Showing last 50 lines. Press Ctrl+C to exit."
echo ""
tail -50f logs/bot.log
EOF

# Make scripts executable
chmod +x start_bot.sh stop_bot.sh restart_bot.sh status_bot.sh view_logs.sh

# 9. Create a simple test script
cat << 'EOF' > test_bot.py
#!/usr/bin/env python3
"""
Simple test to verify bot installation
"""
import sys
import os

def test_installation():
    print("🔧 Testing bot installation...")
    print("=" * 40)
    
    # Check Python
    try:
        import platform
        print(f"✅ Python: {platform.python_version()}")
    except:
        print("❌ Python not found")
        return False
    
    # Check packages
    packages = [
        ("telegram", "python-telegram-bot"),
        ("dotenv", "python-dotenv"),
        ("yt_dlp", "yt-dlp"),
        ("requests", "requests")
    ]
    
    for import_name, package_name in packages:
        try:
            __import__(import_name)
            print(f"✅ {package_name}")
        except ImportError as e:
            print(f"❌ {package_name}: {str(e)}")
            return False
    
    # Check .env
    if os.path.exists(".env"):
        print("✅ .env file exists")
        with open(".env", "r") as f:
            content = f.read()
            if "BOT_TOKEN" in content:
                print("✅ BOT_TOKEN found in .env")
            else:
                print("⚠️ BOT_TOKEN not found in .env")
    else:
        print("❌ .env file not found")
        return False
    
    # Check directories
    directories = ["downloads", "logs", "venv"]
    for dir_name in directories:
        if os.path.exists(dir_name):
            print(f"✅ Directory: {dir_name}")
        else:
            print(f"❌ Directory missing: {dir_name}")
            if dir_name == "venv":
                return False
    
    print("=" * 40)
    print("✅ All tests passed!")
    print("\nTo start the bot:")
    print("  ./start_bot.sh")
    return True

if __name__ == "__main__":
    success = test_installation()
    sys.exit(0 if success else 1)
EOF

chmod +x test_bot.py

# 10. Create requirements.txt
cat << 'EOF' > requirements.txt
python-telegram-bot[job-queue]>=20.7
python-dotenv>=1.0.0
yt-dlp>=2024.4.9
requests>=2.31.0
uuid>=1.30
EOF

# 11. Final instructions
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "\n📁 ${YELLOW}Project Structure:${NC}"
ls -la
echo -e "\n🚀 ${YELLOW}Quick Start:${NC}"
echo -e "  ${GREEN}./start_bot.sh${NC}        # Start the bot"
echo -e "  ${GREEN}./test_bot.py${NC}        # Test installation"
echo -e "\n⚙️ ${YELLOW}Management:${NC}"
echo -e "  ${GREEN}./stop_bot.sh${NC}        # Stop bot"
echo -e "  ${GREEN}./restart_bot.sh${NC}     # Restart bot"
echo -e "  ${GREEN}./status_bot.sh${NC}      # Check status"
echo -e "  ${GREEN}./view_logs.sh${NC}       # View logs"
echo -e "\n📝 ${YELLOW}Testing:${NC}"
echo -e "  1. Run: ${GREEN}./test_bot.py${NC}"
echo -e "  2. Start: ${GREEN}./start_bot.sh${NC}"
echo -e "  3. Send /start to your bot on Telegram"
echo -e "\n${RED}⚠️ Important Notes:${NC}"
echo -e "  • Bot only downloads PUBLIC content"
echo -e "  • Max file size: 50MB"
echo -e "  • Avoid login/redirect links"
echo -e "  • Use direct video links"
echo -e "\n${GREEN}🤖 Bot is ready to use!${NC}"
echo -e "${GREEN}==================================================${NC}"

# 12. Test installation
echo -e "\n${YELLOW}🔧 Running installation test...${NC}"
source venv/bin/activate
python3 test_bot.py

# 13. Start bot option
echo -e "\n${YELLOW}Do you want to start the bot now? (y/n)${NC}"
read -r START_NOW

if [[ $START_NOW =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Starting bot...${NC}"
    ./start_bot.sh
else
    echo -e "${YELLOW}To start later, run: ./start_bot.sh${NC}"
fi
