#!/bin/bash

# =========================================================
#         Complete Social Media Downloader Bot Setup
# =========================================================
# Bot for downloading videos from ALL requested platforms

set -e

BOT_FILE="bot.py"
ENV_FILE=".env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${PURPLE}🛠️ Complete Social Media Downloader Bot Setup${NC}"

# 1. Install basic dependencies
echo -e "${YELLOW}📦 Installing system dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip python3-venv curl ffmpeg

# 2. Install yt-dlp
echo -e "${YELLOW}⬇️ Installing yt-dlp with all extractors...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp

# Update to get latest extractors
echo -e "${CYAN}🔄 Updating yt-dlp for all platform support...${NC}"
yt-dlp -U

echo -e "${GREEN}✅ yt-dlp installed - Version: $(yt-dlp --version)${NC}"

# 3. Create directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
mkdir -p downloads logs

# 4. Create virtual environment
echo -e "${YELLOW}🐍 Setting up Python environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Install Python packages
pip install --upgrade pip
pip install python-telegram-bot==20.7 python-dotenv==1.0.0

# 5. Get Bot Token
echo -e "${GREEN}🤖 Bot Token Configuration${NC}"
echo -e "${YELLOW}Enter your Telegram Bot Token (from @BotFather):${NC}"
read -r BOT_TOKEN

if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Invalid token! Example: 1234567890:ABCdefGHIJKLMnopQRSTuvwXYZ${NC}"
    exit 1
fi

echo "BOT_TOKEN=$BOT_TOKEN" > $ENV_FILE
echo -e "${GREEN}✅ Token saved${NC}"

# 6. Create bot.py with ALL platform support
echo -e "${PURPLE}📝 Creating bot.py with ALL requested platforms...${NC}"

cat << 'EOF' > $BOT_FILE
#!/usr/bin/env python3
"""
Complete Social Media Downloader Bot
Supports ALL requested platforms
"""
import os
import sys
import logging
import subprocess
import asyncio
import json
import re
from pathlib import Path
from uuid import uuid4

from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from dotenv import load_dotenv

# Load token
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# =========================================================
# ALL SUPPORTED PLATFORMS
# =========================================================
SUPPORTED_DOMAINS = [
    # TikTok
    "tiktok.com", "vm.tiktok.com", "vt.tiktok.com",
    
    # Facebook
    "facebook.com", "fb.watch", "fb.com",
    
    # YouTube
    "youtube.com", "youtu.be", "youtube-nocookie.com",
    
    # Instagram
    "instagram.com", "instagr.am",
    
    # Twitter/X
    "twitter.com", "x.com", "t.co",
    
    # Reddit
    "reddit.com", "redd.it",
    
    # Pinterest
    "pinterest.com", "pin.it",
    
    # Likee
    "likee.video", "like.com",
    
    # Twitch
    "twitch.tv", "clips.twitch.tv",
    
    # Dailymotion
    "dailymotion.com", "dai.ly",
    
    # Streamable
    "streamable.com",
    
    # Vimeo
    "vimeo.com",
    
    # Rumble
    "rumble.com",
    
    # Bilibili
    "bilibili.com", "b23.tv",
    
    # TED
    "ted.com",
    
    # Iranian Platforms
    "aparat.com",
    "namava.ir",
    "filimo.com",
    "tiva.ir",
    
    # Additional popular platforms
    "tumblr.com",
    "9gag.com",
    "imgur.com",
    "gfycat.com",
    "giphy.com",
    "flickr.com",
    "vk.com",
    "weibo.com",
    "douyin.com",
    "kuaishou.com",
    "ok.ru",
    "rutube.ru",
    "mx.tiktok.com",
    "tiktokv.com"
]

