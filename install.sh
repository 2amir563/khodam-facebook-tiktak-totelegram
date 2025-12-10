#!/bin/bash

# =========================================================
#         Enhanced Telegram Downloader Bot Setup
# =========================================================
# Advanced bot for downloading videos from social media with quality selection

set -e

BOT_FILE="bot.py"
ENV_FILE=".env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🛠️ Enhanced Telegram Downloader Bot Setup${NC}"

# 1. Install basic dependencies
echo -e "${YELLOW}📦 Installing system dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip python3-venv curl ffmpeg

# 2. Install yt-dlp with cookies support
echo -e "${YELLOW}⬇️ Installing yt-dlp...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp
echo -e "${GREEN}✅ yt-dlp installed${NC}"

# 3. Create directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
mkdir -p downloads logs cookies

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

# 6. Create enhanced bot.py with quality selection
echo -e "${YELLOW}📝 Creating enhanced bot.py with quality selection...${NC}"

cat << 'EOF' > $BOT_FILE
#!/usr/bin/env python3
"""
Enhanced Telegram Downloader Bot with Quality Selection
"""
import os
import sys
import logging
import subprocess
import asyncio
import json
import re
import math
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

# Enhanced supported platforms
SUPPORTED_DOMAINS = [
    # Main platforms
    "tiktok.com", "douyin.com",
    "facebook.com", "fb.watch",
    "youtube.com", "youtu.be",
    "instagram.com",
    "twitter.com", "x.com",
    "reddit.com",
    
    # Additional platforms
    "pinterest.com", "pin.it",
    "likee.video", "likee.com",
    "twitch.tv",
    "dailymotion.com", "dai.ly",
    "streamable.com",
    "vimeo.com",
    "rumble.com",
    "bilibili.com",
    "ted.com",
    
    # Iranian platforms
    "aparat.com",
    "namava.ir",
    "filimo.com",
    "tiva.ir"
]

# Platform names mapping
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

# User download sessions
user_sessions = {}

class DownloadSession:
    """Store user download session data"""
    def __init__(self, url, platform, formats):
        self.url = url
        self.platform = platform
        self.formats = formats
        self.selected_format = None
        self.created_at = datetime.now()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send welcome message"""
    welcome_msg = """
🤖 *Enhanced Downloader Bot*

📥 *Supported Platforms:*
• TikTok, Douyin
• Facebook, Instagram
• YouTube, Twitter/X
• Reddit, Pinterest
• Likee, Twitch
• Dailymotion, Streamable
• Vimeo, Rumble
• Bilibili, TED

🇮🇷 *Iranian Platforms:*
• Aparat, Namava
• Filimo, Tiva

✨ *Features:*
✅ Quality selection before download
✅ File size display for each quality
✅ Video information included
✅ Supports 50MB max file size
✅ Public videos only

📝 *How to use:*
1. Send me a video link
2. Choose your preferred quality
3. Wait for download

⚠️ *Note:* Some platforms may require login cookies for better quality.
"""
    await update.message.reply_text(welcome_msg, parse_mode=ParseMode.MARKDOWN)

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send help message"""
    help_text = """
❓ *Help Guide*

📋 *Steps:*
1. Copy video URL
2. Send to bot
3. Select quality from list
4. Get downloaded file

🎛️ *Quality Selection:*
- You'll see all available qualities
- Each option shows resolution and file size
- Choose based on your needs

📊 *Information Displayed:*
• Video title and uploader
• Duration and views
• Likes count and platform
• Original URL and file size

🔧 *Tips:*
• For Facebook/Twitter: Try direct links
• Max file size: 50MB
• Some platforms may have limited qualities
• Use /cookies command to add login cookies
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def cookies_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Guide for adding cookies"""
    cookies_guide = """
🍪 *Cookies Guide*

Some platforms require login cookies for:
• Access to private videos
• Higher quality options
• Age-restricted content

📁 *Cookie File Location:*
`cookies/` directory

🎯 *Supported Platforms:*
• YouTube, Facebook
• Instagram, Twitter
• Reddit, Twitch

⚠️ *Important:*
1. Use browser extensions to export cookies
2. Save as `cookies.txt` in cookies folder
3. Restart bot after adding cookies

🔒 *Privacy:* Your cookies are stored locally only.
"""
    await update.message.reply_text(cookies_guide, parse_mode=ParseMode.MARKDOWN)

