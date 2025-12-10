#!/bin/bash

# =========================================================
#   Telegram Video Downloader Bot - Complete Installer
# =========================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🤖 Telegram Video Downloader Bot Installer${NC}"
echo -e "${YELLOW}==========================================${NC}"

# 1. Install system dependencies
echo -e "${YELLOW}📦 Installing system dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip python3-venv curl ffmpeg

# 2. Install yt-dlp
echo -e "${YELLOW}⬇️ Installing yt-dlp...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp
echo -e "${GREEN}✅ yt-dlp installed${NC}"

# 3. Create project directory
echo -e "${YELLOW}📁 Creating project structure...${NC}"
mkdir -p telegram-video-bot
cd telegram-video-bot
mkdir -p downloads logs cookies

# 4. Create Python virtual environment
echo -e "${YELLOW}🐍 Setting up Python environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# 5. Install Python packages
pip install --upgrade pip
pip install python-telegram-bot==20.7 python-dotenv==1.0.0

# 6. Get Bot Token
echo -e "${GREEN}🔑 Bot Token Configuration${NC}"
echo -e "${YELLOW}Enter your Telegram Bot Token (from @BotFather):${NC}"
read -r BOT_TOKEN

# Validate token format
if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Invalid token format!${NC}"
    echo -e "${RED}Example: 1234567890:ABCdefGHIJKLMnopQRSTuvwXYZ${NC}"
    exit 1
fi

echo "BOT_TOKEN=$BOT_TOKEN" > .env
echo -e "${GREEN}✅ Token saved to .env file${NC}"

# 7. Create bot.py file
echo -e "${YELLOW}📝 Creating bot.py...${NC}"

cat > bot.py << 'BOT_EOF'
#!/usr/bin/env python3
"""
Telegram Video Downloader Bot with Quality Selection
Supports: TikTok, Facebook, YouTube, Instagram, Twitter/X, Reddit, Pinterest, Likee, Twitch, Dailymotion, Streamable, Vimeo, Rumble, Bilibili, TED, Aparat, Namava, Filimo, Tiva
"""

import os
import sys
import logging
import subprocess
import asyncio
import json
from pathlib import Path
from uuid import uuid4
from datetime import datetime

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, CallbackQueryHandler
from telegram.constants import ParseMode
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

# Supported platforms
SUPPORTED_DOMAINS = [
    "tiktok.com", "douyin.com",
    "facebook.com", "fb.watch",
    "youtube.com", "youtu.be",
    "instagram.com",
    "twitter.com", "x.com",
    "reddit.com",
    "pinterest.com", "pin.it",
    "likee.video", "likee.com",
    "twitch.tv",
    "dailymotion.com", "dai.ly",
    "streamable.com",
    "vimeo.com",
    "rumble.com",
    "bilibili.com",
    "ted.com",
    "aparat.com",
    "namava.ir",
    "filimo.com",
    "tiva.ir"
]

# Platform names
PLATFORM_NAMES = {
    "tiktok": "TikTok",
    "facebook": "Facebook",
    "youtube": "YouTube", 
    "instagram": "Instagram",
    "twitter": "Twitter/X",
    "reddit": "Reddit",
    "pinterest": "Pinterest",
    "likee": "Likee",
    "twitch": "Twitch",
    "dailymotion": "Dailymotion",
    "streamable": "Streamable",
    "vimeo": "Vimeo",
    "rumble": "Rumble",
    "bilibili": "Bilibili",
    "ted": "TED",
    "aparat": "Aparat",
    "namava": "Namava",
    "filimo": "Filimo",
    "tiva": "Tiva"
}

# User sessions storage
user_sessions = {}

class DownloadSession:
    """Store user session data"""
    def __init__(self, url, platform, formats):
        self.url = url
        self.platform = platform
        self.formats = formats
        self.selected_format = None
        self.created_at = datetime.now()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send welcome message"""
    welcome_msg = """
🤖 *Video Downloader Bot*

📥 *Supported Platforms:*
• TikTok, Facebook, YouTube
• Instagram, Twitter/X, Reddit
• Pinterest, Likee, Twitch
• Dailymotion, Streamable, Vimeo
• Rumble, Bilibili, TED

🇮🇷 *Iranian Platforms:*
• Aparat, Namava, Filimo, Tiva

