#!/bin/bash

# =========================================================
#             اسکریپت نصب یکپارچه ربات دانلودر تلگرام
# =========================================================
# این فایل شامل کد Shell (برای نصب و اجرا) و کد Python (منطق ربات) است.

BOT_FILE="bot.py"
ENV_FILE=".env"

# ۱. به‌روزرسانی بسته‌ها و نصب پیش‌نیازها
echo "🛠️ به‌روزرسانی بسته‌های سیستمی و نصب Python، Git و Curl..."
sudo apt update
sudo apt install -y python3 python3-pip git curl

# ۲. نصب yt-dlp (ابزار کلیدی دانلود)
echo "⬇️ نصب yt-dlp برای مدیریت دانلودها..."
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp

# ۳. ایجاد محیط مجازی و نصب کتابخانه‌های پایتون
echo "🐍 ایجاد محیط مجازی و نصب کتابخانه‌های لازم..."
python3 -m venv venv
source venv/bin/activate
pip install python-telegram-bot python-dotenv

# ۴. تنظیم توکن ربات
echo "🤖 لطفاً توکن ربات تلگرام خود را وارد کنید (دریافتی از BotFather):"
read BOT_TOKEN
echo "BOT_TOKEN=$BOT_TOKEN" > $ENV_FILE
echo "توکن در فایل $ENV_FILE ذخیره شد."

# ۵. استخراج کد پایتون و ذخیره در فایل bot.py
echo "📝 استخراج و ذخیره کد منطق ربات در فایل $BOT_FILE..."
cat << 'EOF_PYTHON_CODE' > $BOT_FILE
# =========================================================
#                       bot.py (منطق ربات)
# =========================================================
import logging
import os
import subprocess
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import Application, MessageHandler, filters, ContextTypes
import asyncio
import telegram.ext

# توکن ربات را از فایل .env بارگذاری می‌کند
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")

# تنظیمات لاگ‌گیری
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# فهرست دامنه های پشتیبانی شده (توسط yt-dlp)
SUPPORTED_DOMAINS = [
    "tiktok.com", "facebook.com", "fb.watch", "terabox.com", "loom.com", 
    "streamable.com", "pinterest.com", "pin.it", "snapchat.com/spotlight"
]

# تابع Start
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """پاسخ به دستور /start."""
    welcome_message = (
        "👋 خوش آمدید! من یک ربات دانلودر هستم.\n\n"
        "لینک مورد نظر خود را از پلتفرم‌های زیر برای من ارسال کنید:\n"
        "🔸 **TikTok**\n"
        "🔸 **Facebook**\n"
        "🔸 **Terabox** (ویدیو)\n"
        "🔸 **Loom** (ویدیو)\n"
        "🔸 **Streamable**\n"
        "🔸 **Pinterest** (تصویر و ویدیو)\n"
        "🔸 **Snapchat Spotlights**\n\n"
        "**توجه:** فقط لینک‌های عمومی و بدون محدودیت دانلود می‌شوند."
    )
    await update.message.reply_text(welcome_message)