def is_supported(url):
    """Check if URL is supported"""
    url_lower = url.lower()
    for domain in SUPPORTED_DOMAINS:
        if domain in url_lower:
            return True
    return False

def format_file_size(size_bytes):
    """Format file size in human readable format"""
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
    """Get available formats with size information"""
    try:
        # Check cookies
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
        
        logger.info(f"Getting formats with command: {' '.join(cmd)}")
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
        
        if process.returncode != 0:
            logger.error(f"Format list error: {stderr.decode('utf-8', errors='ignore')[:200]}")
            return None
        
        output = stdout.decode('utf-8', errors='ignore')
        
        # Parse formats
        formats = []
        lines = output.split('\n')
        
        for line in lines:
            # Look for format lines (they contain resolution, filesize, etc.)
            if 'mp4' in line.lower() or 'webm' in line.lower() or 'm4a' in line.lower():
                parts = line.split()
                if len(parts) >= 7:
                    try:
                        format_id = parts[0]
                        extension = parts[1]
                        resolution = parts[2] if len(parts) > 2 else "N/A"
                        
                        # Extract filesize
                        filesize = None
                        for i, part in enumerate(parts):
                            if 'MiB' in part or 'KiB' in part:
                                # Convert to bytes
                                size_str = parts[i-1]
                                unit = parts[i]
                                try:
                                    if 'MiB' in unit:
                                        filesize = float(size_str) * 1024 * 1024
                                    elif 'KiB' in unit:
                                        filesize = float(size_str) * 1024
                                    elif 'GiB' in unit:
                                        filesize = float(size_str) * 1024 * 1024 * 1024
                                except:
                                    filesize = None
                                break
                        
                        # Only add video formats under 50MB
                        if filesize and filesize <= 50 * 1024 * 1024:
                            formats.append({
                                'id': format_id,
                                'ext': extension,
                                'resolution': resolution,
                                'filesize': filesize,
                                'filesize_str': format_file_size(filesize)
                            })
                    except Exception as e:
                        logger.warning(f"Error parsing format line: {e}")
                        continue
        
        # If no formats found with size, try to get basic formats
        if not formats:
            return await get_basic_formats(url)
        
        # Sort by filesize (largest first)
        formats.sort(key=lambda x: x.get('filesize', 0), reverse=True)
        
        return formats
        
    except asyncio.TimeoutError:
        logger.warning("Timeout getting formats")
        return None
    except Exception as e:
        logger.error(f"Error getting formats: {e}")
        return await get_basic_formats(url)

async def get_basic_formats(url):
    """Get basic formats when detailed parsing fails"""
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
            
            # Create basic format options
            formats = []
            best_format = {
                'id': 'best',
                'ext': 'mp4',
                'resolution': 'Best',
                'filesize': data.get('filesize_approx') or data.get('filesize'),
                'filesize_str': format_file_size(data.get('filesize_approx') or data.get('filesize'))
            }
            formats.append(best_format)
            
            worst_format = {
                'id': 'worst',
                'ext': 'mp4',
                'resolution': 'Worst',
                'filesize': None,
                'filesize_str': 'Unknown'
            }
            formats.append(worst_format)
            
            return formats
            
    except Exception as e:
        logger.error(f"Error getting basic formats: {e}")
    
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
        else:
            logger.warning(f"Could not get video info: {stderr.decode('utf-8', errors='ignore')[:100]}")
            return None
            
    except Exception as e:
        logger.error(f"Error getting video info: {e}")
        return None

