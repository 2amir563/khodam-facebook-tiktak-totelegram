#!/bin/bash
# ============================================
# Telegram Media Downloader Bot - SMART INSTALLER
# با تشخیص خودکار سایت‌های کارآمد و ارائه راهنمای کوکی
# ============================================

set -e  # خروج در صورت خطا

echo "=============================================="
echo "🤖 بات دانلود مدیا تلگرام - نسخه هوشمند"
echo "=============================================="
echo ""

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ لطفاً با دسترسی root اجرا کنید: sudo bash install.sh"
    exit 1
fi

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # بدون رنگ

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# دریافت توکن بات
echo "🔑 توکن بات خود را از @BotFather وارد کنید:"
echo "مثال: 1234567890:ABCdefGhIJKlmNoPQRsTUVwxyZ"
echo ""
read -p "📝 توکن بات: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "وارد کردن توکن بات الزامی است!"
    exit 1
fi

print_status "شروع نصب بر روی سرور خام..."

# ============================================
# مرحله ۱: به‌روزرسانی سیستم و نصب ابزارهای پایه
# ============================================
print_status "به‌روزرسانی پکیج‌های سیستم..."
apt-get update
apt-get upgrade -y

print_status "نصب ابزارهای ضروری سیستم..."
apt-get install -y \
    curl \
    wget \
    nano \
    screen \
    unzip \
    pv

# ============================================
# مرحله ۲: بررسی و نصب پایتون و pip
# ============================================
print_status "بررسی نصب پایتون..."

if ! command -v python3 &> /dev/null; then
    print_status "پایتون ۳ یافت نشد. در حال نصب..."
    apt-get install -y python3
fi

if ! command -v pip3 &> /dev/null; then
    print_status "pip3 یافت نشد. در حال نصب..."
    apt-get install -y python3-pip
fi

# نصب ffmpeg برای پردازش ویدیو
print_status "نصب ffmpeg..."
apt-get install -y ffmpeg

# ============================================
# مرحله ۳: ایجاد ساختار پروژه
# ============================================
print_status "ایجاد دایرکتوری پروژه..."
INSTALL_DIR="/opt/telegram-media-bot"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ایجاد دایرکتوری‌های مورد نیاز
mkdir -p downloads logs cookies tmp
chmod 755 downloads logs cookies tmp

# ============================================
# مرحله ۴: نصب پکیج‌های پایتون
# ============================================
print_status "نصب پکیج‌های پایتون..."

# ایجاد فایل requirements
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
python-dotenv==1.0.0
yt-dlp==2024.4.9
aiofiles==23.2.1
requests==2.31.0
EOF

# نصب با استفاده از pip
python3 -m pip install --upgrade pip --quiet
python3 -m pip install -r requirements.txt --quiet

print_status "✅ پکیج‌های اصلی با موفقیت نصب شدند"

# ============================================
# مرحله ۵: ایجاد فایل‌های پیکربندی
# ============================================
print_status "ایجاد فایل‌های پیکربندی..."

# ایجاد فایل .env با توکن بات
cat > .env << EOF
# تنظیمات بات تلگرام
BOT_TOKEN=${BOT_TOKEN}

# تنظیمات سرور
MAX_FILE_SIZE=2000  # مگابایت
DELETE_AFTER_MINUTES=2
CONCURRENT_DOWNLOADS=1

# تنظیمات بات
ENABLE_QUALITY_SELECTION=false
AUTO_CLEANUP=true
EOF

print_status "✅ فایل .env با توکن بات ایجاد شد"

# ============================================
# مرحله ۶: ایجاد فایل اصلی بات (هوشمند)
# ============================================
print_status "ایجاد فایل اصلی بات (نسخه هوشمند)..."

cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
بات هوشمند دانلود مدیا تلگرام
با تشخیص خودکار سایت‌های کارآمد و راهنمای کوکی
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

# بارگذاری متغیرهای محیطی
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))

if not BOT_TOKEN:
    print("❌ خطا: BOT_TOKEN در فایل .env یافت نشد")
    print("لطفاً فایل .env را ویرایش کنید و توکن بات را اضافه کنید")
    sys.exit(1)

