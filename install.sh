#!/bin/bash
# ============================================
# Telegram Media Downloader Bot - Complete Installer
# Works on fresh servers
# ============================================

set -e  # Exit on error

echo "=============================================="
echo "🤖 Telegram Media Downloader Bot - FRESH SERVER"
echo "=============================================="
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root: sudo bash install.sh"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Ask for bot token
echo "🔑 Enter your bot token from @BotFather:"
echo "Example: 1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ"
echo ""
read -p "📝 Bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "Bot token is required!"
    exit 1
fi

print_status "Starting fresh server installation..."

# ============================================
# STEP 1: Update System and Install Basics
# ============================================
print_status "Updating system packages..."
apt-get update
apt-get upgrade -y

print_status "Installing essential system tools..."
apt-get install -y \
    curl \
    wget \
    git \
    nano \
    htop \
    screen \
    cron \
    unzip \
    pv \
    jq

# ============================================
# STEP 2: Install Python and Core Dependencies
# ============================================
print_status "Installing Python and pip..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev

# Install ffmpeg for video processing
print_status "Installing ffmpeg..."
apt-get install -y ffmpeg

# Install build tools for compiling
print_status "Installing build essentials..."
apt-get install -y \
    build-essential \
    libssl-dev \
    libffi-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev

# ============================================
# STEP 3: Create Project Structure
# ============================================
print_status "Creating project directory..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create all needed directories
mkdir -p downloads logs cookies tmp config
chmod 755 downloads logs cookies tmp config

# ============================================
# STEP 4: Install Python Packages (Optimized)
# ============================================
print_status "Installing Python packages..."

# First upgrade pip with root action to suppress warnings
pip3 install --upgrade pip --root-user-action=ignore

# Install core packages first
print_status "Installing core dependencies..."
for package in \
    "python-telegram-bot==20.7" \
    "python-dotenv==1.0.0" \
    "aiofiles==23.2.1" \
    "psutil==5.9.8" \
    "requests==2.31.0" \
    "beautifulsoup4==4.12.3" \
    "lxml==4.9.4" \
    "pillow==10.2.0"
do
    print_info "Installing: $package"
    pip3 install "$package" --root-user-action=ignore || print_warning "Continuing despite $package install issue"
done

# Install yt-dlp with specific version to avoid conflicts
print_status "Installing yt-dlp with all extractors..."
pip3 install "yt-dlp==2024.4.9" --root-user-action=ignore

# Install additional useful packages
print_status "Installing helper packages..."
pip3 install brotli urllib3 --root-user-action=ignore

# ============================================
# STEP 5: Create Configuration Files
# ============================================
print_status "Creating configuration files..."

# Create .env file with bot token
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
YTDLP_USER_AGENT="Mozilla/5.0 (compatible; yt-dlp-bot/1.0)"
YTDLP_MAX_DOWNLOAD_SIZE=2000M
YTDLP_REFERER="https://www.google.com/"

# Bot Settings
ENABLE_QUALITY_SELECTION=false
SHOW_FILE_SIZE=true
AUTO_CLEANUP=true
EOF

print_status "✅ Created .env file with bot token"

# Create yt-dlp config file
cat > config/yt-dlp-config.conf << 'EOF'
# yt-dlp configuration for telegram bot
--no-warnings
--ignore-errors
--no-playlist
--concurrent-fragments 2
--limit-rate 5M
--socket-timeout 30
--retries 5
--fragment-retries 5
--skip-unavailable-fragments

# Output configuration
--output "downloads/%(title)s_%(id)s.%(ext)s"
--merge-output-format mp4

# Quality settings
--format "bestvideo[height<=720]+bestaudio/best[height<=720]"

# Networking settings
--user-agent "Mozilla/5.0 (compatible; yt-dlp-bot/1.0)"
--referer "https://www.google.com/"
--force-ipv4

# Platform specific settings
--extractor-args "youtube:player-client=android,web"
--extractor-args "reddit:user-agent=Mozilla/5.0"
--extractor-args "pinterest:skip_auth_warning=true"
EOF

# ============================================
# STEP 6: Create the Main Bot File
# ============================================
print_status "Creating main bot file..."

cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - Complete Solution for Fresh Servers
Simplified version with better error handling
"""

import os
import sys
import logging
import subprocess
import asyncio
import json
import re
from pathlib import Path
from datetime import datetime
from urllib.parse import urlparse, unquote

from telegram import Update
from telegram.ext import (
    Application, 
    CommandHandler, 
    MessageHandler, 
    filters, 
    ContextTypes
)
from telegram.constants import ParseMode
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))
WEAK_MODE = os.getenv("SERVER_WEAK_MODE", "true").lower() == "true"

if not BOT_TOKEN or BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
    print("❌ ERROR: BOT_TOKEN not found in .env file")
    print("Please edit the .env file and add your bot token")
    sys.exit(1)

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('logs/bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Site-specific configurations
SITE_CONFIGS = {
    # Working sites - simple configurations
    "streamable.com": {
        "format": "best",
        "args": ["--referer", "https://streamable.com/"]
    },
    "dai.ly": {
        "format": "best[height<=720]",
        "args": []
    },
    "twitch.tv": {
        "format": "best",
        "args": ["--add-header", "Client-ID:kimne78kx3ncx6brgo4mv6wki5h1ko"]
    },
    
    # Sites needing cookies
    "pinterest.com": {
        "format": "best",
        "args": ["--referer", "https://www.pinterest.com/"],
        "needs_cookies": True
    },
    "pin.it": {
        "format": "best",
        "args": ["--referer", "https://www.pinterest.com/"],
        "needs_cookies": True
    },
    "reddit.com": {
        "format": "best[height<=720]",
        "args": ["--user-agent", "Mozilla/5.0"],
        "needs_cookies": True
    },
    
    # Sites needing special handling
    "vimeo.com": {
        "format": "best[height<=1080]",
        "args": ["--user-agent", "Mozilla/5.0"]
    },
    "rumble.com": {
        "format": "best",
        "args": ["--user-agent", "Mozilla/5.0"]
    },
    "bilibili.com": {
        "format": "best[height<=720]",
        "args": ["--referer", "https://www.bilibili.com/"]
    },
    "ted.com": {
        "format": "best[height<=720]",
        "args": []
    }
}

def get_site_config(url):
    """Get configuration for specific site"""
    for domain, config in SITE_CONFIGS.items():
        if domain in url.lower():
            return config
    
    # Default configuration for unknown sites
    return {
        "format": "best[height<=720]",
        "args": [],
        "needs_cookies": False
    }

def clean_url(text):
    """Extract and clean URL from text"""
    if not text:
        return None
    
    text = text.strip()
    
    # Find URL pattern
    url_pattern = r'(https?://[^\s<>"\']+|www\.[^\s<>"\']+\.[a-z]{2,})'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    
    if matches:
        url = matches[0]
        if not url.startswith(('http://', 'https://')):
            url = 'https://' + url
        
        # Clean URL
        url = re.sub(r'[.,;:!?]+$', '', url)
        url = unquote(url)
        
        return url
    
    return None

def format_size(bytes_val):
    """Format file size in human readable format"""
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

async def download_with_retry(url, output_path, max_retries=3):
    """Download with multiple retry strategies"""
    
    config = get_site_config(url)
    cookies_file = "cookies/cookies.txt"
    
    # Method 1: Standard download
    retry_methods = [
        # Method 1: Standard with cookies if needed
        lambda: download_method(url, output_path, config, cookies_file),
        
        # Method 2: Simple best format
        lambda: download_simple(url, output_path),
        
        # Method 3: Audio only (fallback)
        lambda: download_audio_only(url, output_path),
    ]
    
    for retry in range(max_retries):
        method = retry_methods[min(retry, len(retry_methods) - 1)]
        
        logger.info(f"Download attempt {retry + 1} for {url[:50]}")
        success, result = await method()
        
        if success:
            return True, result
        
        if retry < max_retries - 1:
            logger.warning(f"Attempt {retry + 1} failed: {result[:100]}")
            await asyncio.sleep(2)  # Wait before retry
    
    return False, "All download attempts failed"

async def download_method(url, output_path, config, cookies_file):
    """Specific download method"""
    try:
        # Build command
        cmd = [
            "yt-dlp",
            "-f", config["format"],
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            "--config-location", "config/yt-dlp-config.conf"
        ]
        
        # Add site-specific arguments
        cmd.extend(config.get("args", []))
        
        # Add cookies if available and needed
        if config.get("needs_cookies", False) and os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
            logger.info("Using cookies file for download")
        
        # Add URL
        cmd.append(url)
        
        # Run download
        logger.info(f"Running command: {' '.join(cmd[:10])}...")
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Wait with timeout
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        except asyncio.TimeoutError:
            process.kill()
            return False, "Timeout (5 minutes)"
        
        if process.returncode == 0:
            return True, "Download successful"
        else:
            error = stderr.decode('utf-8', errors='ignore')[:200]
            return False, f"yt-dlp error: {error}"
            
    except Exception as e:
        return False, f"Command error: {str(e)}"

async def download_simple(url, output_path):
    """Simple fallback download"""
    try:
        cmd = [
            "yt-dlp",
            "-f", "best[filesize<100M]/best",
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode == 0:
            return True, "Simple download successful"
        else:
            error = stderr.decode('utf-8', errors='ignore')[:200]
            return False, f"Simple download error: {error}"
            
    except Exception as e:
        return False, f"Simple download error: {str(e)}"

async def download_audio_only(url, output_path):
    """Audio only fallback"""
    try:
        cmd = [
            "yt-dlp",
            "-f", "bestaudio",
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode == 0:
            return True, "Audio download successful"
        else:
            error = stderr.decode('utf-8', errors='ignore')[:200]
            return False, f"Audio download error: {error}"
            
    except Exception as e:
        return False, f"Audio download error: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = """
🤖 *Telegram Media Downloader Bot*

✅ *WORKING SITES:*
• Streamable (streamable.com) - ✅
• Dailymotion (dai.ly) - ✅  
• Twitch clips - ✅

⚠️ *SITES NEEDING COOKIES:*
• Pinterest (pin.it) - 🍪 Required
• Reddit - 🍪 Recommended
• Others may need cookies.txt file

🔧 *SITES WITH LIMITATIONS:*
• Vimeo, Rumble, Bilibili, TED
• May work with proper configuration

📝 *HOW TO USE:*
1. Send a media URL
2. Bot will try multiple methods
3. Receive downloaded file

⚡ *BOT FEATURES:*
• Multiple retry methods
• Auto fallback strategies
• File size limits
• Cleanup after 2 minutes

🍪 *COOKIES SETUP:*
For better results, add cookies.txt to:
/opt/telegram-media-bot/cookies/
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    original_text = update.message.text
    url = clean_url(original_text)
    
    if not url:
        await update.message.reply_text(
            "❌ *No valid URL found*\nPlease send a URL starting with http:// or https://",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Get site info
    parsed = urlparse(url)
    site = parsed.netloc.replace('www.', '')
    
    # Initial message
    msg = await update.message.reply_text(
        f"🔗 *Processing URL*\n\n"
        f"Site: *{site}*\n"
        f"URL: `{url[:50]}...`\n\n"
        f"Starting download process...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name = re.sub(r'[^\w\-_]', '_', url[:30])
    filename = f"{safe_name}_{timestamp}"
    output_template = f"downloads/{filename}.%(ext)s"
    
    # Try download
    await msg.edit_text(
        f"📥 *Downloading...*\n\n"
        f"Site: {site}\n"
        f"Attempt 1/3\n\n"
        f"Please wait...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    success, result = await download_with_retry(url, output_template, max_retries=3)
    
    if not success:
        await msg.edit_text(
            f"❌ *All download attempts failed*\n\n"
            f"Site: {site}\n"
            f"URL: `{url[:50]}...`\n\n"
            f"*Error:* {result}\n\n"
            f"*Possible solutions:*\n"
            f"• Check if URL is accessible\n"
            f"• Add cookies for this site\n"
            f"• Try a different URL\n"
            f"• Some sites block automated downloads",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Find downloaded file
    downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
    if not downloaded_files:
        await msg.edit_text(
            "❌ Download completed but file not found",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    file_path = downloaded_files[0]
    file_size = file_path.stat().st_size
    
    # Check size
    if file_size > (MAX_SIZE_MB * 1024 * 1024):
        file_path.unlink()
        await msg.edit_text(
            f"❌ *File too large*\n\n"
            f"Size: {format_size(file_size)}\n"
            f"Limit: {MAX_SIZE_MB}MB",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Upload to Telegram
    await msg.edit_text(
        f"📤 *Uploading...*\n\n"
        f"File: {file_path.name}\n"
        f"Size: {format_size(file_size)}\n\n"
        f"This may take a moment...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    try:
        with open(file_path, 'rb') as file:
            file_ext = file_path.suffix.lower()
            
            if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']:
                await update.message.reply_photo(
                    photo=file,
                    caption=f"✅ *Download Complete!*\n\n"
                           f"Site: {site}\n"
                           f"Size: {format_size(file_size)}\n"
                           f"Auto-deletes in {DELETE_AFTER} minutes",
                    parse_mode=ParseMode.MARKDOWN
                )
            elif file_ext in ['.mp3', '.m4a', '.wav', '.ogg', '.flac']:
                await update.message.reply_audio(
                    audio=file,
                    caption=f"✅ *Download Complete!*\n\n"
                           f"Site: {site}\n"
                           f"Size: {format_size(file_size)}\n"
                           f"Auto-deletes in {DELETE_AFTER} minutes",
                    parse_mode=ParseMode.MARKDOWN
                )
            else:
                await update.message.reply_video(
                    video=file,
                    caption=f"✅ *Download Complete!*\n\n"
                           f"Site: {site}\n"
                           f"Size: {format_size(file_size)}\n"
                           f"Auto-deletes in {DELETE_AFTER} minutes",
                    parse_mode=ParseMode.MARKDOWN,
                    supports_streaming=True
                )
        
        # Success message
        await msg.edit_text(
            f"🎉 *SUCCESS!*\n\n"
            f"✅ File downloaded and sent!\n"
            f"📊 Size: {format_size(file_size)}\n"
            f"⏰ Auto-deletes in {DELETE_AFTER} minutes\n\n"
            f"Ready for next URL!",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Schedule file deletion
        async def delete_file():
            await asyncio.sleep(DELETE_AFTER * 60)
            if file_path.exists():
                file_path.unlink()
                logger.info(f"Auto-deleted: {file_path.name}")
        
        asyncio.create_task(delete_file())
        
    except Exception as upload_error:
        logger.error(f"Upload error: {upload_error}")
        await msg.edit_text(
            f"❌ *Upload Failed*\n\n"
            f"Error: {str(upload_error)[:200]}\n\n"
            f"File saved at: {file_path}",
            parse_mode=ParseMode.MARKDOWN
        )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
🆘 *BOT HELP GUIDE*

📋 *How to use:*
1. Send any media URL
2. Bot tries multiple download methods
3. Receive file in Telegram

✅ *Confirmed working sites:*
• Streamable (streamable.com)
• Dailymotion (dai.ly)
• Twitch clips (twitch.tv)

⚠️ *Sites needing cookies:*
• Pinterest (pinterest.com, pin.it)
• Reddit (reddit.com)
• For these, add cookies.txt file

🔧 *Cookies setup:*
1. Install "Get cookies.txt" browser extension
2. Login to site in browser
3. Export cookies as cookies.txt
4. Upload to: /opt/telegram-media-bot/cookies/

📏 *Limits:*
• Max file size: 2000MB
• Auto-delete: 2 minutes
• Concurrent downloads: 1

🐛 *Troubleshooting:*
• Check logs: tail -f logs/bot.log
• Update yt-dlp: pip3 install --upgrade yt-dlp
• Check .env configuration
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    import psutil
    
    cpu = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    status_text = f"""
📊 *BOT STATUS REPORT*

🖥 *System Resources:*
• CPU Usage: {cpu:.1f}%
• Memory Usage: {memory.percent:.1f}%
• Free Memory: {format_size(memory.available)}
• Disk Free: {format_size(disk.free)}

🤖 *Bot Configuration:*
• Version: Complete Installer v1.0
• Max File Size: {MAX_SIZE_MB}MB
• Auto-delete: {DELETE_AFTER} minutes
• Weak Mode: {'✅ Enabled' if WEAK_MODE else '❌ Disabled'}

📁 *Directories:*
• Main: /opt/telegram-media-bot/
• Downloads: /opt/telegram-media-bot/downloads/
• Logs: /opt/telegram-media-bot/logs/
• Cookies: /opt/telegram-media-bot/cookies/

💡 *Quick Commands:*
/start - Welcome message
/help - This help guide  
/status - Bot status
"""
    await update.message.reply_text(status_text, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors in the bot"""
    logger.error(f"Bot error: {context.error}")
    
    try:
        await update.effective_message.reply_text(
            f"❌ *Bot Error*\n\nAn error occurred: `{str(context.error)[:200]}`\n\nCheck bot logs for details.",
            parse_mode=ParseMode.MARKDOWN
        )
    except:
        pass

def main():
    """Main function to run the bot"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot - Complete Installer")
    print("=" * 60)
    print(f"📁 Install directory: {INSTALL_DIR}")
    print(f"🤖 Bot token: {BOT_TOKEN[:20]}...")
    print(f"📏 Max file size: {MAX_SIZE_MB}MB")
    print(f"⏰ Auto-delete: {DELETE_AFTER} minutes")
    print("=" * 60)
    
    # Create application
    app = Application.builder().token(BOT_TOKEN).build()
    
    # Add handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    app.add_error_handler(error_handler)
    
    print("✅ Bot starting...")
    print("📱 Send /start to your bot on Telegram")
    print("🔗 Send any media URL to test")
    
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
Description=Telegram Media Downloader Bot
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=10
User=root
WorkingDirectory=/opt/telegram-media-bot
ExecStart=/usr/bin/python3 /opt/telegram-media-bot/bot.py
StandardOutput=append:/opt/telegram-media-bot/logs/bot.log
StandardError=append:/opt/telegram-media-bot/logs/bot-error.log
Environment=PATH=/usr/bin:/usr/local/bin
Environment=PYTHONUNBUFFERED=1

# Resource limits for weak servers
MemoryLimit=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable telegram-media-bot.service

# ============================================
# STEP 8: Create Management Scripts
# ============================================
print_status "Creating management scripts..."

# Start script
cat > start-bot.sh << 'EOF'
#!/bin/bash
cd /opt/telegram-media-bot
echo "Starting Telegram Media Downloader Bot..."
python3 bot.py
EOF

# Stop script
cat > stop-bot.sh << 'EOF'
#!/bin/bash
echo "Stopping Telegram Media Downloader Bot..."
systemctl stop telegram-media-bot.service
echo "Bot stopped"
EOF

# Restart script
cat > restart-bot.sh << 'EOF'
#!/bin/bash
echo "Restarting Telegram Media Downloader Bot..."
systemctl restart telegram-media-bot.service
echo "Bot restarted"
EOF

# Status script
cat > bot-status.sh << 'EOF'
#!/bin/bash
systemctl status telegram-media-bot.service
EOF

# Logs script
cat > bot-logs.sh << 'EOF'
#!/bin/bash
tail -f /opt/telegram-media-bot/logs/bot.log
EOF

# Update script
cat > update-bot.sh << 'EOF'
#!/bin/bash
echo "Updating bot components..."
cd /opt/telegram-media-bot

# Update yt-dlp
pip3 install --upgrade yt-dlp --root-user-action=ignore

# Update python-telegram-bot
pip3 install --upgrade python-telegram-bot --root-user-action=ignore

# Restart bot
systemctl restart telegram-media-bot.service
echo "✅ Bot updated and restarted"
EOF

# Make all scripts executable
chmod +x *.sh

# ============================================
# STEP 9: Create Cookies Instructions
# ============================================
cat > COOKIES_INSTRUCTIONS.md << 'EOF'
# 🍪 How to Setup Cookies for Better Downloads

## Why Cookies?
Some websites require cookies to:
- Access private/age-restricted content
- Bypass rate limits  
- Maintain login sessions

## Step-by-Step Guide:

### 1. Install Browser Extension
- Chrome: Install "Get cookies.txt" extension
- Firefox: Install "cookies.txt" extension

### 2. Get Cookies for a Site
1. Open the website (e.g., pinterest.com)
2. Login to your account (if needed)
3. Click the extension icon
4. Click "Export" or "Save as cookies.txt"

### 3. Upload to Server
```bash
# On your local computer (Linux/Mac)
scp cookies.txt root@your-server-ip:/opt/telegram-media-bot/cookies/

# Or upload via SFTP to:
# /opt/telegram-media-bot/cookies/cookies.txt