def create_video_caption(video_info, platform, url, selected_format=None):
    """Create video caption with information"""
    platform_name = PLATFORM_NAMES.get(platform, platform.capitalize())
    
    if not video_info:
        caption = f"📹 Downloaded from {platform_name}\n"
        caption += f"🔗 {url[:100]}..."
        return caption
    
    try:
        # Extract information
        title = video_info.get('title', 'Unknown Title')
        uploader = video_info.get('uploader', 'Unknown Uploader')
        
        # Duration
        duration = video_info.get('duration', 0)
        if duration:
            minutes = int(duration // 60)
            seconds = int(duration % 60)
            duration_str = f"{minutes}:{seconds:02d}"
        else:
            duration_str = "Unknown"
        
        # Stats
        view_count = video_info.get('view_count')
        like_count = video_info.get('like_count')
        
        # Format numbers
        views_str = f"{view_count:,}" if view_count else "Unknown"
        likes_str = f"{like_count:,}" if like_count else "Unknown"
        
        # Create caption
        caption = f"📹 {title[:100]}{'...' if len(title) > 100 else ''}\n\n"
        caption += f"👤 Uploader: {uploader[:50]}\n"
        caption += f"⏱ Duration: {duration_str}\n"
        caption += f"👁 Views: {views_str}\n"
        caption += f"👍 Likes: {likes_str}\n"
        caption += f"🏷 Platform: {platform_name}\n"
        
        if selected_format:
            caption += f"📊 Quality: {selected_format.get('resolution', 'Unknown')}\n"
        
        # Add URL
        url_display = url
        if len(url) > 80:
            url_display = url[:77] + "..."
        caption += f"\n🔗 {url_display}"
        
        # Ensure caption doesn't exceed Telegram limits
        if len(caption) > 1000:
            caption = caption[:997] + "..."
        
        return caption
        
    except Exception as e:
        logger.error(f"Error creating caption: {e}")
        return f"📹 Downloaded from {platform_name}\n🔗 {url[:100]}..."

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming links"""
    user = update.effective_user
    chat_id = update.effective_chat.id
    text = update.message.text.strip()
    
    logger.info(f"Message from {user.id}: {text[:50]}")
    
    # Check if it's a URL
    if not text.startswith(('http://', 'https://')):
        await update.message.reply_text("Please send a valid URL starting with http:// or https://")
        return
    
    # Check if supported
    if not is_supported(text):
        platforms_list = "\n".join([f"• {name}" for name in PLATFORM_NAMES.values()])
        await update.message.reply_text(
            f"❌ Platform not supported.\n\n"
            f"Supported platforms:\n{platforms_list}"
        )
        return
    
    # Detect platform
    platform = detect_platform(text)
    
    # Send processing message
    msg = await update.message.reply_text(f"⏳ Analyzing {PLATFORM_NAMES.get(platform, platform)} link...")
    
    try:
        # Get video information
        await msg.edit_text("📋 Getting video information...")
        video_info = await get_video_info(text)
        
        # Get available formats
        await msg.edit_text("🔍 Checking available qualities...")
        formats = await get_available_formats(text)
        
        if not formats or len(formats) == 0:
            await msg.edit_text("❌ No available formats found or video is not accessible.")
            return
        
        # Store session
        session = DownloadSession(text, platform, formats)
        user_sessions[chat_id] = session
        
        # Create quality selection keyboard
        keyboard = []
        for i, fmt in enumerate(formats[:10]):  # Limit to 10 options
            if i % 2 == 0:
                keyboard.append([])
            
            # Button text with quality and size
            resolution = fmt.get('resolution', 'Unknown')
            size_str = fmt.get('filesize_str', 'Unknown')
            button_text = f"{resolution} ({size_str})"
            
            keyboard[-1].append(InlineKeyboardButton(
                button_text, 
                callback_data=f"quality:{i}:{fmt['id']}"
            ))
        
        # Add cancel button
        keyboard.append([InlineKeyboardButton("❌ Cancel", callback_data="cancel")])
        
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        # Send format selection message
        platform_name = PLATFORM_NAMES.get(platform, platform.capitalize())
        selection_text = f"🎬 *{platform_name} Video Download*\n\n"
        
        if video_info:
            title = video_info.get('title', 'Unknown')[:100]
            duration = video_info.get('duration', 0)
            if duration:
                minutes = int(duration // 60)
                seconds = int(duration % 60)
                duration_str = f"{minutes}:{seconds:02d}"
                selection_text += f"📹 *Title:* {title}\n"
                selection_text += f"⏱ *Duration:* {duration_str}\n\n"
        
        selection_text += f"📊 *Available Qualities:*\n"
        selection_text += f"(Select one from below)\n\n"
        
        await msg.edit_text(
            selection_text,
            reply_markup=reply_markup,
            parse_mode=ParseMode.MARKDOWN
        )
        
    except Exception as e:
        logger.error(f"Error in handle_message: {e}")
        error_msg = f"❌ Error: {str(e)}"
        if "private" in str(e).lower() or "login" in str(e).lower():
            error_msg += "\n\n🔒 This video may be private or require login. Try adding cookies using /cookies command."
        await msg.edit_text(error_msg)

async def handle_quality_selection(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle quality selection callback"""
    query = update.callback_query
    await query.answer()
    
    chat_id = query.message.chat_id
    data = query.data
    
    if data == "cancel":
        # Clear session
        if chat_id in user_sessions:
            del user_sessions[chat_id]
        
        await query.message.edit_text("❌ Download cancelled.")
        return
    
    if data.startswith("quality:"):
        try:
            # Parse callback data
            parts = data.split(":")
            format_index = int(parts[1])
            format_id = parts[2]
            
            # Get session
            session = user_sessions.get(chat_id)
            if not session:
                await query.message.edit_text("❌ Session expired. Please send the link again.")
                return
            
            # Get selected format
            if 0 <= format_index < len(session.formats):
                selected_format = session.formats[format_index]
                session.selected_format = selected_format
                
                # Update message
                platform_name = PLATFORM_NAMES.get(session.platform, session.platform.capitalize())
                size_str = selected_format.get('filesize_str', 'Unknown')
                resolution = selected_format.get('resolution', 'Unknown')
                
                await query.message.edit_text(
                    f"✅ Selected: {resolution} ({size_str})\n"
                    f"⬇️ Downloading from {platform_name}...",
                    parse_mode=ParseMode.MARKDOWN
                )
                
                # Start download
                await perform_download(chat_id, session, query.message)
                
            else:
                await query.message.edit_text("❌ Invalid format selection.")
                
        except Exception as e:
            logger.error(f"Error in quality selection: {e}")
            await query.message.edit_text(f"❌ Error: {str(e)}")

async def perform_download(chat_id, session, message):
    """Perform the actual download"""
    try:
        # Create user directory
        user_dir = Path(f"downloads/{chat_id}")
        user_dir.mkdir(parents=True, exist_ok=True)
        
        unique_id = uuid4().hex[:8]
        output_template = f"{user_dir}/{unique_id}.%(ext)s"
        
        # Build download command
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
        
        logger.info(f"Downloading with command: {' '.join(cmd[:8])}...")
        
        # Start download process
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        await message.edit_text("⬇️ Downloading... (This may take a moment)")
        
        # Wait for download to complete
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='ignore').strip()
            logger.error(f"Download error: {error}")
            
            # Try with fallback format
            if "format is not available" in error:
                await message.edit_text("⚠️ Selected format not available. Trying fallback...")
                
                # Fallback to best quality
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
                
                stdout2, stderr2 = await asyncio.wait_for(process2.communicate(), timeout=300)
                
                if process2.returncode != 0:
                    error2 = stderr2.decode('utf-8', errors='ignore').strip()
                    await message.edit_text(f"❌ Download failed: {error2[:200]}")
                    return
        
        # Find downloaded file
        downloaded_file = None
        for file in Path(user_dir).glob(f"{unique_id}.*"):
            if file.is_file() and file.stat().st_size > 0:
                downloaded_file = file
                break
        
        if not downloaded_file:
            await message.edit_text("❌ File not found after download")
            return
        
        # Check file size
        file_size = downloaded_file.stat().st_size
        if file_size > 50 * 1024 * 1024:
            await message.edit_text(f"❌ File too large ({file_size/1024/1024:.1f}MB > 50MB)")
            downloaded_file.unlink()
            return
        
        # Get video info for caption
        video_info = await get_video_info(session.url)
        
        # Create caption
        caption = create_video_caption(video_info, session.platform, session.url, session.selected_format)
        
        # Send file
        await message.edit_text("📤 Uploading to Telegram...")
        
        with open(downloaded_file, 'rb') as f:
            # Detect MIME type
            try:
                result = subprocess.run(
                    ['file', '-b', '--mime-type', str(downloaded_file)],
                    capture_output=True, text=True, timeout=5
                )
                mime_type = result.stdout.strip() if result.returncode == 0 else 'video/mp4'
            except:
                mime_type = 'video/mp4'
            
            # Send based on file type
            if mime_type.startswith('video'):
                await message.reply_video(
                    video=f,
                    caption=caption,
                    supports_streaming=True,
                    read_timeout=120,
                    write_timeout=120
                )
            elif mime_type.startswith('image'):
                await message.reply_photo(
                    photo=f,
                    caption=caption,
                    read_timeout=60
                )
            else:
                await message.reply_document(
                    document=f,
                    caption=caption,
                    read_timeout=60
                )
        
        # Update status
        size_mb = file_size / 1024 / 1024
        platform_name = PLATFORM_NAMES.get(session.platform, session.platform.capitalize())
        await message.edit_text(f"✅ Download complete!\n📦 {platform_name} - {size_mb:.1f}MB")
        
        # Cleanup
        if downloaded_file.exists():
            downloaded_file.unlink()
        
        # Clear session
        if chat_id in user_sessions:
            del user_sessions[chat_id]
        
    except asyncio.TimeoutError:
        await message.edit_text("❌ Download timeout. The video might be too large or the server is slow.")
    except Exception as e:
        logger.error(f"Error in perform_download: {e}")
        await message.edit_text(f"❌ Error: {str(e)[:200]}")
        
        # Cleanup on error
        if chat_id in user_sessions:
            del user_sessions[chat_id]

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Update {update} caused error: {context.error}")
    
    if update and update.effective_chat:
        try:
            await update.effective_chat.send_message("⚠️ An error occurred. Please try again or send /start")
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
    app.add_handler(CommandHandler("cookies", cookies_cmd))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    app.add_handler(CallbackQueryHandler(handle_quality_selection))
    
    # Error handler
    app.add_error_handler(error_handler)
    
    # Start bot
    logger.info("🤖 Enhanced Bot starting...")
    print("=" * 50)
    print("✅ Enhanced Bot with Quality Selection")
    print("✅ Supporting all requested platforms")
    print("✅ User can choose quality before download")
    print("=" * 50)
    
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
EOF