# راه‌اندازی لاگ‌گیری
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('logs/bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# دسته‌بندی سایت‌ها بر اساس قابلیت دانلود
SITE_CATEGORIES = {
    "working": {
        "sites": ["streamable.com", "dai.ly", "twitch.tv"],
        "description": "✅ بدون نیاز به کوکی کار می‌کنند"
    },
    "needs_cookies": {
        "sites": ["pinterest.com", "pin.it", "reddit.com", "rumble.com"],
        "description": "🍪 نیاز به فایل cookies.txt دارند"
    },
    "needs_special_config": {
        "sites": ["bilibili.com", "vimeo.com", "ted.com"],
        "description": "⚙️ نیاز به تنظیمات خاص دارند"
    }
}

def categorize_site(url):
    """دسته‌بندی سایت بر اساس URL"""
    for category, info in SITE_CATEGORIES.items():
        for site in info["sites"]:
            if site in url.lower():
                return category, site
    return "unknown", "سایت ناشناخته"

def clean_url(text):
    """استخراج و تمیز کردن URL از متن"""
    if not text:
        return None
    
    text = text.strip()
    
    # الگوی پیدا کردن URL
    url_pattern = r'(https?://[^\s<>"\']+|www\.[^\s<>"\']+\.[a-z]{2,})'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    
    if matches:
        url = matches[0]
        if not url.startswith(('http://', 'https://')):
            url = 'https://' + url
        
        # تمیز کردن URL
        url = re.sub(r'[.,;:!?]+$', '', url)
        url = unquote(url)
        
        return url
    
    return None

def format_size(bytes_val):
    """فرمت‌بندی حجم فایل به صورت قابل خواندن"""
    if bytes_val is None:
        return "نامشخص"
    
    try:
        bytes_val = float(bytes_val)
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_val < 1024.0:
                return f"{bytes_val:.1f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:.1f} TB"
    except:
        return "نامشخص"

async def download_for_working_sites(url, output_path):
    """دانلود برای سایت‌هایی که بدون کوکی کار می‌کنند"""
    try:
        cmd = [
            "yt-dlp",
            "-f", "best[height<=720]/best",
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            "--concurrent-fragments", "1",
            url
        ]
        
        logger.info(f"در حال دانلود از سایت کارآمد: {' '.join(cmd[:8])}...")
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=180)
        except asyncio.TimeoutError:
            process.kill()
            return False, "وقفه (۳ دقیقه)"
        
        if process.returncode == 0:
            return True, "دانلود موفق"
        else:
            error = stderr.decode('utf-8', errors='ignore')[:200]
            return False, f"خطا: {error}"
            
    except Exception as e:
        return False, f"خطای دستور: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """پردازش دستور /start"""
    welcome = """
🤖 *بات هوشمند دانلود مدیا تلگرام*

🎯 *سایت‌های تأیید شده (بدون نیاز به کوکی):*
✅ Streamable (streamable.com)
✅ Dailymotion (dai.ly)  
✅ Twitch clips (twitch.tv)

⚠️ *سایت‌های نیازمند کوکی:*
🍪 Pinterest (pinterest.com, pin.it)
🍪 Reddit (reddit.com)
🍪 Rumble (rumble.com)

⚡ *ویژگی‌های بات:*
• دانلود خودکار از سایت‌های کارآمد
• راهنمای کامل برای سایت‌های نیازمند کوکی
• محدودیت حجم فایل: ۲۰۰۰ مگابایت
• حذف خودکار پس از ۲ دقیقه