# تابع اصلی پردازش لینک و دانلود
async def handle_link(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """لینک دریافت شده را با yt-dlp دانلود کرده و فایل را می‌فرستد."""
    
    chat_id = update.message.chat_id
    link = update.message.text.strip()
    
    logger.info(f"Received link from {chat_id}: {link}")

    # بررسی لینک برای جلوگیری از پردازش غیرضروری
    if not any(domain in link.lower() for domain in SUPPORTED_DOMAINS):
        await update.message.reply_text(
            "⚠️ این دامنه پشتیبانی نمی‌شود یا لینک معتبر نیست. لطفاً یک لینک از پلتفرم‌های ذکر شده ارسال کنید."
        )
        return

    # ارسال پیام اولیه و نشان دادن وضعیت انتظار
    message = await update.message.reply_text(f"⏳ در حال پردازش لینک شما... ممکن است کمی طول بکشد.\nلینک: `{link}`", parse_mode='Markdown')
    
    # تعیین نام فایل موقت خروجی
    temp_dir = f"./downloads/{chat_id}"
    os.makedirs(temp_dir, exist_ok=True)
    # از %()s برای جلوگیری از تداخل نام‌ها و دریافت مسیر دقیق فایل استفاده می‌کنیم
    output_template = os.path.join(temp_dir, "downloaded_file.%(ext)s")
    
    downloaded_filepath = None
    
    try:
        # --- ۱. اجرای yt-dlp برای دانلود ---
        # --max-filesize 50M: محدودیت حجم (برای تلگرام)
        command = [
            "yt-dlp",
            "-f", "best",
            "--max-filesize", "50M", 
            "--restrict-filenames",
            "--no-warnings",
            "--print", "filepath", 
            link,
            "-o", output_template
        ]
        
        # اجرای دستور در ترمینال
        process = subprocess.run(command, check=True, capture_output=True, text=True)
        
        # مسیر دقیق فایل دانلود شده را از خروجی yt-dlp دریافت می‌کنیم
        downloaded_filepath = process.stdout.strip().split('\n')[-1]
        
        # --- ۲. ارسال فایل ---
        
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=message.message_id,
            text="✅ دانلود تکمیل شد. در حال ارسال فایل..."
        )
        
        # بررسی نوع فایل برای ارسال صحیح (ویدیو یا عکس)
        # استفاده از دستور file برای تشخیص نوع محتوا
        mime_type_process = subprocess.run(['file', '-b', '--mime-type', downloaded_filepath], capture_output=True, text=True, check=True)
        mime_type = mime_type_process.stdout.strip()

        if mime_type.startswith('video'):
            await context.bot.send_video(
                chat_id,
                video=open(downloaded_filepath, 'rb'),
                caption=f"🎥 دانلود از: {link}",
                supports_streaming=True
            )
        elif mime_type.startswith('image'):
            await context.bot.send_photo(
                chat_id,
                photo=open(downloaded_filepath, 'rb'),
                caption=f"🖼 دانلود از: {link}"
            )
        else:
            await context.bot.send_document(
                chat_id,
                document=open(downloaded_filepath, 'rb'),
                caption=f"📄 دانلود از: {link}"
            )

    except subprocess.CalledProcessError as e:
        error_message = f"❌ خطایی هنگام دانلود رخ داد:\n\n`{e.stderr.splitlines()[-1]}`"
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=message.message_id,
            text=error_message,
            parse_mode='Markdown'
        )
        logger.error(f"yt-dlp error: {e.stderr}")
        
    except Exception as e:
        error_message = f"❌ خطای نامشخص در ربات: {type(e).__name__}"
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=message.message_id,
            text=error_message
        )
        logger.error(f"Unknown error: {e}")

    finally:
        # --- ۳. پاکسازی فایل‌های دانلود شده ---
        if downloaded_filepath and os.path.exists(downloaded_filepath):
            os.remove(downloaded_filepath)
        # پاکسازی پوشه موقت (اگر خالی باشد)
        if os.path.exists(temp_dir) and not os.listdir(temp_dir):
            os.rmdir(temp_dir)
        
def main() -> None:
    """راه‌اندازی و اجرای ربات."""
    if not BOT_TOKEN:
        logger.error("🚨 توکن ربات (BOT_TOKEN) در فایل .env تنظیم نشده است.")
        return

    application = Application.builder().token(BOT_TOKEN).build()

    application.add_handler(telegram.ext.CommandHandler("start", start_command))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_link))

    logger.info("🟢 ربات دانلودر شروع به کار کرد. (Polling)")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
EOF_PYTHON_CODE

# ۶. اجرای ربات
echo "🚀 اجرای ربات..."

# فعال‌سازی محیط مجازی
source venv/bin/activate

# اجرای ربات در پس‌زمینه با nohup
nohup python3 $BOT_FILE &

echo ""
echo "--------------------------------------------------------"
echo "✅ نصب و اجرای ربات تکمیل شد."
echo "💡 ربات در پس‌زمینه در حال اجرا است."
echo "💡 برای مشاهده وضعیت ربات: cat nohup.out"
echo "💡 برای متوقف کردن ربات: pkill -f $BOT_FILE"
echo "--------------------------------------------------------"