✨ *Features:*
✅ Choose quality before download
✅ See file size for each quality
✅ Video information included
✅ Max 50MB file size
✅ Public videos supported

📝 *How to use:*
1. Send me a video link
2. Select your preferred quality
3. Wait for download to complete
"""
    await update.message.reply_text(welcome_msg, parse_mode=ParseMode.MARKDOWN)

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send help message"""
    help_text = """
❓ *Help Guide*

📋 *Steps:*
1. Copy video URL
2. Send to bot
3. Choose quality from list
4. Get downloaded file

🎛️ *Quality Selection:*
- All available qualities shown
- Each option shows resolution & size
- Choose based on your needs

📊 *Video Info Displayed:*
• Title and uploader
• Duration and views
• Likes count
• Platform and quality
• File size

⚠️ *Limits:*
• Max 50MB per file
• Public videos only
• Some platforms may need cookies
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

def is_supported(url):
    """Check if URL is supported"""
    url_lower = url.lower()
    for domain in SUPPORTED_DOMAINS:
        if domain in url_lower:
            return True
    return False

def format_file_size(size_bytes):
    """Format file size"""
    if size_bytes == 0 or size_bytes is None:
        return "Unknown"
    
    units = ['B', 'KB', 'MB', 'GB']
    size = float(size_bytes)
    unit_index = 0
    
    while size >= 1024 and unit_index < len(units) - 1:
        size /= 1024
        unit_index += 1
    
    return f"{size:.1f} {units[unit_index]}"

def detect_platform(url):
    """Detect platform from URL"""
    url_lower = url.lower()
    
    platform_map = {
        "tiktok.com": "tiktok",
        "douyin.com": "tiktok",
        "facebook.com": "facebook",
        "fb.watch": "facebook",
        "youtube.com": "youtube",
        "youtu.be": "youtube",
        "instagram.com": "instagram",
        "twitter.com": "twitter",
        "x.com": "twitter",
        "reddit.com": "reddit",
        "pinterest.com": "pinterest",
        "pin.it": "pinterest",
        "likee.video": "likee",
        "likee.com": "likee",
        "twitch.tv": "twitch",
        "dailymotion.com": "dailymotion",
        "dai.ly": "dailymotion",
        "streamable.com": "streamable",
        "vimeo.com": "vimeo",
        "rumble.com": "rumble",
        "bilibili.com": "bilibili",
        "ted.com": "ted",
        "aparat.com": "aparat",
        "namava.ir": "namava",
        "filimo.com": "filimo",
        "tiva.ir": "tiva"
    }
    
    for domain, platform in platform_map.items():
        if domain in url_lower:
            return platform
    
    return "unknown"

async def get_available_formats(url):
    """Get available formats with size info"""
    try:
        # Check for cookies
        cookies_path = "cookies/cookies.txt"
        cookies_args = []
        if os.path.exists(cookies_path):
            cookies_args = ["--cookies", cookies_path]
        
        cmd = [
            "yt-dlp",
            *cookies_args,
            "--list-formats",
            "--no-warnings",
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
        
        if process.returncode != 0:
            return await get_basic_formats(url)
        
        output = stdout.decode('utf-8', errors='ignore')
        formats = []
        lines = output.split('\n')
        
        for line in lines:
            if 'mp4' in line.lower() or 'webm' in line.lower():
                parts = line.split()
                if len(parts) >= 7:
                    try:
                        format_id = parts[0]
                        extension = parts[1]
                        resolution = parts[2] if len(parts) > 2 else "N/A"
                        
                        # Find filesize
                        filesize = None
                        for i, part in enumerate(parts):
                            if 'MiB' in part or 'KiB' in part:
                                size_str = parts[i-1]
                                unit = parts[i]
                                try:
                                    if 'MiB' in unit:
                                        filesize = float(size_str) * 1024 * 1024
                                    elif 'KiB' in unit:
                                        filesize = float(size_str) * 1024
                                except:
                                    filesize = None
                                break
                        
                        if filesize and filesize <= 50 * 1024 * 1024:
                            formats.append({
                                'id': format_id,
                                'ext': extension,
                                'resolution': resolution,
                                'filesize': filesize,
                                'filesize_str': format_file_size(filesize)
                            })
                    except:
                        continue
        
        if not formats:
            return await get_basic_formats(url)
        
        formats.sort(key=lambda x: x.get('filesize', 0), reverse=True)
        return formats
        
    except:
        return await get_basic_formats(url)

async def get_basic_formats(url):
    """Get basic formats fallback"""
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
            data = json.loads(stdout.decode('utf-8', errors='ignore'))
            
            formats = []
            formats.append({
                'id': 'best',
                'ext': 'mp4',
                'resolution': 'Best Quality',
                'filesize': data.get('filesize_approx'),
                'filesize_str': format_file_size(data.get('filesize_approx'))
            })
            
            formats.append({
                'id': 'worst',
                'ext': 'mp4',
                'resolution': 'Low Quality',
                'filesize': None,
                'filesize_str': 'Unknown'
            })
            
            return formats
    except:
        pass
    
    return None

async def get_video_info(url):
    """Get video information"""
    try:
        cookies_path = "cookies/cookies.txt"
        cookies_args = []
        if os.path.exists(cookies_path):
            cookies_args = ["--cookies", cookies_path]
        
        cmd = [
            "yt-dlp",
            *cookies_args,
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
    except:
        pass
    
    return None

def create_caption(video_info, platform, url, selected_format=None):
    """Create video caption"""
    platform_name = PLATFORM_NAMES.get(platform, platform.capitalize())
    
    if not video_info:
        return f"📹 Downloaded from {platform_name}\n🔗 {url[:100]}..."
    
    try:
        title = video_info.get('title', 'Unknown Title')[:100]
        uploader = video_info.get('uploader', 'Unknown Uploader')[:50]
        
        duration = video_info.get('duration', 0)
        if duration:
            minutes = int(duration // 60)
            seconds = int(duration % 60)
            duration_str = f"{minutes}:{seconds:02d}"
        else:
            duration_str = "Unknown"
        
        view_count = video_info.get('view_count')
        views_str = f"{view_count:,}" if view_count else "Unknown"
        
        caption = f"📹 {title}\n\n"
        caption += f"👤 {uploader}\n"
        caption += f"⏱ {duration_str} | 👁 {views_str}\n"
        caption += f"🏷 {platform_name}\n"
        
        if selected_format:
            caption += f"📊 {selected_format.get('resolution', 'Unknown')}\n"
        
        url_display = url[:80] + "..." if len(url) > 80 else url
        caption += f"\n🔗 {url_display}"
        
        return caption[:1000]
    except:
        return f"📹 Downloaded from {platform_name}\n🔗 {url[:100]}..."

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming links"""
    user = update.effective_user
    chat_id = update.effective_chat.id
    text = update.message.text.strip()
    
    logger.info(f"Message from {user.id}: {text[:50]}")
    
    if not text.startswith(('http://', 'https://')):
        await update.message.reply_text("Please send a valid URL starting with http:// or https://")
        return
    
    if not is_supported(text):
        platforms = "\n".join([f"• {name}" for name in PLATFORM_NAMES.values()])
        await update.message.reply_text(f"❌ Platform not supported.\n\nSupported:\n{platforms}")
        return
    
    platform = detect_platform(text)
    msg = await update.message.reply_text(f"⏳ Analyzing {PLATFORM_NAMES.get(platform, platform)} link...")
    
    try:
        await msg.edit_text("📋 Getting video information...")
        video_info = await get_video_info(text)
        
        await msg.edit_text("🔍 Checking available qualities...")
        formats = await get_available_formats(text)
        
        if not formats or len(formats) == 0:
            await msg.edit_text("❌ No available formats found.")
            return
        
        session = DownloadSession(text, platform, formats)
        user_sessions[chat_id] = session
        
        keyboard = []
        for i, fmt in enumerate(formats[:8]):
            if i % 2 == 0:
                keyboard.append([])
            
            resolution = fmt.get('resolution', 'Unknown')
            size_str = fmt.get('filesize_str', 'Unknown')
            button_text = f"{resolution} ({size_str})"
            
            keyboard[-1].append(InlineKeyboardButton(
                button_text, 
                callback_data=f"quality:{i}:{fmt['id']}"
            ))
        
        keyboard.append([InlineKeyboardButton("❌ Cancel", callback_data="cancel")])
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        platform_name = PLATFORM_NAMES.get(platform, platform.capitalize())
        selection_text = f"🎬 *{platform_name} Video*\n\n"
        
        if video_info:
            title = video_info.get('title', 'Unknown')[:80]
            selection_text += f"📹 {title}\n\n"
        
        selection_text += "📊 *Select Quality:*\n"
        
        await msg.edit_text(
            selection_text,
            reply_markup=reply_markup,
            parse_mode=ParseMode.MARKDOWN
        )
        
    except Exception as e:
        logger.error(f"Error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)[:100]}")