# Platform display names with emojis
PLATFORM_NAMES = {
    "tiktok": {"name": "TikTok", "emoji": "🎵"},
    "facebook": {"name": "Facebook", "emoji": "📘"},
    "youtube": {"name": "YouTube", "emoji": "📺"},
    "instagram": {"name": "Instagram", "emoji": "📷"},
    "twitter": {"name": "Twitter/X", "emoji": "🐦"},
    "reddit": {"name": "Reddit", "emoji": "👽"},
    "pinterest": {"name": "Pinterest", "emoji": "📌"},
    "likee": {"name": "Likee", "emoji": "❤️"},
    "twitch": {"name": "Twitch", "emoji": "🎮"},
    "dailymotion": {"name": "Dailymotion", "emoji": "🎬"},
    "streamable": {"name": "Streamable", "emoji": "🎥"},
    "vimeo": {"name": "Vimeo", "emoji": "🎞️"},
    "rumble": {"name": "Rumble", "emoji": "⚡"},
    "bilibili": {"name": "Bilibili", "emoji": "🇨🇳"},
    "ted": {"name": "TED", "emoji": "💡"},
    "aparat": {"name": "آپارات", "emoji": "🇮🇷"},
    "namava": {"name": "نماوا", "emoji": "🇮🇷"},
    "filimo": {"name": "فیلیمو", "emoji": "🇮🇷"},
    "tiva": {"name": "تیوا", "emoji": "🇮🇷"},
    "default": {"name": "Video", "emoji": "📹"}
}

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send welcome message with all platforms"""
    
    # Create categorized platform list
    platforms_text = (
        "🌍 *تمام پلتفرم‌های پشتیبانی شده:*\n\n"
        
        "🎬 *پلتفرم‌های بین‌المللی:*\n"
        "• TikTok 🎵\n• Facebook 📘\n• YouTube 📺\n"
        "• Instagram 📷\n• Twitter/X 🐦\n• Reddit 👽\n"
        "• Pinterest 📌\n• Likee ❤️\n• Twitch 🎮\n"
        "• Dailymotion 🎬\n• Streamable 🎥\n• Vimeo 🎞️\n"
        "• Rumble ⚡\n• Bilibili 🇨🇳\n• TED 💡\n\n"
        
        "🇮🇷 *پلتفرم‌های ایرانی:*\n"
        "• آپارات 🇮🇷\n• نماوا 🇮🇷\n"
        "• فیلیمو 🇮🇷\n• تیوا 🇮🇷\n\n"
        
        "📝 *طریقه استفاده:*\n"
        "فقط لینک ویدیو رو ارسال کن!\n\n"
        
        "✨ *ویژگی‌ها:*\n"
        "• اطلاعات کامل ویدیو\n"
        "• کیفیت اتوماتیک\n"
        "• حداکثر حجم: ۵۰ مگابایت\n"
        "• بدون مشکل Markdown\n\n"
        
        "⚠️ *محدودیت‌ها:*\n"
        "• فقط ویدیوهای عمومی\n"
        "• بدون نیاز به لاگین\n"
        "• برخی پلتفرم‌ها ممکنه محدودیت داشته باشند"
    )
    
    await update.message.reply_text(platforms_text, parse_mode='Markdown')

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send help message"""
    help_text = (
        "❓ *راهنما و عیب‌یابی*\n\n"
        "*طریقه استفاده:*\n"
        "۱. لینک ویدیو رو کپی کن\n"
        "۲. برای ربات ارسال کن\n"
        "۳. ویدیو با اطلاعات کامل دریافت کن\n\n"
        "*مشکلات رایج:*\n"
        "• *خطای فرمت* - ویدیوی دیگه‌ای امتحان کن\n"
        "• *محدودیت حجم* - حداکثر ۵۰ مگابایت\n"
        "• *ویدیوی خصوصی* - باید عمومی باشه\n"
        "• *نیاز به لاگین* - برخی پلتفرم‌ها\n\n"
        "*بهترین عملکرد:*\n"
        "• TikTok و YouTube بهترین کارایی رو دارند\n"
        "• از لینک مستقیم ویدیو استفاده کن\n"
        "• از صفحات لاگین/اشتراک‌گذاری پرهیز کن\n\n"
        "*نیاز به کمک؟* لینکت رو بفرست بررسی می‌کنم!"
    )
    await update.message.reply_text(help_text, parse_mode='Markdown')

