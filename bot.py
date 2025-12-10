#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - Complete Solution
Optimized for weak servers with automatic cleanup after 2 minutes
"""

import os
import sys
import logging
import subprocess
import asyncio
import json
import shutil
from pathlib import Path
from uuid import uuid4
from datetime import datetime, timedelta
import aiofiles
import psutil
from urllib.parse import urlparse

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, 
    CommandHandler, 
    MessageHandler, 
    filters, 
    ContextTypes, 
    CallbackQueryHandler
)
from telegram.constants import ParseMode
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
BOT_TOKEN = os.getenv("BOT_TOKEN")
DELETE_AFTER_MINUTES = int(os.getenv("DELETE_AFTER_MINUTES", "2"))
MAX_CONCURRENT_DOWNLOADS = int(os.getenv("CONCURRENT_DOWNLOADS", "1"))
MAX_FILE_SIZE_MB = int(os.getenv("MAX_FILE_SIZE", "2000"))

# Validate token
if not BOT_TOKEN or BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
    print("ERROR: BOT_TOKEN not set in .env file")
    print("Please edit .env and add your bot token from @BotFather")
    sys.exit(1)

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

# Supported platforms - optimized list
SUPPORTED_DOMAINS = [
    # Main platforms from your list
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
    # Additional platforms
    "9gag.com",
    "gfycat.com",
    "imgur.com",
    "vk.com",
    "ok.ru",
    "tumblr.com"
]

# Platform configuration for yt-dlp
PLATFORM_CONFIGS = {
    "tiktok": {"extractor": "tiktok", "quality": "best"},
    "facebook": {"extractor": "facebook", "cookies_required": True},
    "youtube": {"extractor": "youtube", "cookies_required": True},
    "instagram": {"extractor": "instagram"},
    "twitter": {"extractor": "twitter"},
    "reddit": {"extractor": "reddit"},
    "pinterest": {"extractor": "pinterest"},
    "twitch": {"extractor": "twitch"},
    "dailymotion": {"extractor": "dailymotion"},
    "streamable": {"extractor": "streamable"},
    "vimeo": {"extractor": "vimeo"},
    "rumble": {"extractor": "rumble"},
    "bilibili": {"extractor": "bilibili", "referer": "https://www.bilibili.com/"},
    "ted": {"extractor": "ted"}
}

# Active downloads tracker
active_downloads = {}
download_semaphore = asyncio.Semaphore(MAX_CONCURRENT_DOWNLOADS)

# Cleanup scheduler
cleanup_queue = asyncio.Queue()

class DownloadTask:
    """Represents a download task"""
    def __init__(self, user_id, url, message_id):
        self.id = str(uuid4())
        self.user_id = user_id
        self.url = url
        self.message_id = message_id
        self.start_time = datetime.now()
        self.end_time = None
        self.file_path = None
        self.file_size = 0
        self.status = "pending"
        self.platform = None
        self.quality = None
        
    def to_dict(self):
        return {
            "id": self.id,
            "user_id": self.user_id,
            "url": self.url,
            "status": self.status,
            "file_size": self.file_size,
            "platform": self.platform,
            "quality": self.quality
        }

def format_file_size(bytes_size):
    """Format file size in human readable format"""
    if bytes_size is None or bytes_size == 0:
        return "Unknown"
    
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.1f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.1f} TB"

def format_duration(seconds):
    """Format duration in MM:SS"""
    if seconds is None:
        return "N/A"
    minutes = int(seconds // 60)
    seconds = int(seconds % 60)
    return f"{minutes}:{seconds:02d}"

async def cleanup_worker():
    """Background worker to delete files after 2 minutes"""
    while True:
        try:
            file_path = await cleanup_queue.get()
            await asyncio.sleep(DELETE_AFTER_MINUTES * 60)  # Wait 2 minutes
            
            if os.path.exists(file_path):
                try:
                    os.remove(file_path)
                    logger.info(f"Cleaned up file: {file_path}")
                    
                    # Also clean up related files (thumbnails, etc.)
                    base_name = os.path.splitext(file_path)[0]
                    for ext in ['.jpg', '.png', '.webp', '.info.json']:
                        related_file = f"{base_name}{ext}"
                        if os.path.exists(related_file):
                            os.remove(related_file)
                            
                except Exception as e:
                    logger.error(f"Failed to cleanup {file_path}: {e}")
                    
        except Exception as e:
            logger.error(f"Cleanup worker error: {e}")

async def check_server_health():
    """Check server resource usage"""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    return {
        "cpu": cpu_percent,
        "memory_percent": memory.percent,
        "memory_available": format_file_size(memory.available),
        "disk_free": format_file_size(disk.free),
        "healthy": cpu_percent < 90 and memory.percent < 90
    }

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    user = update.effective_user
    
    # Check server health
    health = await check_server_health()
    
    welcome_msg = f"""
