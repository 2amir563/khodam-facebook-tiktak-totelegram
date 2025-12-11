#!/bin/bash
# Telegram Media Downloader Bot - Complete Installer for Fresh Servers (V12 - English)

set -e

echo "=============================================="
echo "🤖 Telegram Media Downloader Bot - Universal (V12)"
echo "=============================================="
echo ""

# ... (بخش‌های چک روت، رنگ‌ها و پیام اولیه بدون تغییر) ...

# Ask for bot token
echo "🔑 Enter your bot token from @BotFather:"
read -p "📝 Bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    echo -e "\033[0;31m[✗] Bot token is required!\033[0m"
    exit 1
fi

echo -e "\033[0;32m[✓]\033[0m Starting installation on fresh server..."

# ============================================
# STEP 1: System Update & Essential Tools
# ============================================
echo -e "\033[0;32m[✓]\033[0m Updating system packages..."
apt-get update
apt-get upgrade -y

echo -e "\033[0;32m[✓]\033[0m Installing essential tools..."
apt-get install -y curl wget nano htop screen unzip pv git

# ============================================
# STEP 2: Install Python, PIP (FIXED), FFmpeg and Dependencies
# ============================================
echo -e "\033[0;32m[✓]\033[0m Checking Python installation..."

if ! command -v python3 &> /dev/null; then
    echo -e "\033[0;32m[✓]\033[0m Installing Python3..."
    apt-get install -y python3
fi

# **FIXED:** Install python3-pip explicitly
if ! command -v pip3 &> /dev/null; then
    echo -e "\033[0;32m[✓]\033[0m Installing Python3-PIP (Package Installer)..."
    apt-get install -y python3-pip
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo -e "\033[0;32m[✓]\033[0m Found $PYTHON_VERSION"

echo -e "\033[0;32m[✓]\033[0m Installing FFmpeg..."
apt-get install -y ffmpeg

# ============================================
# STEP 3: Create Project Structure
# ============================================
echo -e "\033[0;32m[✓]\033[0m Creating project directory..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

mkdir -p downloads logs cookies tmp
chmod 777 downloads logs cookies tmp

# ============================================
# STEP 4: Install Python Packages (Updated versions)
# ============================================
echo -e "\033[0;32m[✓]\033[0m Installing Python packages..."

cat > requirements.txt << 'REQEOF'
python-telegram-bot>=20.7
python-dotenv>=1.0.0
yt-dlp>=2024.4.9
aiofiles>=23.2.1
requests>=2.31.0
psutil>=5.9.8
REQEOF

python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

echo -e "\033[0;32m[✓]\033[0m Core packages installed"

# ============================================
# STEP 5: Create Configuration
# ============================================
echo -e "\033[0;32m[✓]\033[0m Creating configuration files..."

cat > .env << ENVEOF
BOT_TOKEN=${BOT_TOKEN}
MAX_FILE_SIZE=2000
DELETE_AFTER_MINUTES=2
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
ENVEOF

echo -e "\033[0;32m[✓]\033[0m Configuration created"

# ============================================
# STEP 6: Create Bot File (bot.py - V12: Geo-Bypass Fix)
# ============================================
echo -e "\033[0;32m[✓]\033[0m Creating bot main file (bot.py - V12)..."

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - UNIVERSAL VERSION (v12 - Geo-Bypass Fix)
Fixed: 'no such option: --geo-bypass-resume' error.
"""

import os
import sys
import logging
import subprocess
import asyncio
import re
from pathlib import Path
from datetime import datetime
from urllib.parse import urlparse, unquote

import psutil 
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

# Load environment
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))
USER_AGENT = os.getenv("USER_AGENT", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

if not BOT_TOKEN:
    print("ERROR: Please set BOT_TOKEN in .env file")
    print("Edit: nano /opt/telegram-media-bot/.env")
    sys.exit(1)

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('logs/bot.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

def clean_url(text):
    """Clean URL from text"""
    if not text:
        return None
    
    text = text.strip()
    url_pattern = r'(https?://[^\s<>"\']+|www\.[^\s<>"\']+\.[a-z]{2,})'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    
    if matches:
        url = matches[0]
        if not url.startswith(('http://', 'https://')):
            url = 'https://' + url
            
        url = re.sub(r'[.,;:!?]+$', '', url)
        url = unquote(url)
        
        return url
    
    return None

def format_size(bytes_val):
    """Format file size"""
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

async def download_video(url, output_path):
    """Download video using yt-dlp with advanced options and format fallback"""
    
    # V11 Fix: Removed height filter and switched to a robust format
    download_format = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
    
    cmd = [
        # V12 Fix: Use 'python3 -m yt_dlp' to ensure using pip-installed version
        "python3", "-m", "yt_dlp",
        "-f", download_format, 
        "-o", output_path,
        "--no-warnings",
        "--ignore-errors",
        "--no-playlist",
        "--concurrent-fragments", "4",
        "--limit-rate", "10M",
        # --- Advanced Options for stability and bypassing blocks ---
        "--retries", "15",
        "--fragment-retries", "15",
        "--buffer-size", "256K",
        "--user-agent", USER_AGENT, 
        "--geo-bypass-country", "US,DE,GB",
        # V12 FIX: Removed "--geo-bypass-resume" which caused the error
        "--no-check-certificate", 
        "--referer", "https://google.com/",
        "--http-chunk-size", "10M",
        # ----------------------------------------------------------------
        url
    ]
    
    # Add cookies if available
    cookies_file = "cookies/cookies.txt"
    if os.path.exists(cookies_file):
        cmd.extend(["--cookies", cookies_file])
    
    logger.info(f"Running yt-dlp for: {url}")
    
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Increased timeout to 8 minutes (480 seconds)
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=480) 
        except asyncio.TimeoutError:
            process.kill()
            logger.error(f"Download Timeout: {url}")
            return False, "Timeout (8 minutes) - Server might be too slow or file too large."
        
        if process.returncode == 0:
            return True, "Success"
        else:
            error_output = stderr.decode('utf-8', errors='ignore')
            
            # --- Better Error Parsing (V11) ---
            error_summary = "Unknown Download Error"
            
            if "HTTP Error 403" in error_output or "Forbidden" in error_output or "Access Denied" in error_output or "HTTP Error 412" in error_output:
                error_summary = "Access Denied (403/412/Blocked). Requires Cookies or Geo-bypass failed."
            elif "HTTP Error 404" in error_output or "NOT FOUND" in error_output:
                error_summary = "File Not Found (404). Check URL validity."
            elif "logged-in" in error_output or "--cookies" in error_output:
                error_summary = "Login Required (Vimeo/Private). You MUST provide cookies.txt."
            elif "Requested format is not available" in error_output:
                error_summary = "Format Not Found. The link might be broken or not a video."
            else:
                lines = [line.strip() for line in error_output.split('\n') if line.strip()]
                error_summary = lines[-1][:200] if lines else "Unknown Download Error"

            logger.error(f"yt-dlp failed for {url}: {error_output}")
            return False, f"Download error: {error_summary}"
            
    except Exception as e:
        logger.error(f"Exception during download: {e}")
        return False, f"Internal Error: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = f"""
🤖 *UNIVERSAL Media Downloader Bot - V12*

✅ *Supported Sites:*
• YouTube, TikTok, Instagram
• Facebook, Twitter/X, Reddit
• Pinterest, Vimeo, Dailymotion and many more!

📝 *How to Use:*
1. Send any media URL.
2. The bot will download and send the file.

⚡ *Features (V12 Update):*
✅ Fixed Geo-bypass error.
✅ Optimized format detection.
✅ Enhanced access handling.
✅ Automatic file deletion after {DELETE_AFTER} minutes
✅ Max file size: {MAX_SIZE_MB}MB

🍪 *Cookie Setup (CRITICAL for Vimeo/403/412):*
For sites requiring login or access (Vimeo, Private content, BiliBili):
Place your `cookies.txt` file here:
`/opt/telegram-media-bot/cookies/`
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

# ... (سایر توابع مانند handle_url، help_command، status_command و main بدون تغییر باقی می‌مانند) ...

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = f"""
🆘 *HELP GUIDE (V12)*

📋 *How to Use:*
1. Send any media URL.
2. The bot automatically handles the download.
3. Receive the file in Telegram.
4. Files are auto-deleted after {DELETE_AFTER} minutes.

🌐 *Supported Sites:*
- Almost all sites supported by yt-dlp.

⚙️ *Cookie Setup (CRITICAL for Access):*
To bypass login/access errors (like Vimeo login or BiliBili 412), you need a `cookies.txt` file.
Place it in: `/opt/telegram-media-bot/cookies/`

📏 *Limits:*
- Max file size: {MAX_SIZE_MB}MB
- Auto-delete: {DELETE_AFTER} minutes
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    
    cpu = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    status_text = f"""
📊 *BOT STATUS (V12)*

🖥 *System:*
• CPU: {cpu:.1f}%
• RAM: {memory.percent:.1f}% ({format_size(memory.available)} Free)
• Disk: {disk.percent:.1f}% ({format_size(disk.free)} Free)

🤖 *Bot:*
• Version: V12 (Geo-Bypass Fix)
• Max size: {MAX_SIZE_MB}MB
• Auto-delete: {DELETE_AFTER} min
• Status: ✅ Running

💡 *Quick Commands:*
/start - Welcome message
/help - Guide
/status - Bot status
"""
    await update.message.reply_text(status_text, parse_mode=ParseMode.MARKDOWN)


def main():
    """Main function"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot - V12 (Geo-Bypass Fix)")
    print("=" * 60)
    print(f"Token: {BOT_TOKEN[:20]}...")
    print(f"Max size: {MAX_SIZE_MB}MB")
    print(f"Auto-delete: {DELETE_AFTER} minutes")
    print("=" * 60)
    
    app = Application.builder().token(BOT_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    app.add_error_handler(error_handler)
    
    print("✅ Bot starting...")
    print("📱 Send /start to your bot")
    print("🔗 Send any URL to download")
    
    app.run_polling(
        allowed_updates=Update.ALL_TYPES,
        drop_pending_updates=True
    )

if __name__ == "__main__":
    if not os.access(__file__, os.X_OK):
        try:
            os.chmod(__file__, 0o755) 
        except Exception as e:
            pass
    main()
PYEOF

# Make bot executable
chmod +x bot.py

# ============================================
# STEP 7: Create Systemd Service (V12 Change: ExecStart updated to use python3)
# ============================================
echo -e "\033[0;32m[✓]\033[0m Creating systemd service..."

cat > /etc/systemd/system/telegram-media-bot.service << SERVICEEOF
[Unit]
Description=Telegram Media Downloader Bot
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=10
User=root
WorkingDirectory=/opt/telegram-media-bot
ExecStart=/usr/bin/python3 /opt/telegram-media-bot/bot.py
StandardOutput=append:/opt/telegram-media-bot/logs/bot.log
StandardError=append:/opt/telegram-media-bot/logs/bot-error.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable telegram-media-bot.service

# ============================================
# STEP 8: Create Management Scripts
# ============================================
echo -e "\033[0;32m[✓]\033[0m Creating management scripts..."

# ... (سایر اسکریپت‌های مدیریت بدون تغییر) ...

# ============================================
# STEP 9: Start Service
# ============================================
echo -e "\033[0;32m[✓]\033[0m Starting bot service..."
systemctl start telegram-media-bot.service
sleep 3

# ============================================
# STEP 10: Show Final Instructions
# ============================================
echo ""
echo "=============================================="
echo "🎉 INSTALLATION COMPLETE (V12)"
echo "=============================================="
echo "✅ مشکل geo-bypass-resume حل شد."
echo "✅ ربات برای استفاده از yt-dlp نصب شده توسط pip بهینه شد."
echo "💡 *مهم:* برای خطاهای لاگین/403/412، کوکی‌ها ضروری هستند."
echo "🍪 /opt/telegram-media-bot/cookies/cookies.txt"
echo "=============================================="
