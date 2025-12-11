#!/bin/bash
# Telegram Media Downloader Bot - Complete Installer for Fresh Servers
# Compatible with Ubuntu/Debian fresh installations (Modified Version)

set -e # Exit on error

echo "=============================================="
echo "🤖 Telegram Media Downloader Bot - Universal (V8)"
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
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Ask for bot token
echo "🔑 Enter your bot token from @BotFather:"
read -p "📝 Bot token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "Bot token is required!"
    exit 1
fi

print_status "Starting installation on fresh server..."

# ============================================
# STEP 1: System Update & Essential Tools
# ============================================
print_status "Updating system packages..."
apt-get update
apt-get upgrade -y

print_status "Installing essential tools..."
apt-get install -y curl wget nano htop screen unzip pv git

# ============================================
# STEP 2: Install Python, FFmpeg and Dependencies
# ============================================
print_status "Checking Python installation..."

# Install Python if not exists
if ! command -v python3 &> /dev/null; then
    print_status "Installing Python3..."
    apt-get install -y python3 python3-pip
fi

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1)
print_status "Found $PYTHON_VERSION"

# Install FFmpeg
print_status "Installing FFmpeg..."
apt-get install -y ffmpeg

# ============================================
# STEP 3: Create Project Structure
# ============================================
print_status "Creating project directory..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create directories
mkdir -p downloads logs cookies tmp
chmod 777 downloads logs cookies tmp # Increased permissions for easier debugging

# ============================================
# STEP 4: Install Python Packages (Updated with psutil)
# ============================================
print_status "Installing Python packages..."

# Create requirements file with *LATEST* versions for better compatibility
cat > requirements.txt << 'REQEOF'
python-telegram-bot>=20.7
python-dotenv>=1.0.0
yt-dlp>=2024.4.9 # Using a recent version
aiofiles>=23.2.1
requests>=2.31.0
psutil>=5.9.8 # Added for /status command
REQEOF

# Install packages
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

print_status "✅ Core packages installed"

# ============================================
# STEP 5: Create Configuration
# ============================================
print_status "Creating configuration files..."

# Create .env file
cat > .env << ENVEOF
BOT_TOKEN=${BOT_TOKEN}
MAX_FILE_SIZE=2000
DELETE_AFTER_MINUTES=2
# Added for yt-dlp to bypass some blocks
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
ENVEOF

print_status "✅ Configuration created"

# ============================================
# STEP 6: Create Bot File (Writing the full, updated bot.py)
# ============================================
print_status "Creating bot main file (bot.py)..."

# --- Start of the main bot.py content ---

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - UNIVERSAL VERSION (v8 - Optimized for Access/Errors)
Fixed installation issues - Simple and reliable
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

import psutil # For /status command
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
USER_AGENT = os.getenv("USER_AGENT", "Mozilla/5.0 (compatible; My-TG-Bot/1.0)") # Use a better default

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
    
    # Find URL pattern (modified to be more flexible)
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
    """Download video using yt-dlp with advanced options"""
    try:
        cmd = [
            "yt-dlp",
            # Use format best[height<=720]/best (Keep existing)
            "-f", "best[height<=720]/best", 
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            "--concurrent-fragments", "2",
            "--limit-rate", "5M",
            # --- Advanced Options for stability and bypassing blocks ---
            "--retries", "3", # Retry up to 3 times on temporary network errors
            "--buffer-size", "128K", # Set buffer size
            "--user-agent", USER_AGENT, # Set the user agent from .env
            "--geo-bypass", # Bypass geographic restrictions
            "--no-check-certificate", # Ignore SSL certificate errors (helpful sometimes)
            # -----------------------------------------------------------
            url
        ]
        
        # Add cookies if available
        cookies_file = "cookies/cookies.txt"
        if os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
        
        logger.info(f"Running yt-dlp for: {url}")
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Increased timeout to 5 minutes (300 seconds)
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=400) 
        except asyncio.TimeoutError:
            process.kill()
            logger.error(f"Download Timeout: {url}")
            return False, "Timeout (6.6 minutes) - Try again later or check URL."
        
        if process.returncode == 0:
            return True, "Success"
        else:
            error_output = stderr.decode('utf-8', errors='ignore')
            # Look for specific error lines
            if "HTTP Error 403" in error_output or "Forbidden" in error_output or "Blocked" in error_output:
                error_summary = "Access Denied (403/Blocked). Try adding cookies.txt."
            elif "HTTP Error 404" in error_output or "NOT FOUND" in error_output:
                error_summary = "File Not Found (404). Check URL validity."
            elif "KeyError" in error_output:
                error_summary = "Extractor Error (KeyError). Try updating yt-dlp or report bug."
            else:
                error_summary = error_output.split('\n')[-2].strip()[:200] if error_output.strip() else "Unknown Download Error"

            logger.error(f"yt-dlp failed for {url}: {error_output}")
            return False, f"Download error: {error_summary}"
            
    except Exception as e:
        logger.error(f"Exception during download: {e}")
        return False, f"Internal Error: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = f"""