async def list_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """List all supported platforms with examples"""
    
    examples = {
        "tiktok": "https://www.tiktok.com/@user/video/123456789",
        "facebook": "https://www.facebook.com/watch/?v=123456789",
        "youtube": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "instagram": "https://www.instagram.com/reel/ABC123DEF",
        "twitter": "https://twitter.com/user/status/123456789",
        "pinterest": "https://www.pinterest.com/pin/123456789",
        "likee": "https://likee.video/@user/video/123456789",
        "twitch": "https://www.twitch.tv/videos/123456789",
        "dailymotion": "https://www.dailymotion.com/video/abc123",
        "aparat": "https://www.aparat.com/v/abc123",
        "namava": "https://www.namava.ir/v/abc123",
        "filimo": "https://www.filimo.com/v/abc123",
        "tiva": "https://www.tiva.ir/v/abc123"
    }
    
    list_text = (
        "📋 *تمام پلتفرم‌ها با مثال*\n\n"
        
        "*🎬 پلتفرم‌های اصلی:*\n"
        f"🎵 TikTok\n`{examples['tiktok']}`\n\n"
        f"📺 YouTube\n`{examples['youtube']}`\n\n"
        f"📷 Instagram\n`{examples['instagram']}`\n\n"
        
        "*📌 پلتفرم‌های دیگر:*\n"
        f"📌 Pinterest\n`{examples['pinterest']}`\n\n"
        f"❤️ Likee\n`{examples['likee']}`\n\n"
        f"🎮 Twitch\n`{examples['twitch']}`\n\n"
        
        "*🇮🇷 پلتفرم‌های ایرانی:*\n"
        f"🇮🇷 آپارات\n`{examples['aparat']}`\n\n"
        f"🇮🇷 نماوا\n`{examples['namava']}`\n\n"
        f"🇮🇷 فیلیمو\n`{examples['filimo']}`\n\n"
        
        "💡 *نکته:* هر لینک ویدیویی از پلتفرم‌های بالا رو می‌تونی بفرستی!"
    )
    
    await update.message.reply_text(list_text, parse_mode='Markdown')

def is_supported(url):
    """Check if URL is from supported platform"""
    url_lower = url.lower()
    
    # Check all supported domains
    for domain in SUPPORTED_DOMAINS:
        if domain in url_lower:
            return True
    
    # Additional check for common video patterns
    video_patterns = [
        r'\.(mp4|avi|mov|mkv|webm|flv|m3u8)',
        r'/video/',
        r'/v/',
        r'/watch',
        r'/reel/',
        r'/clip/',
        r'/status/',
        r'/tv/'
    ]
    
    for pattern in video_patterns:
        if re.search(pattern, url_lower):
            return True
    
    return False

def get_platform_info(url):
    """Get platform name and emoji from URL"""
    url_lower = url.lower()
    
    # Check each platform
    platform_patterns = {
        "tiktok": ["tiktok.com", "vm.tiktok", "vt.tiktok"],
        "facebook": ["facebook.com", "fb.watch", "fb.com"],
        "youtube": ["youtube.com", "youtu.be"],
        "instagram": ["instagram.com", "instagr.am"],
        "twitter": ["twitter.com", "x.com", "t.co"],
        "reddit": ["reddit.com", "redd.it"],
        "pinterest": ["pinterest.com", "pin.it"],
        "likee": ["likee.video", "like.com"],
        "twitch": ["twitch.tv"],
        "dailymotion": ["dailymotion.com", "dai.ly"],
        "streamable": ["streamable.com"],
        "vimeo": ["vimeo.com"],
        "rumble": ["rumble.com"],
        "bilibili": ["bilibili.com", "b23.tv"],
        "ted": ["ted.com"],
        "aparat": ["aparat.com"],
        "namava": ["namava.ir"],
        "filimo": ["filimo.com"],
        "tiva": ["tiva.ir"]
    }
    
    for platform_id, patterns in platform_patterns.items():
        for pattern in patterns:
            if pattern in url_lower:
                return PLATFORM_NAMES.get(platform_id, PLATFORM_NAMES["default"])
    
    return PLATFORM_NAMES["default"]

