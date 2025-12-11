#!/bin/bash
# Telegram Media Downloader Bot - Complete Installer for Fresh Servers (V18 - Final Stability)

set -e # Exit immediately if a command exits with a non-zero status

echo "=============================================="
echo "🤖 Telegram Media Downloader Bot - Universal (V18)"
echo "=============================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Helper functions
print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "لطفاً با دسترسی روت اجرا کنید: sudo bash install.sh"
    exit 1
fi

# Ask for bot token
echo "🔑 توکن ربات خود را از @BotFather وارد کنید:"
read -p "📝 توکن ربات: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "وارد کردن توکن ربات ضروری است!"
    exit 1
fi

print_status "شروع فرآیند نصب..."

# ============================================
# STEP 1: System Update & Essential Tools
# ============================================
print_status "به‌روزرسانی بسته‌های سیستمی..."
apt-get update -y
apt-get upgrade -y

print_status "نصب ابزارهای ضروری..."
apt-get install -y curl wget nano htop screen unzip pv git

# ============================================
# STEP 2: Install Python, PIP, and FFmpeg
# ============================================
print_status "بررسی نصب Python..."

if ! command -v python3 &> /dev/null; then
    print_status "نصب Python3..."
    apt-get install -y python3
fi

if ! command -v pip3 &> /dev/null; then
    print_status "نصب Python3-PIP..."
    apt-get install -y python3-pip
fi

print_status "نصب FFmpeg..."
apt-get install -y ffmpeg

# FIX: Remove system's youtube-dl/yt-dlp to prevent conflicts with pip version
print_status "حذف بسته‌های yt-dlp/youtube-dl سیستمی (برای جلوگیری از تداخل)..."
apt-get remove -y youtube-dl yt-dlp 2>/dev/null || true


# ============================================
# STEP 3: Create Project Structure
# ============================================
print_status "ایجاد دایرکتوری پروژه..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

mkdir -p downloads logs cookies tmp
chmod 777 downloads logs cookies tmp

# ============================================
# STEP 4: Install Python Packages & Update yt-dlp
# ============================================
print_status "نصب/به‌روزرسانی بسته‌های Python..."

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

print_status "بسته‌های اصلی با موفقیت نصب شدند."

# ============================================
# STEP 5: Create Configuration
# ============================================
print_status "ایجاد فایل‌های پیکربندی..."

cat > .env << ENVEOF
BOT_TOKEN=${BOT_TOKEN}
MAX_FILE_SIZE=2000
DELETE_AFTER_MINUTES=2
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
ENVEOF

print_status "پیکربندی ایجاد شد."

# ============================================
# STEP 6: Create Bot File (bot.py - V18: Final Stability)
# ============================================
print_status "ایجاد فایل اصلی ربات (bot.py - V18)..."

cat > bot.py << 'PYEOF'
#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - UNIVERSAL VERSION (v18 - Final Stability & Format Fallback)
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
    print("ERROR: BOT_TOKEN is missing in .env file.")
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
    """Download video using yt-dlp with optimized options (V18)"""
    
    # V18: Prioritize MP4 (video+audio), if fails, fall back to best overall stream
    download_format = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
    
    cmd = [
        "python3", "-m", "yt_dlp",
        "-f", download_format, 
        "-o", output_path,
        "--no-warnings",
        "--ignore-errors",
        "--no-playlist",
        "--concurrent-fragments", "4",
        "--limit-rate", "10M",
        # --- V18 Stable Options (Confirmed working for 6 sites) ---
        "--retries", "15",
        "--fragment-retries", "15",
        "--buffer-size", "256K",
        "--user-agent", USER_AGENT, 
        "--no-check-certificate", 
        "--referer", "https://google.com/",
        "--http-chunk-size", "10M",
        "--force-overwrite",
        # ------------------------------------
        url
    ]
    
    # Add cookies if available
    cookies_file = "cookies/cookies.txt"
    if os.path.exists(cookies_file):
        cmd.extend(["--cookies", cookies_file])
    
    logger.info(f"Initiating download for: {url}")
    
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Timeout to prevent infinite hang
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=480) 
        except asyncio.TimeoutError:
            process.kill()
            logger.error(f"Download Timeout (480s) for: {url}")
            return False, "Timeout (8 minutes) - Server might be too slow or file too large."
        
        if process.returncode == 0:
            logger.info(f"yt-dlp finished successfully for: {url}")
            return True, "Success"
        else:
            error_output = stderr.decode('utf-8', errors='ignore')
            
            # --- Better Error Parsing ---
            error_summary = "Unknown Download Error"
            
            if "The downloaded file is empty" in error_output:
                error_summary = "Downloaded file is empty (Possible Geo-Block/IP Block)"
            elif "No video formats found" in error_output:
                error_summary = "No video formats found (Incompatible URL or old extractor)"
            elif "HTTP Error 403" in error_output or "Forbidden" in error_output or "Access Denied" in error_output or "HTTP Error 412" in error_output:
                error_summary = "Access Denied (403/412/Blocked). Requires Cookies."
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
🤖 *UNIVERSAL Media Downloader Bot - V18*