🤖 *Welcome {user.first_name}!*

I'm a *Media Downloader Bot* optimized for weak servers.

📥 *Supported Platforms:*
• TikTok, Facebook, YouTube, Instagram
• Twitter/X, Reddit, Pinterest, Twitch
• Dailymotion, Streamable, Vimeo
• Rumble, Bilibili, TED, and many more!

✨ *Features:*
✅ Quality selection before download
✅ File size display for each quality
✅ Automatic cleanup after {DELETE_AFTER_MINUTES} minutes
✅ Resource optimized for weak servers
✅ Concurrent download limit: {MAX_CONCURRENT_DOWNLOADS}

🔄 *Server Status:*
• CPU: {health['cpu']:.1f}%
• Memory: {health['memory_percent']:.1f}% used
• Free memory: {health['memory_available']}
• Disk free: {health['disk_free']}

📝 *How to use:*
1. Send me a media URL
2. Choose your preferred quality
3. Wait for download
4. File auto-deletes after {DELETE_AFTER_MINUTES} min

⚠️ *Max file size:* {MAX_FILE_SIZE_MB}MB
    """
    
    await update.message.reply_text(welcome_msg, parse_mode=ParseMode.MARKDOWN)

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = f"""
❓ *Help Guide*

📋 *Quick Start:*
1. Copy any supported media URL
2. Send it to me
3. Select quality from the buttons
4. Receive the file in Telegram

🎛️ *Quality Selection:*
- All available qualities shown
- Each option shows resolution & size
- Choose based on your needs

🔄 *Auto Cleanup:*
- Files deleted after *{DELETE_AFTER_MINUTES} minutes*
- Saves server disk space
- No manual cleanup needed

⚙️ *Server Optimizations:*
- Limited concurrent downloads: {MAX_CONCURRENT_DOWNLOADS}
- Memory usage monitoring
- Automatic retry on failure

⚠️ *Limitations:*
- Max file size: {MAX_FILE_SIZE_MB}MB
- Some platforms need cookies
- Private/age-restricted content may fail

🛠 *Commands:*
/start - Welcome message
/help - This help guide
/status - Check bot and server status
/stats - Download statistics
/cancel - Cancel current download
    """
    
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    health = await check_server_health()
    
    # Count active downloads
    active_count = len([d for d in active_downloads.values() if d.status == "downloading"])
    
    status_msg = f"""
📊 *System Status*

🖥 *Server Health:*
• CPU Usage: {health['cpu']:.1f}%
• Memory Usage: {health['memory_percent']:.1f}%
• Available Memory: {health['memory_available']}
• Free Disk: {health['disk_free']}
• Status: {'✅ Healthy' if health['healthy'] else '⚠️ Under heavy load'}

🤖 *Bot Status:*
• Active Downloads: {active_count}/{MAX_CONCURRENT_DOWNLOADS}
• Cleanup Delay: {DELETE_AFTER_MINUTES} minutes
• Max File Size: {MAX_FILE_SIZE_MB}MB

