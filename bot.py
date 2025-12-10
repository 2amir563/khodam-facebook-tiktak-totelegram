#!/bin/bash
# ===========================================
# Telegram Media Downloader Bot - UNIVERSAL VERSION
# Version 7.0 - Fixed Installation Issues
# Repository: https://github.com/YOUR_USERNAME/YOUR_REPO
# ============================================

set -e  # Exit on error

echo "==============================================="
echo "🤖 Telegram Media Downloader Bot - UNIVERSAL VERSION"
echo "==============================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root or use: sudo bash install.sh"
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

print_status "Starting UNIVERSAL installation..."

# ============================================
# STEP 1: Update System
# ============================================
print_status "Updating system packages..."
apt-get update
apt-get upgrade -y

# ============================================
# STEP 2: Install System Dependencies
# ============================================
print_status "Installing system dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    ffmpeg \
    curl \
    wget \
    cron \
    nano \
    htop \
    unzip \
    pv \
    screen \
    atomicparsley \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    build-essential \
    python3-dev \
    jq \
    python3-brotli

# ============================================
# STEP 3: Create Project Directory
# ============================================
print_status "Creating project directory..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create necessary directories
mkdir -p downloads logs cookies tmp
chmod 755 downloads logs cookies tmp

# ============================================
# STEP 4: Install Python Dependencies (FIXED)
# ============================================
print_status "Installing Python dependencies..."
pip3 install --upgrade pip --root-user-action=ignore

# Install dependencies one by one to avoid conflicts
for package in \
    "python-telegram-bot==20.7" \
    "yt-dlp==2024.4.9" \
    "python-dotenv==1.0.0" \
    "aiofiles==23.2.1" \
    "psutil==5.9.8" \
    "requests==2.31.0" \
    "beautifulsoup4==4.12.3" \
    "lxml==4.9.4" \
    "pillow==10.2.0" \
    "urllib3==2.1.0" \
    "brotli==1.1.0"
do
    print_status "Installing $package..."
    pip3 install "$package" --root-user-action=ignore || print_warning "Failed to install $package, continuing..."
done

# Update yt-dlp with ALL extractors
print_status "Installing yt-dlp with ALL extractors..."
pip3 install --upgrade --force-reinstall "yt-dlp[default]" --root-user-action=ignore

# ============================================
# STEP 5: Create Configuration Files
# ============================================
print_status "Creating configuration files..."

# Create .env file
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
YTDLP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
YTDLP_MAX_DOWNLOAD_SIZE=2000M

# Bot Settings
ENABLE_QUALITY_SELECTION=false  # Disable for problematic sites
SHOW_FILE_SIZE=true
AUTO_CLEANUP=true
EOF

print_status "Created .env file with your bot token"

# Create yt-dlp config
mkdir -p ~/.config/yt-dlp
cat > ~/.config/yt-dlp/config << 'EOF'
# Universal yt-dlp configuration
--no-warnings
--ignore-errors
--no-playlist
--concurrent-fragments 2
--limit-rate 5M
--socket-timeout 30
--retries 5
--fragment-retries 5
--skip-unavailable-fragments
--extractor-retries 3
--throttled-rate 100K
--compat-options no-youtube-unavailable-videos,no-certifi,no-websockets

# For problematic sites
--extractor-args "youtube:player-client=android,web;formats=all"
--extractor-args "reddit:user-agent=Mozilla/5.0"
--extractor-args "pinterest:skip_auth_warning=true"
--extractor-args "twitch:client-id=kimne78kx3ncx6brgo4mv6wki5h1ko"
--extractor-args "bilibili:referer=https://www.bilibili.com/"

# Video formats (try in order)
--format-sort "res,fps,codec:av1,br"
--format "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"
--merge-output-format mp4

# Cookies
--cookies cookies/cookies.txt
EOF

# ============================================
# STEP 6: Create Bot Service File
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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable telegram-media-bot.service

# ============================================
# STEP 7: Download Bot File from GitHub
# ============================================
print_status "Downloading bot.py from GitHub..."
curl -sSL -o bot.py https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/bot.py

if [ ! -f "bot.py" ] || [ ! -s "bot.py" ]; then
    print_warning "Failed to download bot.py, creating local version..."
    # Create a simple bot.py locally
    cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - Simple Version