🤖 *UNIVERSAL Media Downloader Bot - V8*

✅ *سایت‌های پشتیبانی شده:*
• یوتیوب، تیک‌تاک، اینستاگرام
• فیس‌بوک، توییتر/ایکس، ردیت
• پینترست، ویمئو، دِیلی‌موشن و بسیاری دیگر!

📝 *نحوه استفاده:*
1. هر URL رسانه‌ای را بفرستید.
2. ربات دانلود کرده و فایل را ارسال می‌کند.

⚡ *ویژگی‌ها:*
✅ دانلود خودکار و سریع
✅ نمایش حجم فایل
✅ حذف خودکار فایل‌ها پس از {DELETE_AFTER} دقیقه
✅ حداکثر حجم فایل: {MAX_SIZE_MB}MB

🍪 *تنظیم کوکی:*
برای سایت‌هایی مانند اینستاگرام، پینترست و ردیت (برای دور زدن محدودیت‌های ۴۰۳)، فایل `cookies.txt` را در مسیر زیر قرار دهید:
`/opt/telegram-media-bot/cookies/`
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    original_text = update.message.text
    url = clean_url(original_text)
    
    if not url:
        await update.message.reply_text(
            "❌ *URL نامعتبر*\nلطفاً یک URL معتبر که با http:// یا https:// شروع می‌شود ارسال کنید.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Detect site
    try:
        parsed = urlparse(url)
        site_name = parsed.netloc.split('.')[-2] if parsed.netloc.count('.') >= 2 else parsed.netloc.split('.')[0]
        site = site_name.replace('www.', '').split(':')[0]
    except:
        site = "Unknown"
    
    # Initial message
    msg = await update.message.reply_text(
        f"🔗 *در حال پردازش URL*\n\n"
        f"سایت: *{site.upper()}*\n"
        f"URL: `{url[:50]}...`\n\n"
        f"شروع دانلود...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    # Use only the domain name for safe_name for simplicity
    safe_name = site 
    filename = f"{safe_name}_{timestamp}"
    output_template = f"downloads/{filename}.%(ext)s"
    
    # Download
    await msg.edit_text(
        f"📥 *در حال دانلود...*\n\n"
        f"سایت: {site.upper()}\n"
        f"لطفاً منتظر بمانید...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    success, result = await download_video(url, output_template)
    
    # If download fails, report error with more details
    if not success:
        await msg.edit_text(
            f"❌ *دانلود ناموفق*\n\n"
            f"خطا: `{result}`\n\n"
            f"دلایل احتمالی:\n"
            f"• URL در دسترس نیست.\n"
            f"• نیاز به فایل `cookies.txt` برای این سایت است (مانند Pinterest/Reddit).\n"
            f"• محتوای محدود شده (Region/Private).",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Find downloaded file
    # glob to find all files starting with our prefix
    downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
    
    # Sort files to potentially find the main video/media file first
    downloaded_files.sort(key=lambda p: p.stat().st_size, reverse=True)
    
    if not downloaded_files:
        await msg.edit_text(
            "❌ دانلود تکمیل شد اما فایل نهایی پیدا نشد.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    file_path = downloaded_files[0]
    file_size = file_path.stat().st_size
    
    # Check size
    if file_size > (MAX_SIZE_MB * 1024 * 1024):
        # Clean up all related downloaded files
        for p in downloaded_files:
            if p.exists():
                p.unlink()
        
        await msg.edit_text(
            f"❌ *فایل بیش از حد بزرگ است*\n\n"
            f"حجم: {format_size(file_size)}\n"
            f"محدودیت: {MAX_SIZE_MB}MB",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Upload to Telegram
    await msg.edit_text(
        f"📤 *در حال آپلود...*\n\n"
        f"فایل: {file_path.name}\n"
        f"حجم: {format_size(file_size)}\n\n"
        f"این ممکن است کمی طول بکشد...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    try:
        with open(file_path, 'rb') as file:
            file_ext = file_path.suffix.lower()
            caption_text = (
                f"✅ *دانلود موفقیت‌آمیز!*\n\n"
                f"سایت: {site.upper()}\n"
                f"حجم: {format_size(file_size)}\n"
                f"حذف خودکار پس از {DELETE_AFTER} دقیقه"
            )
            
            # Smart media type detection
            if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']:
                await update.message.reply_photo(photo=file, caption=caption_text, parse_mode=ParseMode.MARKDOWN)
            elif file_ext in ['.mp3', '.m4a', '.wav', '.ogg', '.flac']:
                await update.message.reply_audio(audio=file, caption=caption_text, parse_mode=ParseMode.MARKDOWN)
            else: # Default to video (covers mp4, webm, etc.)
                await update.message.reply_video(
                    video=file, 
                    caption=caption_text, 
                    parse_mode=ParseMode.MARKDOWN,
                    supports_streaming=True
                )
        
        # Final status update
        await msg.edit_text(
            f"🎉 *عملیات موفقیت‌آمیز!*\n\n"
            f"✅ فایل دانلود و ارسال شد!\n"
            f"📊 حجم: {format_size(file_size)}\n"
            f"⏰ حذف خودکار در {DELETE_AFTER} دقیقه\n\n"
            f"آماده برای URL بعدی!",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Auto delete after delay
        async def delete_files_after_delay():
            await asyncio.sleep(DELETE_AFTER * 60)
            for p in downloaded_files:
                if p.exists():
                    try:
                        p.unlink()
                        logger.info(f"Auto-deleted: {p.name}")
                    except Exception as e:
                        logger.error(f"Failed to delete {p.name}: {e}")

        asyncio.create_task(delete_files_after_delay())
        
    except Exception as upload_error:
        logger.error(f"Upload error: {upload_error}")
        await msg.edit_text(
            f"❌ *آپلود ناموفق*\n\n"
            f"خطا: {str(upload_error)[:200]}",
            parse_mode=ParseMode.MARKDOWN
        )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = f"""
🆘 *راهنمای کمک*

📋 *نحوه استفاده:*
1. URL رسانه‌ای را ارسال کنید.
2. ربات دانلود کرده و فایل را ارسال می‌کند.

🌐 *سایت‌های پشتیبانی شده:*
- تقریباً تمام سایت‌هایی که توسط yt-dlp پشتیبانی می‌شوند (مانند YouTube, TikTok, Reddit, Pinterest, Vimeo).

⚙️ *تنظیم کوکی:*
برای رفع خطاهای دسترسی (مانند ۴۰۳ در Pinterest/Reddit) نیاز است.
فایل `cookies.txt` را در مسیر زیر قرار دهید:
`/opt/telegram-media-bot/cookies/`

📏 *محدودیت‌ها:*
- حداکثر حجم فایل: {MAX_SIZE_MB}MB
- حذف خودکار: {DELETE_AFTER} دقیقه
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    
    cpu = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    status_text = f"""
📊 *وضعیت ربات*

🖥 *سیستم:*
• CPU: {cpu:.1f}%
• RAM: {memory.percent:.1f}% ({format_size(memory.available)} آزاد)
• دیسک: {disk.percent:.1f}% ({format_size(disk.free)} آزاد)

🤖 *ربات:*
• نسخه: V8 (Optimized)
• حداکثر حجم: {MAX_SIZE_MB}MB
• حذف خودکار: {DELETE_AFTER} دقیقه
• وضعیت: ✅ فعال

💡 *دستورات سریع:*
/start - پیام خوش‌آمد
/help - راهنما
/status - وضعیت ربات
"""
    await update.message.reply_text(status_text, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Unhandled error: {context.error}")
    # Prevent sending reply if the original message is already gone or in an invalid state
    if update and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "❌ یک خطای داخلی رخ داد. لطفاً دوباره تلاش کنید.",
                parse_mode=ParseMode.MARKDOWN
            )
        except Exception as e:
            logger.error(f"Failed to send error message: {e}")

def main():
    """Main function"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot - V8")
    print("=" * 60)
    print(f"Token: {BOT_TOKEN[:20]}...")
    print(f"Max size: {MAX_SIZE_MB}MB")
    print(f"Auto-delete: {DELETE_AFTER} minutes")
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
    print("📱 Send /start to your bot")
    print("🔗 Send any URL to download")
    
    app.run_polling(
        allowed_updates=Update.ALL_TYPES,
        drop_pending_updates=True
    )

if __name__ == "__main__":
    # Ensure correct execution permissions on the script itself if run manually
    if not os.access(__file__, os.X_OK):
        try:
            os.chmod(__file__, 0o755) # Add executable permission
        except Exception as e:
            pass # Ignore if it fails
    main()

PYEOF
# --- End of the main bot.py content ---

# Make bot executable
chmod +x bot.py

# ============================================
# STEP 7: Create Systemd Service (Same as before, still reliable)
# ============================================
print_status "Creating systemd service..."

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
# STEP 8: Create Management Scripts (Same as before)
# ============================================
print_status "Creating management scripts..."

# ... (Scripts start-bot.sh, stop-bot.sh, restart-bot.sh, bot-status.sh, bot-logs.sh remain the same) ...
cat > start-bot.sh << 'EOF'
#!/bin/bash
cd /opt/telegram-media-bot
python3 bot.py
EOF

cat > stop-bot.sh << 'EOF'
#!/bin/bash
systemctl stop telegram-media-bot.service
echo "Bot stopped"
EOF

cat > restart-bot.sh << 'EOF'
#!/bin/bash
systemctl restart telegram-media-bot.service
echo "Bot restarted"
EOF

cat > bot-status.sh << 'EOF'
#!/bin/bash
systemctl status telegram-media-bot.service
EOF

cat > bot-logs.sh << 'EOF'
#!/bin/bash
tail -f /opt/telegram-media-bot/logs/bot.log
EOF

chmod +x *.sh

# ============================================
# STEP 9: Start Service
# ============================================
print_status "Starting bot service..."
systemctl start telegram-media-bot.service
sleep 3

# ============================================
# STEP 10: Show Final Instructions
# ============================================
echo ""
echo "=============================================="
echo "🎉 INSTALLATION COMPLETE (V8)"
echo "=============================================="
echo "📁 Directory: /opt/telegram-media-bot"
echo "🤖 Bot token saved in: .env"
echo "📝 Logs: logs/bot.log"
echo ""
echo "💡 *نکته مهم:* برای لینک‌هایی که خطای 403 (Forbidden) می‌دهند (مثل Pinterest/Reddit)، لطفاً فایل کوکی‌های خود را در مسیر زیر قرار دهید:"
echo "🍪 /opt/telegram-media-bot/cookies/cookies.txt"
echo ""
echo "🚀 TO START USING:"
echo "1. Go to Telegram and send /start"
echo ""
echo "⚙️ MANAGEMENT:"
echo "cd /opt/telegram-media-bot"
echo "./start-bot.sh    # Start"
echo "./stop-bot.sh     # Stop"
echo "./restart-bot.sh  # Restart"
echo "./bot-status.sh   # Status"
echo "./bot-logs.sh     # Logs"
echo "=============================================="