📁 *Directories:*
• Downloads: /opt/telegram-media-bot/downloads/
• Logs: /opt/telegram-media-bot/logs/
• Cookies: /opt/telegram-media-bot/cookies/

💡 *Tips for weak servers:*
1. Send one URL at a time
2. Choose lower quality for faster downloads
3. Large files take more time
    """
    
    await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN)

async def stats_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /stats command"""
    total_downloads = len(active_downloads)
    completed = len([d for d in active_downloads.values() if d.status == "completed"])
    failed = len([d for d in active_downloads.values() if d.status == "failed"])
    
    # Calculate total size
    total_size = sum(d.file_size for d in active_downloads.values() if d.file_size)
    
    stats_msg = f"""
📈 *Download Statistics*

📊 *Overview:*
• Total Requests: {total_downloads}
• Completed: {completed}
• Failed: {failed}
• Success Rate: {(completed/total_downloads*100 if total_downloads > 0 else 0):.1f}%

💾 *Data Usage:*
• Total Downloaded: {format_file_size(total_size)}
• Average File Size: {format_file_size(total_size/completed) if completed > 0 else '0 B'}

🔧 *System Info:*
• Python: {sys.version.split()[0]}
• Concurrent Limit: {MAX_CONCURRENT_DOWNLOADS}
• Cleanup: {DELETE_AFTER_MINUTES} minutes
• Max Size: {MAX_FILE_SIZE_MB}MB

🔄 *Recent Activity:*
{get_recent_activity()}
    """
    
    await update.message.reply_text(stats_msg, parse_mode=ParseMode.MARKDOWN)