"""
import os
import sys
from dotenv import load_dotenv
from telegram.ext import Application

load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")

if not BOT_TOKEN:
    print("ERROR: BOT_TOKEN not set")
    sys.exit(1)

async def start(update, context):
    await update.message.reply_text("🤖 Bot is working! Send me a URL.")

def main():
    app = Application.builder().token(BOT_TOKEN).build()
    from telegram.ext import CommandHandler
    app.add_handler(CommandHandler("start", start))
    print("Bot starting...")
    app.run_polling()

if __name__ == "__main__":
    main()
PYEOF
fi

chmod +x bot.py

# ============================================
# STEP 8: Create Management Scripts
# ============================================
print_status "Creating management scripts..."

# Create start script
cat > start-bot.sh << 'EOF'
#!/bin/bash
cd /opt/telegram-media-bot
source .env
python3 bot.py
EOF
chmod +x start-bot.sh

# Create stop script
cat > stop-bot.sh << 'EOF'
#!/bin/bash
systemctl stop telegram-media-bot.service
echo "Bot stopped"
EOF
chmod +x stop-bot.sh

# Create restart script
cat > restart-bot.sh << 'EOF'
#!/bin/bash
systemctl restart telegram-media-bot.service
echo "Bot restarted"
EOF
chmod +x restart-bot.sh

# Create status script
cat > bot-status.sh << 'EOF'
#!/bin/bash
systemctl status telegram-media-bot.service
EOF
chmod +x bot-status.sh

# Create logs script
cat > bot-logs.sh << 'EOF'
#!/bin/bash
tail -f /opt/telegram-media-bot/logs/bot.log
EOF
chmod +x bot-logs.sh

# Create update script
cat > update-bot.sh << 'EOF'
#!/bin/bash
echo "Updating Telegram Media Downloader Bot..."
cd /opt/telegram-media-bot
git pull origin main 2>/dev/null || echo "Git not available, downloading latest bot.py..."
curl -sSL -o bot.py https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/bot.py
pip3 install --upgrade -r <(echo "python-telegram-bot==20.7
yt-dlp==2024.4.9
python-dotenv==1.0.0
aiofiles==23.2.1
psutil==5.9.8
requests==2.31.0
beautifulsoup4==4.12.3
lxml==4.9.4
pillow==10.2.0
urllib3==2.1.0
brotli==1.1.0") --root-user-action=ignore
systemctl restart telegram-media-bot.service
echo "✅ Bot updated successfully!"
EOF
chmod +x update-bot.sh

# ============================================
# STEP 9: Create Setup Files
# ============================================
print_status "Creating setup files..."

# Create cookies guide
cat > COOKIES_GUIDE.md << 'EOFGUIDE'
# 🍪 Cookies Setup Guide

Some websites require cookies for downloading:

## 📋 Websites needing cookies:
1. **Pinterest** - Required for most downloads
2. **Reddit** - Better success rate with cookies
3. **Vimeo** - For private/unlisted videos
4. **Facebook** - Required for most content
5. **Instagram** - Required for downloading
6. **YouTube** - For age-restricted content
7. **Twitch** - For clips and VODs

## 🔧 How to get cookies:
1. Install "Get cookies.txt" extension in Chrome/Firefox
2. Go to website and login
3. Export cookies and save as `cookies.txt` in `/opt/telegram-media-bot/cookies/`
EOFGUIDE

# Create README
cat > README.md << 'EOFHOWTO'
# Telegram Media Downloader Bot

## Quick Start:
1. Send /start to bot
2. Send any media URL
3. Bot will download and send file

## Management:
- `./start-bot.sh` - Start bot
- `./stop-bot.sh` - Stop bot  
- `./restart-bot.sh` - Restart bot
- `./bot-status.sh` - Check status
- `./bot-logs.sh` - View logs

## Need help? Check logs:
tail -f /opt/telegram-media-bot/logs/bot.log
EOFHOWTO

# Create uninstall script
cat > uninstall.sh << 'EOFUNINSTALL'
#!/bin/bash
echo "Uninstalling Telegram Media Downloader Bot..."

# Stop and disable service
systemctl stop telegram-media-bot.service 2>/dev/null
systemctl disable telegram-media-bot.service 2>/dev/null
rm -f /etc/systemd/system/telegram-media-bot.service
systemctl daemon-reload

# Remove installation directory
if [ -d "/opt/telegram-media-bot" ]; then
    rm -rf /opt/telegram-media-bot
fi

echo "Uninstallation complete!"
echo "Note: Downloaded files in ~/telegram-downloads/ were not removed."
EOFUNINSTALL
chmod +x uninstall.sh

# ============================================
# STEP 10: Set Permissions and Start
# ============================================
print_status "Setting permissions..."
chown -R root:root /opt/telegram-media-bot
chmod 755 /opt/telegram-media-bot/*.sh
chmod 644 /opt/telegram-media-bot/.env

print_status "Starting bot service..."
systemctl start telegram-media-bot.service

# Wait for service
sleep 3

# ============================================
# STEP 11: Verify Installation
# ============================================
if systemctl is-active --quiet telegram-media-bot.service; then
    print_status "✅ Bot service is running!"
    
    # Create test URL file
    cat > test-urls.txt << 'EOFTEST'
# Test URLs for your bot:
- YouTube: https://www.youtube.com/watch?v=dQw4w9WgXcQ
- TikTok: https://www.tiktok.com/@example/video/123456789
- Instagram: https://www.instagram.com/p/ABC123/
- Twitter: https://twitter.com/user/status/123456789
- Pinterest: https://pin.it/abc123
EOFTEST
    
    print_status "✅ Installation completed successfully!"
else
    print_warning "⚠️ Service might need manual start."
    print_info "You can start manually with: systemctl start telegram-media-bot"
fi

# ============================================
# FINAL MESSAGE
# ============================================
echo ""
echo "==============================================="
echo "📦 INSTALLATION COMPLETE"
echo "==============================================="
echo "📁 Directory: /opt/telegram-media-bot"
echo "🤖 Bot token saved in: .env"
echo "📝 Logs: logs/bot.log"
echo "🔧 Service: telegram-media-bot.service"
echo ""
echo "🚀 TO START USING:"
echo "1. Go to Telegram"
echo "2. Find your bot"
echo "3. Send /start command"
echo "4. Send any media URL"
echo ""
echo "⚙️ MANAGEMENT:"
echo "cd /opt/telegram-media-bot"
echo "./start-bot.sh    # Start"
echo "./stop-bot.sh     # Stop"
echo "./restart-bot.sh  # Restart"
echo "./bot-status.sh   # Status"
echo "./bot-logs.sh     # Logs"
echo "./update-bot.sh   # Update"
echo ""
echo "❌ UNINSTALL:"
echo "cd /opt/telegram-media-bot && ./uninstall.sh"
echo ""
echo "🐛 TROUBLESHOOTING:"
echo "tail -f logs/bot.log          # View logs"
echo "systemctl status telegram-media-bot  # Check service"
echo "nano .env                     # Edit config"
echo "==============================================="