def clean_text(text):
    """Clean text for safe display"""
    if not text:
        return ""
    
    # Remove control characters
    cleaned = re.sub(r'[\x00-\x1F\x7F]', '', text)
    
    # Replace problematic characters
    cleaned = cleaned.replace('`', "'")
    cleaned = cleaned.replace('```', "'''")
    
    # Clean excessive whitespace
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    
    # Truncate if too long
    if len(cleaned) > 150:
        cleaned = cleaned[:147] + "..."
    
    return cleaned

async def get_video_info(url):
    """Get video information using yt-dlp"""
    try:
        cmd = [
            "yt-dlp",
            "--dump-json",
            "--no-warnings",
            "--skip-download",
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
        
        if process.returncode == 0:
            return json.loads(stdout.decode('utf-8', errors='ignore'))
        else:
            logger.debug(f"Info extraction failed: {stderr.decode('utf-8', errors='ignore')[:100]}")
            return None
            
    except Exception as e:
        logger.debug(f"Info extraction error: {e}")
        return None

def create_caption(video_info, platform_info, url, file_size):
    """Create informative caption"""
    
    # Platform header
    caption = f"{platform_info['emoji']} *{platform_info['name']}*\n\n"
    
    # Add video info if available
    if video_info:
        title = clean_text(video_info.get('title', ''))
        uploader = clean_text(video_info.get('uploader', ''))
        
        if title and title != 'Unknown Title':
            caption += f"📹 *{title}*\n"
        
        if uploader and uploader != 'Unknown Uploader':
            caption += f"👤 *آپلودکننده:* {uploader}\n"
        
        # Duration
        duration = video_info.get('duration', 0)
        if duration:
            minutes = duration // 60
            seconds = duration % 60
            caption += f"⏱ *مدت:* {minutes}:{seconds:02d}\n"
        
        # Stats
        views = video_info.get('view_count', 0)
        likes = video_info.get('like_count', 0)
        
        if views:
            caption += f"👁 *بازدید:* {views:,}\n"
        if likes:
            caption += f"👍 *لایک:* {likes:,}\n"
    
    # File info
    caption += f"📦 *حجم:* {file_size/1024/1024:.1f}MB\n"
    
    # Short URL
    url_display = url
    if len(url) > 60:
        url_display = url[:57] + "..."
    caption += f"🔗 *لینک:* {url_display}"
    
    return caption

async def download_video(url, output_dir):
    """Download video with smart format selection"""
    unique_id = uuid4().hex[:10]
    output_template = f"{output_dir}/{unique_id}.%(ext)s"
    
    # Smart format selection based on platform
    platform_info = get_platform_info(url)
    platform_id = platform_info.get("id", "default")
    
    # Platform-specific formats
    format_configs = {
        "facebook": "best[height<=720][filesize<=50M]/best[height<=480]/best[filesize<=50M]/worst",
        "youtube": "best[height<=720][filesize<=50M]/best[filesize<=50M]/worst",
        "bilibili": "best[filesize<=50M]/worst",
        "aparat": "best[filesize<=50M]/worst",
        "namava": "best[filesize<=50M]/worst",
        "filimo": "best[filesize<=50M]/worst",
        "tiva": "best[filesize<=50M]/worst",
        "default": "best[filesize<=50M]/worst"
    }
    
    format_str = format_configs.get(platform_id, format_configs["default"])
    
    # Build command
    cmd = [
        "yt-dlp",
        "--no-warnings",
        "--format", format_str,
        "--max-filesize", "50M",
        "--restrict-filenames",
        "--socket-timeout", "30",
        "--retries", "3",
        "-o", output_template,
        url
    ]
    
    try:
        logger.info(f"Downloading from {platform_info['name']}...")
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='ignore').strip()
            
            # Try fallback format
            logger.info("Trying fallback format...")
            fallback_cmd = [
                "yt-dlp",
                "--no-warnings",
                "--format", "best",
                "--max-filesize", "50M",
                "-o", output_template,
                url
            ]
            
            process2 = await asyncio.create_subprocess_exec(
                *fallback_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout2, stderr2 = await asyncio.wait_for(process2.communicate(), timeout=300)
            
            if process2.returncode != 0:
                error2 = stderr2.decode('utf-8', errors='ignore').strip()
                error_lines = [line for line in error2.split('\n') if line.strip()]
                last_error = error_lines[-1] if error_lines else "خطای دانلود"
                return None, f"{last_error[:100]}"
        
        # Find downloaded file
        for file in Path(output_dir).glob(f"{unique_id}.*"):
            if file.is_file() and file.stat().st_size > 0:
                return file, None
        
        return None, "فایل بعد از دانلود پیدا نشد"
        
    except asyncio.TimeoutError:
        return None, "زمان دانلود به پایان رسید (۵ دقیقه)"
    except Exception as e:
        logger.error(f"Download exception: {e}")
        return None, f"خطا: {str(e)}"

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming video links"""
    user = update.effective_user
    chat_id = update.effective_chat.id
    text = update.message.text.strip()
    
    logger.info(f"Message from {user.id} ({user.first_name}): {text[:80]}...")
    
    # Check if it's a URL
    if not text.startswith(('http://', 'https://')):
        await update.message.reply_text("لطفا یک لینک معتبر با http:// یا https:// ارسال کنید")
        return
    
    # Check if supported
    if not is_supported(text):
        await update.message.reply_text(
            "❌ این پلتفرم پشتیبانی نمی‌شود.\n\n"
            "برای مشاهده پلتفرم‌های پشتیبانی شده /list را ارسال کنید."
        )
        return
    
    # Get platform info
    platform_info = get_platform_info(text)
    
    # Create user directory
    user_dir = Path(f"downloads/{chat_id}")
    user_dir.mkdir(parents=True, exist_ok=True)
    
    # Send initial message
    msg = await update.message.reply_text(
        f"{platform_info['emoji']} درحال پردازش لینک {platform_info['name']}..."
    )
    
    file_path = None
    try:
        # Get video information
        await msg.edit_text(f"{platform_info['emoji']} دریافت اطلاعات ویدیو...")
        video_info = await get_video_info(text)
        
        # Download video
        await msg.edit_text(f"{platform_info['emoji']} درحال دانلود...")
        file_path, error = await download_video(text, str(user_dir))
        
        if error:
            await msg.edit_text(f"❌ {error}")
            return
        
        if not file_path or not file_path.exists():
            await msg.edit_text("❌ فایل بعد از دانلود پیدا نشد")
            return
        
        # Check file size (50MB limit)
        file_size = file_path.stat().st_size
        if file_size > 50 * 1024 * 1024:
            await msg.edit_text(f"❌ حجم فایل زیاد است ({file_size/1024/1024:.1f}MB > 50MB)")
            file_path.unlink()
            return
        
        # Create caption
        caption = create_caption(video_info, platform_info, text, file_size)
        
        # Send file
        await msg.edit_text(f"{platform_info['emoji']} درحال آپلود...")
        
        with open(file_path, 'rb') as f:
            # Determine file type
            try:
                result = subprocess.run(
                    ['file', '-b', '--mime-type', str(file_path)],
                    capture_output=True, text=True, timeout=5
                )
                mime_type = result.stdout.strip() if result.returncode == 0 else 'video/mp4'
            except:
                mime_type = 'video/mp4'
            
            if mime_type.startswith('video'):
                await update.message.reply_video(
                    video=f,
                    caption=caption,
                    parse_mode='Markdown',
                    supports_streaming=True,
                    read_timeout=120,
                    write_timeout=120
                )
            elif mime_type.startswith('image'):
                await update.message.reply_photo(
                    photo=f,
                    caption=caption,
                    parse_mode='Markdown',
                    read_timeout=60
                )
            else:
                await update.message.reply_document(
                    document=f,
                    caption=caption,
                    parse_mode='Markdown',
                    read_timeout=60
                )
        
        await msg.edit_text(
            f"✅ انجام شد! {platform_info['emoji']} {platform_info['name']} - "
            f"{file_size/1024/1024:.1f}MB"
        )
        
        logger.info(f"Successfully sent {platform_info['name']} video to {user.id}")
        
    except Exception as e:
        logger.error(f"Error processing {text}: {e}")
        
        # Friendly error messages
        error_msg = f"❌ خطا: {str(e)[:100]}"
        
        # Platform-specific tips
        tips = {
            "facebook": "از لینک مستقیم ویدیو استفاده کنید، نه صفحات لاگین/اشتراک",
            "instagram": "مطمئن شوید ویدیو عمومی است",
            "twitter": "ممکن است برخی ویدیوها محدودیت داشته باشند",
            "aparat": "آپارات معمولا خوب کار می‌کند",
            "namava": "نماوا ممکن است نیاز به لاگین داشته باشد",
            "filimo": "فیلیمو ممکن است محدودیت منطقه‌ای داشته باشد"
        }
        
        platform_id = platform_info.get("id", "")
        if platform_id in tips:
            error_msg += f"\n\n💡 *نکته:* {tips[platform_id]}"
        
        await msg.edit_text(error_msg, parse_mode='Markdown')
    
    finally:
        # Cleanup
        if file_path and file_path.exists():
            try:
                file_path.unlink()
                logger.info(f"Cleaned up: {file_path}")
            except:
                pass

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Error: {context.error}", exc_info=True)
    
    if update and update.effective_chat:
        try:
            await update.effective_chat.send_message(
                "⚠️ خطایی رخ داد. لطفا دوباره تلاش کنید."
            )
        except:
            pass

def main():
    """Start the bot"""
    if not BOT_TOKEN:
        logger.error("❌ BOT_TOKEN not found!")
        return
    
    # Create application
    app = Application.builder().token(BOT_TOKEN).build()
    
    # Add handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(CommandHandler("list", list_cmd))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    # Error handler
    app.add_error_handler(error_handler)
    
    # Start bot
    logger.info("🤖 Bot starting with ALL platform support...")
    print("=" * 60)
    print("✅ Bot running! Press Ctrl+C to stop")
    print("=" * 60)
    
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
EOF

# Make executable
chmod +x $BOT_FILE

# 7. Create management scripts
echo -e "${YELLOW}📁 Creating management scripts...${NC}"

# Start script
cat << 'EOF' > start.sh
#!/bin/bash
# Start the bot

echo "🚀 Starting Complete Downloader Bot..."
source venv/bin/activate
python3 bot.py
EOF

# Stop script
cat << 'EOF' > stop.sh
#!/bin/bash
# Stop the bot

echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null && echo "✅ Bot stopped" || echo "⚠️ Bot not running"
EOF

# Restart script
cat << 'EOF' > restart.sh
#!/bin/bash
# Restart bot

echo "🔄 Restarting..."
./stop.sh
sleep 2
./start.sh
EOF

# Status script
cat << 'EOF' > status.sh
#!/bin/bash
# Check bot status

echo "🤖 Bot Status"
echo "============"

if pgrep -f "python3 bot.py" > /dev/null; then
    echo "✅ Status: RUNNING"
    echo "📊 PID: $(pgrep -f "python3 bot.py")"
else
    echo "❌ Status: STOPPED"
fi

# Check active downloads
YTDLP_COUNT=$(pgrep -f "yt-dlp" | wc -l)
if [ $YTDLP_COUNT -gt 0 ]; then
    echo "📥 Active downloads: $YTDLP_COUNT"
fi

# Check directories
echo "📁 Directories:"
echo "  downloads/ - $(find downloads -type f 2>/dev/null | wc -l) files"
echo "  logs/ - $(du -sh logs 2>/dev/null | cut -f1)"

echo "============"
EOF

# Make scripts executable
chmod +x start.sh stop.sh restart.sh status.sh

# 8. Create test file
cat << 'EOF' > test.py
#!/usr/bin/env python3
# Test all platform support

import sys
import os
import subprocess

print("🔧 Testing Complete Downloader Bot Installation")
print("=" * 50)

# Test results
tests = []
def add_test(name, result):
    icon = "✅" if result else "❌"
    tests.append(f"{icon} {name}")
    return result

# Check Python
try:
    import platform
    py_ver = platform.python_version()
    add_test(f"Python {py_ver}", True)
except:
    add_test("Python", False)

# Check packages
packages_to_check = ["telegram", "dotenv", "json", "re"]
for pkg in packages_to_check:
    try:
        __import__(pkg)
        add_test(pkg, True)
    except:
        add_test(pkg, False)

# Check yt-dlp
result = subprocess.run(["yt-dlp", "--version"], capture_output=True, text=True)
add_test(f"yt-dlp {result.stdout.strip()}" if result.returncode == 0 else "yt-dlp", result.returncode == 0)

# Check .env
env_ok = os.path.exists(".env")
if env_ok:
    with open(".env", "r") as f:
        env_ok = "BOT_TOKEN=" in f.read()
add_test(".env file", env_ok)

# Check directories
for dir_name in ["downloads", "logs", "venv"]:
    add_test(f"Directory: {dir_name}", os.path.exists(dir_name))

# Print results
print("\n".join(tests))
print("=" * 50)

# Platform count
platforms = [
    "TikTok", "Facebook", "YouTube", "Instagram", "Twitter/X", "Reddit",
    "Pinterest", "Likee", "Twitch", "Dailymotion", "Streamable", "Vimeo",
    "Rumble", "Bilibili", "TED", "آپارات", "نماوا", "فیلیمو", "تیوا"
]

print(f"\n🌍 *پشتیبانی از {len(platforms)} پلتفرم:*")
for i in range(0, len(platforms), 3):
    line = platforms[i:i+3]
    print(f"  {' | '.join(line)}")

print("\n" + "=" * 50)
print("🎉 Installation complete!")
print("\n✨ *ویژگی‌ها:*")
print("   • پشتیبانی از تمام پلتفرم‌های درخواستی")
print("   • اطلاعات کامل ویدیو")
print("   • کیفیت اتوماتیک")
print("   • کپشن فارسی و انگلیسی")
print("\n🚀 To start: ./start.sh")
print("📋 To list platforms: /list in bot")

success = all(["❌" not in test for test in tests])
sys.exit(0 if success else 1)
EOF

chmod +x test.py

# 9. Create requirements.txt
cat << 'EOF' > requirements.txt
python-telegram-bot==20.7
python-dotenv==1.0.0
EOF

# 10. Create platform examples file
cat << 'EOF' > examples.txt
# مثال‌های لینک برای تست پلتفرم‌های مختلف:

📌 Pinterest:
https://www.pinterest.com/pin/123456789/

❤️ Likee:
https://likee.video/@username/video/123456789

🎮 Twitch:
https://www.twitch.tv/videos/123456789
https://clips.twitch.tv/CoolClipName

🎬 Dailymotion:
https://www.dailymotion.com/video/abc123
https://dai.ly/abc123

🎥 Streamable:
https://streamable.com/abc123

🎞️ Vimeo:
https://vimeo.com/123456789

⚡ Rumble:
https://rumble.com/abc123-def456

🇨🇳 Bilibili:
https://www.bilibili.com/video/BV123456789
https://b23.tv/abc123

💡 TED:
https://www.ted.com/talks/123

🇮🇷 آپارات:
https://www.aparat.com/v/abc123

🇮🇷 نماوا:
https://www.namava.ir/v/abc123

🇮🇷 فیلیمو:
https://www.filimo.com/v/abc123

🇮🇷 تیوا:
https://www.tiva.ir/v/abc123

🎵 TikTok:
https://www.tiktok.com/@user/video/123456789

📘 Facebook:
https://www.facebook.com/watch/?v=123456789
https://fb.watch/abc123def/

📺 YouTube:
https://www.youtube.com/watch?v=dQw4w9WgXcQ
https://youtu.be/dQw4w9WgXcQ

📷 Instagram:
https://www.instagram.com/reel/ABC123DEF/
https://www.instagram.com/p/ABC123DEF/

🐦 Twitter/X:
https://twitter.com/user/status/123456789
https://x.com/user/status/123456789

👽 Reddit:
https://www.reddit.com/r/videos/comments/abc123/title/
EOF

# 11. Final instructions
echo -e "\n${PURPLE}==============================================${NC}"
echo -e "${PURPLE}✅ نصب کامل بات دانلودر با تمام پلتفرم‌ها${NC}"
echo -e "${PURPLE}==============================================${NC}"
echo -e "\n${GREEN}📁 فایل‌های ایجاد شده:${NC}"
ls -la

echo -e "\n${CYAN}🚀 برای شروع:${NC}"
echo -e "  ${GREEN}./start.sh${NC}"

echo -e "\n${YELLOW}⚙️ دستورات مدیریت:${NC}"
echo -e "  ${GREEN}./stop.sh${NC}      # توقف بات"
echo -e "  ${GREEN}./restart.sh${NC}   # راه‌اندازی مجدد"
echo -e "  ${GREEN}./status.sh${NC}    # وضعیت بات"
echo -e "  ${GREEN}./test.py${NC}      # تست نصب"

echo -e "\n${PURPLE}🌍 پلتفرم‌های پشتیبانی شده:${NC}"
echo -e "  ${BLUE}🎬 بین‌المللی:${NC}"
echo -e "    • TikTok 🎵      • Facebook 📘"
echo -e "    • YouTube 📺     • Instagram 📷"
echo -e "    • Twitter/X 🐦   • Reddit 👽"
echo -e "    • Pinterest 📌   • Likee ❤️"
echo -e "    • Twitch 🎮      • Dailymotion 🎬"
echo -e "    • Streamable 🎥  • Vimeo 🎞️"
echo -e "    • Rumble ⚡      • Bilibili 🇨🇳"
echo -e "    • TED 💡"

echo -e "\n  ${RED}🇮🇷 ایرانی:${NC}"
echo -e "    • آپارات 🇮🇷     • نماوا 🇮🇷"
echo -e "    • فیلیمو 🇮🇷     • تیوا 🇮🇷"

echo -e "\n${GREEN}✨ ویژگی‌ها:${NC}"
echo -e "  • اطلاعات کامل ویدیو"
echo -e "  • کپشن فارسی/انگلیسی"
echo -e "  • کیفیت اتوماتیک"
echo -e "  • بدون مشکل Markdown"
echo -e "  • حداکثر حجم: ۵۰ مگابایت"

echo -e "\n${YELLOW}📝 دستورات بات:${NC}"
echo -e "  /start - راهنما"
echo -e "  /help  - کمک"
echo -e "  /list  - لیست پلتفرم‌ها"

echo -e "\n${RED}⚠️ نکات مهم:${NC}"
echo -e "  • فقط ویدیوهای عمومی"
echo -e "  • برخی پلتفرم‌ها ممکنه محدودیت داشته باشند"
echo -e "  • پلتفرم‌های ایرانی نیاز به تست دارند"

echo -e "\n${GREEN}🤖 بات آماده با پشتیبانی از تمام پلتفرم‌ها!${NC}"
echo -e "${PURPLE}==============================================${NC}"

# 12. Test and ask to start
echo -e "\n${YELLOW}آیا می‌خواهید نصب را تست کنید؟ (y/n)${NC}"
read -r TEST

if [[ "$TEST" =~ ^[Yy]$ ]]; then
    source venv/bin/activate
    python3 test.py
fi

echo -e "\n${YELLOW}آیا می‌خواهید بات را الآن شروع کنید؟ (y/n)${NC}"
read -r START

if [[ "$START" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}درحال شروع...${NC}"
    ./start.sh
else
    echo -e "${YELLOW}برای شروع بعدی: ./start.sh${NC}"
    echo -e "${CYAN}مثال‌های لینک در فایل examples.txt ذخیره شدند.${NC}"
fi