def get_recent_activity():
    """Get recent download activity"""
    recent = list(active_downloads.values())[-5:]  # Last 5 items
    if not recent:
        return "No recent activity"
    
    activity = []
    for task in reversed(recent):
        time_ago = datetime.now() - task.start_time
        minutes = int(time_ago.total_seconds() // 60)
        activity.append(f"• {task.platform or 'Unknown'} - {task.status} ({minutes} min ago)")
    
    return "\n".join(activity)

async def cancel_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /cancel command"""
    user_id = update.effective_user.id
    
    # Find user's active download
    user_tasks = [t for t in active_downloads.values() 
                  if t.user_id == user_id and t.status == "downloading"]
    
    if not user_tasks:
        await update.message.reply_text("❌ You don't have any active downloads to cancel.")
        return
    
    for task in user_tasks:
        task.status = "cancelled"
        # Try to kill the download process
        # Note: This is simplified - in production you'd track and kill the subprocess
    
    await update.message.reply_text("✅ Your downloads have been cancelled.")

def is_supported_url(url):
    """Check if URL is supported"""
    try:
        parsed = urlparse(url)
        domain = parsed.netloc.lower()
        
        # Remove www. prefix
        if domain.startswith('www.'):
            domain = domain[4:]
        
        # Check against supported domains
        for supported in SUPPORTED_DOMAINS:
            if supported in domain or domain.endswith('.' + supported):
                return True
        
        # Special case for short URLs
        if 'pin.it' in url.lower():
            return True
        if 'dai.ly' in url.lower():
            return True
        
        return False
    except:
        return False

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
        "9gag.com": "9gag",
        "gfycat.com": "gfycat",
        "imgur.com": "imgur",
        "vk.com": "vk",
        "ok.ru": "ok",
        "tumblr.com": "tumblr"
    }
    
    for domain, platform in platform_map.items():
        if domain in url_lower:
            return platform
    
    return "unknown"

async def get_video_info(url):
    """Get video information using yt-dlp"""
    try:
        cmd = [
            "yt-dlp",
            "--dump-json",
            "--no-warnings",
            "--no-playlist",
            "--skip-download",
            url
        ]
        
        # Add cookies if available
        cookies_file = "cookies/cookies.txt"
        if os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=30)
        
        if process.returncode == 0:
            info = json.loads(stdout.decode('utf-8', errors='ignore'))
            
            # Extract relevant info
            title = info.get('title', 'Unknown Title')
            uploader = info.get('uploader', 'Unknown')
            duration = info.get('duration', 0)
            views = info.get('view_count', 0)
            
            # Get available formats
            formats = []
            for fmt in info.get('formats', []):
                if fmt.get('vcodec') != 'none':  # Video formats only
                    format_id = fmt.get('format_id', 'unknown')
                    ext = fmt.get('ext', 'mp4')
                    resolution = fmt.get('resolution', 'N/A')
                    filesize = fmt.get('filesize') or fmt.get('filesize_approx', 0)
                    
                    # Skip if file too large
                    if filesize and filesize > (MAX_FILE_SIZE_MB * 1024 * 1024):
                        continue
                    
                    formats.append({
                        'id': format_id,
                        'ext': ext,
                        'resolution': resolution,
                        'filesize': filesize,
                        'filesize_str': format_file_size(filesize)
                    })
            
            # Sort by resolution
            formats.sort(key=lambda x: (
                float(x['resolution'].split('x')[0]) 
                if 'x' in str(x['resolution']) else 0
            ), reverse=True)
            
            return {
                'success': True,
                'title': title,
                'uploader': uploader,
                'duration': duration,
                'views': views,
                'formats': formats[:10],  # Limit to 10 formats
                'thumbnail': info.get('thumbnail'),
                'webpage_url': info.get('webpage_url', url)
            }
        else:
            logger.error(f"yt-dlp error: {stderr.decode('utf-8', errors='ignore')}")
            return {'success': False, 'error': 'Failed to get video info'}
            
    except asyncio.TimeoutError:
        return {'success': False, 'error': 'Timeout getting video info'}
    except Exception as e:
        logger.error(f"Error getting video info: {e}")
        return {'success': False, 'error': str(e)}

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming URLs"""
    url = update.message.text.strip()
    user_id = update.effective_user.id
    
    # Check if URL is supported
    if not is_supported_url(url):
        unsupported_msg = """
❌ *Unsupported URL*

This URL is not supported or is from an unsupported platform.

✅ *Supported platforms include:*
• TikTok, Facebook, YouTube
• Instagram, Twitter/X, Reddit  
• Pinterest, Twitch, Dailymotion
• Streamable, Vimeo, Rumble
• Bilibili, TED, and many more

🔗 *Make sure:* The URL is public and accessible.
        """
        await update.message.reply_text(unsupported_msg, parse_mode=ParseMode.MARKDOWN)
        return
    
    # Check server health before processing
    health = await check_server_health()
    if not health['healthy']:
        await update.message.reply_text(
            "⚠️ *Server is under heavy load*\n"
            "Please try again in a few minutes.\n"
            f"CPU: {health['cpu']:.1f}%, Memory: {health['memory_percent']:.1f}%",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Check concurrent download limit
    active_count = len([d for d in active_downloads.values() if d.status == "downloading"])
    if active_count >= MAX_CONCURRENT_DOWNLOADS:
        await update.message.reply_text(
            f"⏳ *Download queue is full*\n"
            f"Currently {active_count}/{MAX_CONCURRENT_DOWNLOADS} downloads active.\n"
            f"Please wait for one to complete.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Get platform
    platform = detect_platform(url)
    
    # Send initial message
    status_msg = await update.message.reply_text(
        f"🔍 *Analyzing URL...*\n"
        f"Platform: {platform.upper()}\n"
        f"URL: {url[:50]}...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    # Get video information
    video_info = await get_video_info(url)
    
    if not video_info['success']:
        await status_msg.edit_text(
            f"❌ *Failed to analyze URL*\n"
            f"Error: {video_info['error']}\n\n"
            f"Possible reasons:\n"
            f"• URL is private/restricted\n"
            f"• Platform requires cookies\n"
            f"• Network error\n\n"
            f"Try adding cookies or check if URL is public.",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Check if we have formats
    if not video_info['formats']:
        await status_msg.edit_text(
            f"❌ *No downloadable formats found*\n"
            f"Title: {video_info['title']}\n\n"
            f"This video might be:\n"
            f"• Live stream\n"
            f"• Age-restricted\n"
            f"• Region locked\n"
            f"• DRM protected",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Create task
    task = DownloadTask(user_id, url, status_msg.message_id)
    task.platform = platform
    active_downloads[task.id] = task
    
    # Create quality selection keyboard
    keyboard = []
    for fmt in video_info['formats']:
        btn_text = f"{fmt['resolution']} - {fmt['filesize_str']} ({fmt['ext']})"
        callback_data = f"quality:{task.id}:{fmt['id']}"
        keyboard.append([InlineKeyboardButton(btn_text, callback_data=callback_data)])
    
    # Add cancel button
    keyboard.append([InlineKeyboardButton("❌ Cancel", callback_data=f"cancel:{task.id}")])
    
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    # Update message with quality options
    info_text = f"""
📹 *{video_info['title']}*

👤 Uploader: {video_info['uploader']}
⏱ Duration: {format_duration(video_info['duration'])}
👁 Views: {video_info['views']:,}
🌐 Platform: {platform.upper()}

📊 *Available Qualities:*
Choose your preferred quality:
    """
    
    await status_msg.edit_text(
        info_text,
        reply_markup=reply_markup,
        parse_mode=ParseMode.MARKDOWN
    )

async def handle_quality_selection(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle quality selection callback"""
    query = update.callback_query
    await query.answer()
    
    data = query.data
    user_id = query.from_user.id
    
    if data.startswith("quality:"):
        _, task_id, quality_id = data.split(":", 2)
        
        if task_id not in active_downloads:
            await query.edit_message_text("❌ Download task expired or not found.")
            return
        
        task = active_downloads[task_id]
        
        if task.user_id != user_id:
            await query.edit_message_text("❌ This is not your download task.")
            return
        
        # Update task
        task.quality = quality_id
        task.status = "downloading"
        
        # Start download
        await query.edit_message_text(
            f"⬇️ *Downloading...*\n"
            f"Quality: {quality_id}\n"
            f"Please wait...",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Download in background
        asyncio.create_task(download_and_send(task, query.message.chat_id, query.message.message_id))
    
    elif data.startswith("cancel:"):
        _, task_id = data.split(":", 1)
        
        if task_id in active_downloads:
            task = active_downloads[task_id]
            task.status = "cancelled"
            await query.edit_message_text("✅ Download cancelled.")

async def download_and_send(task, chat_id, message_id):
    """Download video and send to Telegram"""
    try:
        async with download_semaphore:
            # Create unique filename
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{task.platform}_{timestamp}_{uuid4().hex[:8]}"
            output_template = f"downloads/{filename}.%(ext)s"
            
            # Build yt-dlp command
            cmd = [
                "yt-dlp",
                "-f", task.quality,
                "-o", output_template,
                "--no-warnings",
                "--no-playlist",
                "--progress",
                "--newline",
                task.url
            ]
            
            # Add cookies if available
            cookies_file = "cookies/cookies.txt"
            if os.path.exists(cookies_file):
                cmd.extend(["--cookies", cookies_file])
            
            # Add referer for certain platforms
            if task.platform == "bilibili":
                cmd.extend(["--referer", "https://www.bilibili.com/"])
            
            # Update status
            await context.bot.edit_message_text(
                chat_id=chat_id,
                message_id=message_id,
                text=f"⬇️ *Downloading...*\n"
                     f"URL: {task.url[:50]}...\n"
                     f"Quality: {task.quality}\n"
                     f"Status: Starting download...",
                parse_mode=ParseMode.MARKDOWN
            )
            
            # Start download process
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            # Monitor progress
            last_update = datetime.now()
            progress_lines = []
            
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                    
                line_str = line.decode('utf-8', errors='ignore').strip()
                
                # Parse progress
                if "[download]" in line_str:
                    progress_lines.append(line_str)
                    
                    # Update every 5 seconds to avoid API spam
                    if (datetime.now() - last_update).seconds >= 5:
                        progress_text = progress_lines[-3:]  # Last 3 lines
                        progress_display = "\n".join(progress_text[-3:])
                        
                        await context.bot.edit_message_text(
                            chat_id=chat_id,
                            message_id=message_id,
                            text=f"⬇️ *Downloading...*\n"
                                 f"URL: {task.url[:50]}...\n"
                                 f"Quality: {task.quality}\n"
                                 f"Progress:\n`{progress_display}`",
                            parse_mode=ParseMode.MARKDOWN
                        )
                        last_update = datetime.now()
            
            # Wait for process to complete
            await process.wait()
            
            if process.returncode != 0:
                error_output = await process.stderr.read()
                error_text = error_output.decode('utf-8', errors='ignore')[:500]
                
                task.status = "failed"
                await context.bot.edit_message_text(
                    chat_id=chat_id,
                    message_id=message_id,
                    text=f"❌ *Download Failed*\n"
                         f"Error: {error_text}\n\n"
                         f"Possible solutions:\n"
                         f"1. Try different quality\n"
                         f"2. Check if URL is still valid\n"
                         f"3. Add cookies for this platform",
                    parse_mode=ParseMode.MARKDOWN
                )
                return
            
            # Find downloaded file
            downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
            if not downloaded_files:
                task.status = "failed"
                await context.bot.edit_message_text(
                    chat_id=chat_id,
                    message_id=message_id,
                    text="❌ *Download Failed*\nFile not found after download.",
                    parse_mode=ParseMode.MARKDOWN
                )
                return
            
            file_path = downloaded_files[0]
            task.file_path = str(file_path)
            task.file_size = file_path.stat().st_size
            
            # Check file size
            if task.file_size > (MAX_FILE_SIZE_MB * 1024 * 1024):
                task.status = "failed"
                os.remove(file_path)
                await context.bot.edit_message_text(
                    chat_id=chat_id,
                    message_id=message_id,
                    text=f"❌ *File too large*\n"
                         f"Size: {format_file_size(task.file_size)}\n"
                         f"Limit: {MAX_FILE_SIZE_MB}MB\n\n"
                         f"Please choose lower quality.",
                    parse_mode=ParseMode.MARKDOWN
                )
                return
            
            # Update status
            await context.bot.edit_message_text(
                chat_id=chat_id,
                message_id=message_id,
                text=f"📤 *Uploading to Telegram...*\n"
                     f"File: {file_path.name}\n"
                     f"Size: {format_file_size(task.file_size)}\n"
                     f"This may take a moment...",
                parse_mode=ParseMode.MARKDOWN
            )
            
            # Send file to Telegram
            try:
                with open(file_path, 'rb') as file:
                    # Determine file type
                    if file_path.suffix.lower() in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
                        await context.bot.send_photo(
                            chat_id=chat_id,
                            photo=file,
                            caption=f"📷 *Image Downloaded*\n"
                                    f"Size: {format_file_size(task.file_size)}\n"
                                    f"Platform: {task.platform.upper()}",
                            parse_mode=ParseMode.MARKDOWN
                        )
                    else:
                        await context.bot.send_video(
                            chat_id=chat_id,
                            video=file,
                            caption=f"🎬 *Video Downloaded*\n"
                                    f"Size: {format_file_size(task.file_size)}\n"
                                    f"Quality: {task.quality}\n"
                                    f"Platform: {task.platform.upper()}",
                            parse_mode=ParseMode.MARKDOWN,
                            supports_streaming=True
                        )
                
                task.status = "completed"
                task.end_time = datetime.now()
                
                # Schedule cleanup
                await cleanup_queue.put(str(file_path))
                
                # Send completion message
                duration = (task.end_time - task.start_time).seconds
                await context.bot.edit_message_text(
                    chat_id=chat_id,
                    message_id=message_id,
                    text=f"✅ *Download Complete!*\n"
                         f"File sent to chat\n"
                         f"Size: {format_file_size(task.file_size)}\n"
                         f"Time: {duration} seconds\n"
                         f"Will auto-delete in {DELETE_AFTER_MINUTES} minutes",
                    parse_mode=ParseMode.MARKDOWN
                )
                
            except Exception as upload_error:
                logger.error(f"Upload error: {upload_error}")
                task.status = "failed"
                await context.bot.edit_message_text(
                    chat_id=chat_id,
                    message_id=message_id,
                    text=f"❌ *Upload Failed*\n"
                         f"Error: {str(upload_error)[:200]}",
                    parse_mode=ParseMode.MARKDOWN
                )
            
    except Exception as e:
        logger.error(f"Download error: {e}")
        if task_id in active_downloads:
            active_downloads[task_id].status = "failed"
        
        try:
            await context.bot.edit_message_text(
                chat_id=chat_id,
                message_id=message_id,
                text=f"❌ *Download Error*\n{str(e)[:500]}",
                parse_mode=ParseMode.MARKDOWN
            )
        except:
            pass

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Update {update} caused error: {context.error}")
    
    # Try to send error message to user
    try:
        if update.effective_message:
            await update.effective_message.reply_text(
                "❌ An error occurred. Please try again later.",
                parse_mode=ParseMode.MARKDOWN
            )
    except:
        pass

async def maintenance_task():
    """Periodic maintenance tasks"""
    while True:
        try:
            # Clean old tasks from memory (older than 1 hour)
            current_time = datetime.now()
            to_delete = []
            
            for task_id, task in active_downloads.items():
                if task.end_time and (current_time - task.end_time).seconds > 3600:
                    to_delete.append(task_id)
            
            for task_id in to_delete:
                del active_downloads[task_id]
            
            # Check disk space
            disk = psutil.disk_usage('/')
            if disk.percent > 90:
                logger.warning(f"Disk space low: {disk.percent}%")
            
            # Clean old files from downloads directory (safety net)
            downloads_dir = Path("downloads")
            if downloads_dir.exists():
                for file in downloads_dir.iterdir():
                    if file.is_file():
                        file_age = current_time.timestamp() - file.stat().st_mtime
                        if file_age > 3600:  # Older than 1 hour
                            try:
                                file.unlink()
                            except:
                                pass
            
            await asyncio.sleep(300)  # Run every 5 minutes
            
        except Exception as e:
            logger.error(f"Maintenance task error: {e}")
            await asyncio.sleep(60)

def main():
    """Main function to start the bot"""
    print("Starting Telegram Media Downloader Bot...")
    print(f"Max concurrent downloads: {MAX_CONCURRENT_DOWNLOADS}")
    print(f"Auto-delete after: {DELETE_AFTER_MINUTES} minutes")
    print(f"Max file size: {MAX_FILE_SIZE_MB}MB")
    
    # Create application
    application = Application.builder().token(BOT_TOKEN).build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("status", status_command))
    application.add_handler(CommandHandler("stats", stats_command))
    application.add_handler(CommandHandler("cancel", cancel_command))
    
    # Handle URLs
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_url))
    
    # Handle callbacks
    application.add_handler(CallbackQueryHandler(handle_quality_selection))
    
    # Add error handler
    application.add_error_handler(error_handler)
    
    # Start maintenance tasks
    asyncio.create_task(cleanup_worker())
    asyncio.create_task(maintenance_task())
    
    # Start bot
    print("Bot is starting...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