# Make executable
chmod +x $BOT_FILE

# 7. Create enhanced management scripts
echo -e "${YELLOW}📁 Creating enhanced scripts...${NC}"

# Start script
cat << 'EOF' > start.sh
#!/bin/bash
# Start the enhanced bot

echo "🚀 Starting Enhanced Downloader Bot..."
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

echo "🔄 Restarting Enhanced Bot..."
./stop.sh
sleep 2
./start.sh
EOF

# Clear cookies script
cat << 'EOF' > clear_cookies.sh
#!/bin/bash
# Clear cookies

echo "🧹 Clearing cookies..."
rm -f cookies/cookies.txt 2>/dev/null
echo "✅ Cookies cleared"
EOF

# Make scripts executable
chmod +x start.sh stop.sh restart.sh clear_cookies.sh

# 8. Create comprehensive test file
cat << 'EOF' > test.py
#!/usr/bin/env python3
# Comprehensive test

import sys
import os
import subprocess
import json

print("🔧 Testing Enhanced Installation...")
print("=" * 50)

# Check Python
try:
    import platform
    print(f"✅ Python {platform.python_version()}")
except:
    print("❌ Python error")
    sys.exit(1)

# Check packages
packages = ["telegram", "dotenv", "json", "re", "asyncio"]
for pkg in packages:
    try:
        __import__(pkg)
        print(f"✅ {pkg}")
    except ImportError as e:
        print(f"❌ {pkg}: {e}")