✅ *سایت‌های پشتیبانی شده:*
• تقریباً تمام سایت‌های سازگار با yt-dlp.

📝 *نحوه استفاده:*
1. هر URL رسانه‌ای را بفرستید.
2. ربات فایل را دانلود و ارسال می‌کند.

⚡ *ویژگی‌ها:*
✅ حداکثر پایداری دانلود.
✅ حذف خودکار فایل‌ها بعد از {DELETE_AFTER} دقیقه
✅ حداکثر حجم فایل: {MAX_SIZE_MB}MB

🍪 *تنظیم کوکی (بسیار مهم برای دسترسی):*
برای لینک‌هایی که نیاز به ورود یا دسترسی محدود دارند (Vimeo, لینک‌های خصوصی, خطاهای 403/412):
فایل `cookies.txt` خود را در مسیر زیر قرار دهید:
`/opt/telegram-media-bot/cookies/`
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    original_text = update.message.text
    url = clean_url(original_text)
    
    if not url:
        await update.message.reply_text(
            "❌ *URL نامعتبر*\nلطفاً یک URL معتبر که با http:// یا https:// شروع می‌شود، بفرستید.",
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
    safe_name = site 
    filename = f"{safe_name}_{timestamp}"
    output_template = f"downloads/{filename}.%(ext)s"
    
    # Download
    await msg.edit_text(
        f"📥 *در حال دانلود...*\n\n"
        f"سایت: {site.upper()}\n"
        f"لطفاً صبر کنید (حداکثر 8 دقیقه)...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    success, result = await download_video(url, output_template)
    
    # If download fails, report error with more details
    if not success:
        
        if "Login Required" in result:
             error_message = (
                f"❌ *دانلود ناموفق (نیاز به ورود)*\n\n"
                f"خطا: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *راه‌حل:* این لینک خصوصی است یا نیاز به ورود دارد.\n"
                f"لطفاً فایل `cookies.txt` خود را در مسیر `/opt/telegram-media-bot/cookies/` قرار دهید."
            )
        elif "Access Denied" in result:
            error_message = (
                f"❌ *دانلود ناموفق (دسترسی مسدود شده)*\n\n"
                f"خطا: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *راه‌حل:* سرور دسترسی را رد کرده است (403/412/مسدود شده).\n"
                f"اگر لینک عمومی است، دسترسی شبکه را بررسی کنید یا `cookies.txt` را ارائه دهید."
            )
        elif "Downloaded file is empty" in result:
            error_message = (
                f"❌ *دانلود ناموفق (فایل خالی)*\n\n"
                f"خطا: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *راه‌حل:* این ممکن است به دلیل مسدودسازی شدید جغرافیایی یا محافظت ضد ربات سرور باشد.\n"
                f"با یک لینک جدید یا با `cookies.txt` دوباره امتحان کنید."
            )
        elif "No video formats found" in result:
            error_message = (
                f"❌ *دانلود ناموفق (فرمت پیدا نشد)*\n\n"
                f"خطا: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *راه‌حل:* yt-dlp نتوانست منبع ویدیو را استخراج کند. لینک ممکن است خراب باشد یا از فرمت جدید/غیرمعمولی استفاده کند. یک لینک دیگر از همان سایت امتحان کنید."
            )
        elif "File Not Found" in result:
            error_message = (
                f"❌ *دانلود ناموفق (404)*\n\n"
                f"خطا: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *راه‌حل:* URL داده شده به یک فایل/صفحه موجود اشاره نمی‌کند."
            )
        else:
             error_message = (
                f"❌ *دانلود ناموفق*\n\n"
                f"خطا: `{result}`\n\n"
                f"دلایل احتمالی:\n"
                f"• URL غیرقابل دسترسی یا خراب است.\n"
                f"• فایل کوکی (`cookies.txt`) مورد نیاز است.\n"
                f"• محتوا محدود شده است (جغرافیایی/خصوصی)."
            )

        await msg.edit_text(error_message, parse_mode=ParseMode.MARKDOWN)
        return
    
    # Find downloaded file
    downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
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
            f"❌ *حجم فایل بیش از حد مجاز است*\n\n"
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
        f"ممکن است کمی طول بکشد...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    try:
        with open(file_path, 'rb') as file:
            file_ext = file_path.suffix.lower()
            caption_text = (
                f"✅ *دانلود تکمیل شد!*\n\n"
                f"سایت: {site.upper()}\n"
                f"حجم: {format_size(file_size)}\n"
                f"حذف خودکار در {DELETE_AFTER} دقیقه"
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
            f"🎉 *موفقیت‌آمیز!*",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Auto delete after delay
        async def delete_files_after_delay():
            await asyncio.sleep(DELETE_AFTER * 60)
            for p in downloaded_files:
                if p.exists():
                    try:
                        p.unlink()
                        logger.info(f"Auto-deleted file: {p.name}")
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
🆘 *راهنمای کمک (V18)*

📋 *نحوه استفاده:*
1. هر URL رسانه‌ای را بفرستید.
2. ربات به صورت خودکار دانلود را انجام می‌دهد.
3. فایل را در تلگرام دریافت کنید.
4. فایل‌ها {DELETE_AFTER} دقیقه بعد حذف می‌شوند.

🌐 *سایت‌های پشتیبانی شده:*
- تقریباً تمام سایت‌های پشتیبانی شده توسط yt-dlp.

⚙️ *تنظیم کوکی (CRITICAL for Access):*
برای دور زدن خطاهای ورود/دسترسی و بسیاری از خطاهای دسترسی مسدود شده (403/412)، فایل `cookies.txt` خود را در: `/opt/telegram-media-bot/cookies/` قرار دهید.

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
📊 *وضعیت ربات (V18)*

🖥 *سیستم:*
• CPU: {cpu:.1f}%
• RAM: {memory.percent:.1f}% ({format_size(memory.available)} آزاد)
• دیسک: {disk.percent:.1f}% ({format_size(disk.free)} آزاد)

🤖 *ربات:*
• نسخه: V18 (پایداری نهایی)
• حداکثر حجم: {MAX_SIZE_MB}MB
• حذف خودکار: {DELETE_AFTER} دقیقه
• وضعیت: ✅ در حال اجرا

💡 *دستورات سریع:*
/start - پیام خوشامدگویی
/help - راهنما
/status - وضعیت ربات
"""
    await update.message.reply_text(status_text, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Unhandled error: {context.error}")
    if update and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "❌ یک خطای داخلی رخ داده است. لطفاً دوباره تلاش کنید.",
                parse_mode=ParseMode.MARKDOWN
            )
        except Exception as e:
            logger.error(f"Failed to send error message: {e}")

def main():
    """Main function"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot - V18 (در حال شروع)")
    print("=" * 60)
    print(f"توکن: {BOT_TOKEN[:20]}...")
    print(f"حداکثر حجم: {MAX_SIZE_MB}MB")
    print("=" * 60)
    
    app = Application.builder().token(BOT_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("status", status_command))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    app.add_error_handler(error_handler)
    
    print("✅ ربات شروع به نظرسنجی کرد...")
    
    try:
        app.run_polling(
            allowed_updates=Update.ALL_TYPES,
            drop_pending_updates=True,
            timeout=30
        )
    except Exception as e:
        logger.critical(f"ربات نتوانست شروع به نظرسنجی کند: {e}")
        sys.exit(1)


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
# STEP 7: Create Systemd Service
# ============================================
print_status "ایجاد سرویس systemd..."
# Find the exact path of python3
PYTHON_PATH=$(which python3)

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
ExecStart=${PYTHON_PATH} /opt/telegram-media-bot/bot.py
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
print_status "ایجاد اسکریپت‌های مدیریت..."

cat > start-bot.sh << 'EOF'
#!/bin/bash
systemctl start telegram-media-bot.service
echo "Bot started"
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
print_status "شروع سرویس ربات..."
systemctl start telegram-media-bot.service
sleep 3

# ============================================
# STEP 10: Show Final Instructions
# ============================================
echo ""
echo "================================================"
echo "🎉 نصب تکمیل شد (V18 - پایداری نهایی)"
echo "================================================"
echo "💡 ربات اکنون حداکثر پایداری دانلود را دارد."
echo "✅ برای حل خطاهای دسترسی (Access Denied / Login Required)، باید فایل cookies.txt را قرار دهید."
echo ""
echo "⚙️ دستورات نهایی کنترل:"
echo "------------------------------------------------"
echo "A) وضعیت سرویس:"
echo "   systemctl status telegram-media-bot"
echo "B) مشاهده لحظه‌ای لاگ‌ها:"
echo "   tail -f /opt/telegram-media-bot/logs/bot.log"
echo "------------------------------------------------"
echo "================================================"