📝 *نحوه استفاده:*
۱. یک لینک مدیا ارسال کنید
۲. بات نوع سایت را تشخیص می‌دهد
۳. در صورت نیاز راهنمای کوکی دریافت می‌کنید
۴. برای سایت‌های کارآمد، فایل دانلود می‌شود
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """پردازش لینک‌های ارسالی"""
    original_text = update.message.text
    url = clean_url(original_text)
    
    if not url:
        await update.message.reply_text(
            "❌ *لینک معتبری یافت نشد*\nلطفاً یک لینک با http:// یا https:// ارسال کنید",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # تشخیص نوع سایت
    category, site_name = categorize_site(url)
    
    if category == "working":
        # سایت‌های کارآمد - مستقیم دانلود می‌شوند
        msg = await update.message.reply_text(
            f"🔗 *سایت کارآمد شناسایی شد*\n\n"
            f"سایت: *{site_name}*\n"
            f"وضعیت: ✅ بدون نیاز به کوکی\n\n"
            f"در حال دانلود...",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # تولید نام فایل
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_name = re.sub(r'[^\w\-_]', '_', url[:30])
        filename = f"{safe_name}_{timestamp}"
        output_template = f"downloads/{filename}.%(ext)s"
        
        # دانلود
        success, result = await download_for_working_sites(url, output_template)
        
        if not success:
            await msg.edit_text(
                f"❌ *دانلود ناموفق*\n\n"
                f"سایت: {site_name}\n"
                f"خطا: {result}",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        # پیدا کردن فایل دانلود شده
        downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
        if not downloaded_files:
            await msg.edit_text(
                "❌ دانلود کامل شد اما فایل یافت نشد",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        file_path = downloaded_files[0]
        file_size = file_path.stat().st_size
        
        # بررسی حجم
        if file_size > (MAX_SIZE_MB * 1024 * 1024):
            file_path.unlink()
            await msg.edit_text(
                f"❌ *حجم فایل بسیار زیاد*\n\n"
                f"حجم: {format_size(file_size)}\n"
                f"حداکثر مجاز: {MAX_SIZE_MB}MB",
                parse_mode=ParseMode.MARKDOWN
            )
            return
        
        # آپلود به تلگرام
        await msg.edit_text(
            f"📤 *در حال آپلود...*\n\n"
            f"فایل: {file_path.name}\n"
            f"حجم: {format_size(file_size)}",
            parse_mode=ParseMode.MARKDOWN
        )
        
        try:
            with open(file_path, 'rb') as file:
                await update.message.reply_video(
                    video=file,
                    caption=f"✅ *دانلود کامل شد!*\n\n"
                           f"سایت: {site_name}\n"
                           f"حجم: {format_size(file_size)}\n"
                           f"حذف خودکار پس از {DELETE_AFTER} دقیقه",
                    parse_mode=ParseMode.MARKDOWN,
                    supports_streaming=True
                )
            
            await msg.edit_text(
                f"🎉 *موفقیت!*\n\n"
                f"✅ فایل دانلود و ارسال شد!\n"
                f"📊 حجم: {format_size(file_size)}\n"
                f"⏰ حذف خودکار پس از {DELETE_AFTER} دقیقه",
                parse_mode=ParseMode.MARKDOWN
            )
            
            # زمان‌بندی حذف فایل
            async def delete_file():
                await asyncio.sleep(DELETE_AFTER * 60)
                if file_path.exists():
                    file_path.unlink()
                    logger.info(f"فایل حذف شد: {file_path.name}")
            
            asyncio.create_task(delete_file())
            
        except Exception as upload_error:
            logger.error(f"خطای آپلود: {upload_error}")
            await msg.edit_text(
                f"❌ *خطای آپلود*\n\n{str(upload_error)[:200]}",
                parse_mode=ParseMode.MARKDOWN
            )
    
    elif category == "needs_cookies":
        # سایت‌های نیازمند کوکی - راهنمای کامل
        cookie_guide = f"""
🍪 *سایت نیازمند کوکی شناسایی شد*

سایت: *{site_name}*
وضعیت: 🔒 نیاز به احراز هویت

📋 *مراحل راه‌اندازی کوکی:*

۱. *روی کامپیوتر شخصی:*
   • افزونه «Get cookies.txt» را در کروم/فایرفاکس نصب کنید
   • به سایت {site_name} بروید و وارد حساب خود شوید
   • روی افزونه کلیک کنید → Export cookies
   • فایل را با نام `cookies.txt` ذخیره کنید

۲. *آپلود به سرور:*
```bash
# در ترمینال کامپیوتر شخصی
scp cookies.txt root@آیپی-سرور:/opt/telegram-media-bot/cookies/