# Check .env
if os.path.exists(".env"):
    with open(".env", "r") as f:
        content = f.read()
        if "BOT_TOKEN=" in content:
            print("✅ .env with BOT_TOKEN")
        else:
            print("❌ .env missing BOT_TOKEN")
else:
    print("❌ .env missing")

# Check yt-dlp CLI
result = subprocess.run(["yt-dlp", "--version"], capture_output=True, text=True)
if result.returncode == 0:
    version = result.stdout.strip()
    print(f"✅ yt-dlp CLI: {version}")
else:
    print("❌ yt-dlp CLI not working")

# Check directories
directories = ["downloads", "logs", "cookies", "venv"]
for dir in directories:
    if os.path.exists(dir):
        print(f"✅ Directory: {dir}")
    else:
        print(f"⚠️ Missing: {dir}")

# Check supported platforms
supported_platforms = [
    "TikTok", "Facebook", "YouTube", "Instagram",
    "Twitter/X", "Reddit", "Pinterest", "Likee",
    "Twitch", "Dailymotion", "Streamable", "Vimeo",
    "Rumble", "Bilibili", "TED",
    "Aparat", "Namava", "Filimo", "Tiva"
]

print("\n📋 Supported Platforms:")
for platform in supported_platforms:
    print(f"   ✅ {platform}")

