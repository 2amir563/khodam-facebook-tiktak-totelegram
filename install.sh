#!/usr/bin/env python3
"""
Telegram Video Downloader Bot with Quality Selection
Supports: TikTok, Facebook, YouTube, Instagram, Twitter/X, Reddit, Pinterest, Likee, Twitch, Dailymotion, Streamable, Vimeo, Rumble, Bilibili, TED, Aparat, Namava, Filimo, Tiva
NO 50MB LIMIT - All platforms supported without size restriction
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
    level=logging.INFO,
    handlers=[
        logging.FileHandler('logs/bot.log'),
        logging.StreamHandler()
    ]
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
✅ NO 50MB LIMIT - Full quality downloads
✅ Public videos supported

📝 *How to use:*
1. Send me a video link
2. Select your preferred quality
3. Wait for download to complete

⚠️ *Note:* Large files may take longer to download and upload.
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

⚠️ *Important:*
• NO 50MB LIMIT - Full quality downloads
• Large files may take time
• Public videos only
• Some platforms may need cookies
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
    """Get available formats with size information - FIXED for Aparat"""
    try:
        # Check cookies
        cookies_path = "cookies/cookies.txt"
        cookies_args = []
        if os.path.exists(cookies_path):
            cookies_args = ["--cookies", cookies_path]
        
        # Method 1: Try JSON dump first (more reliable)
        cmd_json = [
            "yt-dlp",
            *cookies_args,
            "--dump-json",
            "--no-warnings",
            "--skip-download",
            url
        ]
        
        logger.info(f"Getting formats via JSON: {' '.join(cmd_json)}")
        process_json = await asyncio.create_subprocess_exec(
            *cmd_json,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process_json.communicate(), timeout=30)
        
        if process_json.returncode == 0:
            try:
                data = json.loads(stdout.decode('utf-8', errors='ignore'))
                formats = []
                
                # If formats are in the JSON data
                if 'formats' in data and data['formats']:
                    for fmt in data['formats']:
                        try:
                            format_id = fmt.get('format_id', 'unknown')
                            ext = fmt.get('ext', 'mp4')
                            resolution = fmt.get('resolution', 'N/A')
                            
                            # Get filesize
                            filesize = fmt.get('filesize') or fmt.get('filesize_approx')
                            
                            # NO 50MB LIMIT - Include all formats
                            formats.append({
                                'id': format_id,
                                'ext': ext,
                                'resolution': resolution,
                                'filesize': filesize,
                                'filesize_str': format_file_size(filesize)
                            })
                        except Exception as e:
                            logger.warning(f"Error parsing format from JSON: {e}")
                            continue
                    
                    # Sort by resolution if possible
                    if formats:
                        def get_resolution_num(res):
                            if isinstance(res, str) and 'x' in res:
                                try:
                                    return int(res.split('x')[0])
                                except:
                                    return 0
                            return 0
                        
                        formats.sort(key=lambda x: get_resolution_num(x.get('resolution', '')), reverse=True)
                        logger.info(f"Found {len(formats)} formats via JSON")
                        return formats
                
                # If no formats in JSON, try to create basic format from main data
                if 'format_id' in data or 'url' in data:
                    format_id = data.get('format_id', 'best')
                    ext = data.get('ext', 'mp4')
                    resolution = data.get('resolution', 'Best available')
                    filesize = data.get('filesize') or data.get('filesize_approx')
                    
                    return [{
                        'id': format_id,
                        'ext': ext,
                        'resolution': resolution,
                        'filesize': filesize,
                        'filesize_str': format_file_size(filesize)
                    }]
                    
            except json.JSONDecodeError:
                logger.warning("JSON decode failed, trying list-formats")
        
        # Method 2: Try list-formats as fallback
        cmd_list = [
            "yt-dlp",
            *cookies_args,
            "--list-formats",
            "--no-warnings",
            url
        ]
        
        logger.info(f"Getting formats via list-formats: {' '.join(cmd_list)}")
        process_list = await asyncio.create_subprocess_exec(
            *cmd_list,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout_list, stderr_list = await asyncio.wait_for(process_list.communicate(), timeout=30)
        
        if process_list.returncode == 0:
            output = stdout_list.decode('utf-8', errors='ignore')
            return await parse_formats_from_output(output)
        else:
            logger.error(f"List-formats failed: {stderr_list.decode('utf-8', errors='ignore')[:200]}")
            # Final fallback: return basic format options
            return await get_basic_formats(url)
            
    except asyncio.TimeoutError:
        logger.warning("Timeout getting formats")
        return await get_basic_formats(url)
    except Exception as e:
        logger.error(f"Error getting formats: {e}")
        return await get_basic_formats(url)

async def parse_formats_from_output(output):
    """Parse formats from yt-dlp --list-formats output"""
    formats = []
    lines = output.split('\n')
    
    for line in lines:
        # Look for video/audio format lines
        line_lower = line.lower()
        if any(x in line_lower for x in ['mp4', 'webm', 'm4a', 'video', 'audio', 'hd', 'sd', 'p', 'k']):
            parts = line.split()
            if len(parts) >= 4:
                try:
                    format_id = parts[0]
                    extension = parts[1] if len(parts) > 1 else 'mp4'
                    resolution = parts[2] if len(parts) > 2 else "N/A"
                    
                    # Extract filesize
                    filesize = None
                    for i, part in enumerate(parts):
                        if 'mib' in part.lower() or 'kib' in part.lower() or 'gib' in part.lower():
                            size_str = parts[i-1] if i > 0 else '0'
                            try:
                                size_val = float(size_str)
                                if 'gib' in part.lower():
                                    filesize = size_val * 1024 * 1024 * 1024
                                elif 'mib' in part.lower():
                                    filesize = size_val * 1024 * 1024
                                elif 'kib' in part.lower():
                                    filesize = size_val * 1024
                            except:
                                filesize = None
                            break
                    
                    # NO 50MB LIMIT - Include all formats
                    formats.append({
                        'id': format_id,
                        'ext': extension,
                        'resolution': resolution,
                        'filesize': filesize,
                        'filesize_str': format_file_size(filesize)
                    })
                except Exception as e:
                    continue
    
    # Sort by resolution if possible
    if formats:
        def get_resolution_num(res):
            if isinstance(res, str):
                if 'x' in res:
                    try:
                        return int(res.split('x')[0])
                    except:
                        pass
                # Try to extract numbers like 1080, 720, etc.
                import re
                numbers = re.findall(r'\d+', res)
                if numbers:
                    return int(numbers[-1])
            return 0
        
        formats.sort(key=lambda x: get_resolution_num(x.get('resolution', '')), reverse=True)
    
    return formats if formats else None

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
            
            # Best quality option
            formats.append({
                'id': 'best',
                'ext': 'mp4',
                'resolution': 'Best Quality',
                'filesize': data.get('filesize_approx') or data.get('filesize'),
                'filesize_str': format_file_size(data.get('filesize_approx') or data.get('filesize'))
            })
            
            # Worst quality option
            formats.append({
                'id': 'worst',
                'ext': 'mp4',
                'resolution': 'Low Quality',
                'filesize': None,
                'filesize_str': 'Unknown'
            })
            
            # Medium quality option if available
            if 'height' in data:
                height = data.get('height', 0)
                if height > 480:
                    formats.append({
                        'id': f'best[height<={height//2}]',
                        'ext': 'mp4',
                        'resolution': f'Medium ({height//2}p)',
                        'filesize': None,
                        'filesize_str': 'Unknown'
                    })
            
            return formats
    except Exception as e:
        logger.error(f"Error getting basic formats: {e}")
    
    # Absolute fallback
    return [
        {
            'id': 'best',
            'ext': 'mp4',
            'resolution': 'Best Available',
            'filesize': None,
            'filesize_str': 'Unknown'
        }
    ]

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
            
            # Add file size if available
            filesize_str = selected_format.get('filesize_str')
            if filesize_str and filesize_str != 'Unknown':
                caption += f"📦 Size: {filesize_str}\n"
        
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
            await msg.edit_text("❌ No available formats found. The video might be private or restricted.")
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
            
            # Truncate if too long
            if len(button_text) > 30:
                button_text = button_text[:27] + "..."
            
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
        
        # Show first few formats in message
        for i, fmt in enumerate(formats[:3]):
            resolution = fmt.get('resolution', 'Unknown')
            size_str = fmt.get('filesize_str', 'Unknown')
            selection_text += f"• {resolution} ({size_str})\n"
        
        if len(formats) > 3:
            selection_text += f"• ... and {len(formats) - 3} more\n"
        
        await msg.edit_text(
            selection_text,
            reply_markup=reply_markup,
            parse_mode=ParseMode.MARKDOWN
        )
        
    except Exception as e:
        logger.error(f"Error in handle_message: {e}")
        error_msg = f"❌ Error: {str(e)[:200]}"
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
            await query.message.edit_text(f"❌ Error: {str(e)[:200]}")

async def perform_download(chat_id, session, message):
    """Perform the actual download - NO 50MB LIMIT"""
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
        
        # NO 50MB LIMIT - Removed --max-filesize parameter
        cmd = [
            "yt-dlp",
            *cookies_args,
            "--no-warnings",
            "--format", session.selected_format['id'],
            # "--max-filesize", "50M",  # REMOVED - No size limit
            "--restrict-filenames",
            "-o", output_template,
            session.url
        ]
        
        logger.info(f"Downloading with command: {' '.join(cmd)}")
        
        # Start download process
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        await message.edit_text("⬇️ Downloading... (This may take a moment for large files)")
        
        # Wait for download to complete - longer timeout for large files
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=600)  # 10 minutes timeout
        
        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='ignore').strip()
            logger.error(f"Download error: {error}")
            
            # Try with fallback format
            if "format is not available" in error or "unable to download" in error:
                await message.edit_text("⚠️ Selected format not available. Trying fallback...")
                
                # Fallback to best quality
                fallback_cmd = [
                    "yt-dlp",
                    *cookies_args,
                    "--no-warnings",
                    "--format", "best",  # Simple best format
                    # "--max-filesize", "50M",  # REMOVED - No size limit
                    "--restrict-filenames",
                    "-o", output_template,
                    session.url
                ]
                
                process2 = await asyncio.create_subprocess_exec(
                    *fallback_cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                
                stdout2, stderr2 = await asyncio.wait_for(process2.communicate(), timeout=600)
                
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
        
        # NO 50MB LIMIT CHECK - Removed file size check
        
        # Get video info for caption
        video_info = await get_video_info(session.url)
        
        # Create caption
        caption = create_video_caption(video_info, session.platform, session.url, session.selected_format)
        
        # Send file
        await message.edit_text("📤 Uploading to Telegram... (May take time for large files)")
        
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
                    read_timeout=300,  # Longer timeout for large files
                    write_timeout=300,
                    connect_timeout=300
                )
            elif mime_type.startswith('image'):
                await message.reply_photo(
                    photo=f,
                    caption=caption,
                    read_timeout=120
                )
            else:
                await message.reply_document(
                    document=f,
                    caption=caption,
                    read_timeout=120
                )
        
        # Update status
        file_size = downloaded_file.stat().st_size
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
        logger.error("❌ BOT_TOKEN not found! Please set it in .env file")
        print("❌ BOT_TOKEN not found! Please set it in .env file")
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
    print("✅ Video Downloader Bot with Quality Selection")
    print("✅ NO 50MB LIMIT - Full quality downloads")
    print("✅ Supports 20+ platforms including Aparat")
    print("=" * 50)
    print("🤖 Bot is running. Press Ctrl+C to stop.")
    print("=" * 50)
    
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    # Ensure logs directory exists
    Path("logs").mkdir(exist_ok=True)
    
    main()