async def handle_quality_selection(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle quality selection"""
    query = update.callback_query
    await query.answer()
    
    chat_id = query.message.chat_id
    data = query.data
    
    if data == "cancel":
        if chat_id in user_sessions:
            del user_sessions[chat_id]
        await query.message.edit_text("❌ Download cancelled.")
        return
    
    if data.startswith("quality:"):
        try:
            parts = data.split(":")
            format_index = int(parts[1])
            format_id = parts[2]
            
            session = user_sessions.get(chat_id)
            if not session:
                await query.message.edit_text("❌ Session expired. Please send link again.")
                return
            
            if 0 <= format_index < len(session.formats):
                selected_format = session.formats[format_index]
                session.selected_format = selected_format
                
                platform_name = PLATFORM_NAMES.get(session.platform, session.platform.capitalize())
                size_str = selected_format.get('filesize_str', 'Unknown')
                resolution = selected_format.get('resolution', 'Unknown')
                
                await query.message.edit_text(
                    f"✅ Selected: {resolution} ({size_str})\n"
                    f"⬇️ Downloading from {platform_name}..."
                )
                
                await perform_download(chat_id, session, query.message)
            else:
                await query.message.edit_text("❌ Invalid selection.")
                
        except Exception as e:
            logger.error(f"Selection error: {e}")
            await query.message.edit_text(f"❌ Error: {str(e)[:100]}")

async def perform_download(chat_id, session, message):
    """Download and send video"""
    try:
        user_dir = Path(f"downloads/{chat_id}")
        user_dir.mkdir(parents=True, exist_ok=True)
        
        unique_id = uuid4().hex[:8]
        output_template = f"{user_dir}/{unique_id}.%(ext)s"
        
        cookies_path = "cookies/cookies.txt"
        cookies_args = []
        if os.path.exists(cookies_path):
            cookies_args = ["--cookies", cookies_path]
        
        cmd = [
            "yt-dlp",
            *cookies_args,
            "--no-warnings",
            "--format", session.selected_format['id'],
            "--max-filesize", "50M",
            "--restrict-filenames",
            "-o", output_template,
            session.url
        ]
        
        await message.edit_text("⬇️ Downloading...")
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='ignore').strip()
            if "format is not available" in error:
                await message.edit_text("⚠️ Trying fallback quality...")
                
                fallback_cmd = [
                    "yt-dlp",
                    *cookies_args,
                    "--no-warnings",
                    "--format", "best[filesize<=50M]",
                    "--max-filesize", "50M",
                    "--restrict-filenames",
                    "-o", output_template,
                    session.url
                ]
                
                process2 = await asyncio.create_subprocess_exec(
                    *fallback_cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                
                await process2.communicate()
        
        # Find downloaded file
        downloaded_file = None
        for file in Path(user_dir).glob(f"{unique_id}.*"):
            if file.is_file() and file.stat().st_size > 0:
                downloaded_file = file
                break
        
        if not downloaded_file:
            await message.edit_text("❌ File not found after download")
            return
        
        file_size = downloaded_file.stat().st_size
        if file_size > 50 * 1024 * 1024:
            await message.edit_text(f"❌ File too large ({file_size/1024/1024:.1f}MB > 50MB)")
            downloaded_file.unlink()
            return
        
        video_info = await get_video_info(session.url)
        caption = create_caption(video_info, session.platform, session.url, session.selected_format)
        
        await message.edit_text("📤 Uploading...")
        
        with open(downloaded_file, 'rb') as f:
            await message.reply_video(
                video=f,
                caption=caption,
                supports_streaming=True,
                read_timeout=120,
                write_timeout=120
            )
        
        size_mb = file_size / 1024 / 1024
        platform_name = PLATFORM_NAMES.get(session.platform, session.platform.capitalize())
        await message.edit_text(f"✅ Download complete!\n📦 {platform_name} - {size_mb:.1f}MB")
        
        if downloaded_file.exists():
            downloaded_file.unlink()
        
        if chat_id in user_sessions:
            del user_sessions[chat_id]
        
    except asyncio.TimeoutError:
        await message.edit_text("❌ Download timeout.")
    except Exception as e:
        logger.error(f"Download error: {e}")
        await message.edit_text(f"❌ Error: {str(e)[:200]}")
        if chat_id in user_sessions:
            del user_sessions[chat_id]

def main():
    """Start the bot"""
    if not BOT_TOKEN:
        logger.error("❌ BOT_TOKEN not found!")
        return
    
    app = Application.builder().token(BOT_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_cmd))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    app.add_handler(CallbackQueryHandler(handle_quality_selection))
    
    logger.info("🤖 Bot starting...")
    print("=" * 50)
    print("✅ Bot with Quality Selection")
    print("✅ Supports 20+ platforms")
    print("=" * 50)
    
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
BOT_EOF

# 8. Create management scripts
echo -e "${YELLOW}📁 Creating management scripts...${NC}"

cat > start.sh << 'START_EOF'
#!/bin/bash
echo "🚀 Starting Video Downloader Bot..."
source venv/bin/activate
python3 bot.py
START_EOF

cat > stop.sh << 'STOP_EOF'
#!/bin/bash
echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null && echo "✅ Bot stopped" || echo "⚠️ Bot not running"
STOP_EOF

cat > restart.sh << 'RESTART_EOF'
#!/bin/bash
echo "🔄 Restarting bot..."
./stop.sh
sleep 2
./start.sh
RESTART_EOF

cat > test.sh << 'TEST_EOF'
#!/bin/bash
echo "🔧 Testing setup..."
source venv/bin/activate
python3 -c "
import sys
print('✅ Python version:', sys.version[:6])
try:
    import telegram
    print('✅ python-telegram-bot installed')
except:
    print('❌ python-telegram-bot missing')
try:
    import dotenv
    print('✅ python-dotenv installed')
except:
    print('❌ python-dotenv missing')
import subprocess
result = subprocess.run(['yt-dlp', '--version'], capture_output=True, text=True)
if result.returncode == 0:
    print(f'✅ yt-dlp: {result.stdout.strip()}')
else:
    print('❌ yt-dlp not working')
"
TEST_EOF

chmod +x bot.py start.sh stop.sh restart.sh test.sh

# 9. Create requirements.txt
cat > requirements.txt << 'REQS_EOF'
python-telegram-bot==20.7
python-dotenv==1.0.0
REQS_EOF

# 10. Display completion message
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"

echo -e "\n📁 ${YELLOW}Project Structure:${NC}"
ls -la

echo -e "\n🚀 ${YELLOW}Available Commands:${NC}"
echo -e "  ${GREEN}./start.sh${NC}    - Start the bot"
echo -e "  ${GREEN}./stop.sh${NC}     - Stop the bot"
echo -e "  ${GREEN}./restart.sh${NC}  - Restart the bot"
echo -e "  ${GREEN}./test.sh${NC}     - Test installation"

echo -e "\n📱 ${YELLOW}Supported Platforms:${NC}"
echo -e "  • TikTok, Facebook, YouTube, Instagram"
echo -e "  • Twitter/X, Reddit, Pinterest, Likee"
echo -e "  • Twitch, Dailymotion, Streamable, Vimeo"
echo -e "  • Rumble, Bilibili, TED"
echo -e "  • Aparat, Namava, Filimo, Tiva"

echo -e "\n✨ ${GREEN}Features:${NC}"
echo -e "  ✅ Choose quality before download"
echo -e "  ✅ See file size for each quality"
echo -e "  ✅ Supports all requested platforms"
echo -e "  ✅ Video information included"
echo -e "  ✅ Max 50MB file size"

echo -e "\n${YELLOW}📝 To start the bot:${NC}"
echo -e "1. ${GREEN}cd telegram-video-bot${NC}"
echo -e "2. ${GREEN}./start.sh${NC}"

echo -e "\n${YELLOW}🎯 Your bot token is saved in:${NC}"
echo -e "  ${GREEN}.env${NC} file"

echo -e "\n${GREEN}🤖 Your bot is ready to use!${NC}"