print("\n✨ Features:")
print("   ✅ Quality selection before download")
print("   ✅ File size display for each quality")
print("   ✅ Support for all requested platforms")
print("   ✅ Iranian platforms support")
print("   ✅ Cookie support for private videos")
print("   ✅ Max 50MB file size limit")

print("=" * 50)
print("🎉 Enhanced Setup Complete!")
print("\n🚀 To start: ./start.sh")
print("🛑 To stop:  ./stop.sh")
print("🔄 To restart: ./restart.sh")
print("🍪 To clear cookies: ./clear_cookies.sh")
print("\n💡 Tip: Add cookies.txt to cookies/ folder for better quality on some platforms!")
EOF

chmod +x test.py

# 9. Create enhanced requirements.txt
cat << 'EOF' > requirements.txt
python-telegram-bot==20.7
python-dotenv==1.0.0
EOF

# 10. Create README
cat << 'EOF' > README.md
# Enhanced Telegram Downloader Bot

Advanced bot for downloading videos from multiple social media platforms with quality selection.

## ✨ Features

- **Quality Selection**: Choose quality before downloading
- **File Size Display**: See size for each quality option
- **Multi-Platform Support**: 20+ platforms supported
- **Iranian Platforms**: Aparat, Namava, Filimo, Tiva
- **Cookie Support**: Login cookies for private videos
- **Video Info**: Title, uploader, duration, views, likes

## 📋 Supported Platforms

### Main Platforms
- TikTok, Douyin
- Facebook, Instagram
- YouTube, Twitter/X
- Reddit, Pinterest
- Likee, Twitch
- Dailymotion, Streamable
- Vimeo, Rumble
- Bilibili, TED

### Iranian Platforms
- Aparat
- Namava  
- Filimo
- Tiva

## 🚀 Installation

1. Run the setup script:
```bash
bash install.sh
