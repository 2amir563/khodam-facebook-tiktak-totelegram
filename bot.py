#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - UNIVERSAL VERSION
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
    
    # Find URL pattern
    url_pattern = r'(https?://[^\s<>"\']+|www\.[^\s<>"\']+\.[a-z]{2,})'
    matches = re.findall(url_pattern, text, re.IGNORECASE)
    
    if matches:
        url = matches[0]
        if not url.startswith(('http://', 'https://')):
            if url.startswith('www.'):
                url = 'https://' + url
            else:
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
    """Download video using yt-dlp"""
    try:
        cmd = [
            "yt-dlp",
            "-f", "best[height<=720]/best",
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            "--concurrent-fragments", "2",
            "--limit-rate", "5M",
            url
        ]
        
        # Add cookies if available
        cookies_file = "cookies/cookies.txt"
        if os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
        
        logger.info(f"Running: {' '.join(cmd[:10])}...")
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        except asyncio.TimeoutError:
            process.kill()
            return False, "Timeout (5 minutes)"
        
        if process.returncode == 0:
            return True, "Success"
        else:
            error = stderr.decode('utf-8', errors='ignore')[:200]
            return False, f"Download error: {error}"
            
    except Exception as e:
        return False, f"Error: {str(e)}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = """
🤖 *UNIVERSAL Media Downloader Bot*

✅ *SUPPORTED SITES:*
• YouTube, TikTok, Instagram
• Facebook, Twitter/X, Reddit
• Pinterest, Twitch, Vimeo
• Dailymotion, Streamable, Rumble
• Bilibili, TED, and many more!

📝 *HOW TO USE:*
1. Copy ANY media URL
2. Paste in chat
3. Bot will download and send file

⚡ *FEATURES:*
✅ Automatic download
✅ File size display
✅ Auto-cleanup after 2 minutes
✅ Works with most sites

🍪 *COOKIES:*
Some sites need cookies for better results.
Place cookies.txt in /opt/telegram-media-bot/cookies/
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    original_text = update.message.text
    url = clean_url(original_text)
    
    if not url:
        await update.message.reply_text(
            "❌ *No valid URL found*\nPlease send a URL starting with http:// or https://",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Detect site
    parsed = urlparse(url)
    site = parsed.netloc.replace('www.', '').split('.')[0]
    
    # Initial message
    msg = await update.message.reply_text(
        f"🔗 *Processing URL*\n\n"
        f"Site: *{site.upper()}*\n"
        f"URL: `{url[:50]}...`\n\n"
        f"Starting download...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name = re.sub(r'[^\w\-_]', '_', url[:30])
    filename = f"{safe_name}_{timestamp}"
    output_template = f"downloads/{filename}.%(ext)s"
    
    # Download
    await msg.edit_text(
        f"📥 *Downloading...*\n\n"
        f"Site: {site.upper()}\n"
        f"Please wait...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    success, result = await download_video(url, output_template)
    
    if not success:
        await msg.edit_text(
            f"❌ *Download Failed*\n\n"
            f"Error: {result}\n\n"
            f"Possible reasons:\n"
            f"• URL not accessible\n"
            f"• Need cookies for this site\n"
            f"• Content restricted",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Find downloaded file
    downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
    if not downloaded_files:
        await msg.edit_text(
            "❌ Download completed but file not found",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    file_path = downloaded_files[0]
    file_size = file_path.stat().st_size
    
    # Check size
    if file_size > (MAX_SIZE_MB * 1024 * 1024):
        file_path.unlink()
        await msg.edit_text(
            f"❌ *File too large*\n\n"
            f"Size: {format_size(file_size)}\n"
            f"Limit: {MAX_SIZE_MB}MB",
            parse_mode=ParseMode.MARKDOWN
        )
        return
    
    # Upload to Telegram
    await msg.edit_text(
        f"📤 *Uploading...*\n\n"
        f"File: {file_path.name}\n"
        f"Size: {format_size(file_size)}\n\n"
        f"This may take a moment...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    try:
        with open(file_path, 'rb') as file:
            file_ext = file_path.suffix.lower()
            
            if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']:
                await update.message.reply_photo(
                    photo=file,
                    caption=f"✅ *Download Complete!*\n\n"
                           f"Site: {site.upper()}\n"
                           f"Size: {format_size(file_size)}\n"
                           f"Auto-deletes in {DELETE_AFTER} minutes",
                    parse_mode=ParseMode.MARKDOWN
                )
            elif file_ext in ['.mp3', '.m4a', '.wav', '.ogg', '.flac']:
                await update.message.reply_audio(
                    audio=file,
                    caption=f"✅ *Download Complete!*\n\n"
                           f"Site: {site.upper()}\n"
                           f"Size: {format_size(file_size)}\n"
                           f"Auto-deletes in {DELETE_AFTER} minutes",
                    parse_mode=ParseMode.MARKDOWN
                )
            else:
                await update.message.reply_video(
                    video=file,
                    caption=f"✅ *Download Complete!*\n\n"
                           f"Site: {site.upper()}\n"
                           f"Size: {format_size(file_size)}\n"
                           f"Auto-deletes in {DELETE_AFTER} minutes",
                    parse_mode=ParseMode.MARKDOWN,
                    supports_streaming=True
                )
        
        # Success
        await msg.edit_text(
            f"🎉 *SUCCESS!*\n\n"
            f"✅ File downloaded and sent!\n"
            f"📊 Size: {format_size(file_size)}\n"
            f"⏰ Auto-deletes in {DELETE_AFTER} minutes\n\n"
            f"Ready for next URL!",
            parse_mode=ParseMode.MARKDOWN
        )
        
        # Auto delete after delay
        async def delete_file():
            await asyncio.sleep(DELETE_AFTER * 60)
            if file_path.exists():
                file_path.unlink()
                logger.info(f"Auto-deleted: {file_path.name}")
        
        asyncio.create_task(delete_file())
        
    except Exception as upload_error:
        logger.error(f"Upload error: {upload_error}")
        await msg.edit_text(
            f"❌ *Upload Failed*\n\n"
            f"Error: {str(upload_error)[:200]}",
            parse_mode=ParseMode.MARKDOWN
        )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
🆘 *HELP GUIDE*

📋 *How to use:*
1. Send any media URL
2. Bot downloads automatically
3. Receive file in Telegram
4. Files auto-delete after 2 minutes

🌐 *Supported sites:*
- YouTube, TikTok, Instagram
- Facebook, Twitter, Reddit
- Pinterest, Twitch, Vimeo
- Dailymotion, Streamable
- Rumble, Bilibili, TED

⚙️ *Cookies setup:*
Some sites need cookies.txt file
Place in: /opt/telegram-media-bot/cookies/

📏 *Limits:*
- Max file size: 2000MB
- Auto-delete: 2 minutes
- One download at a time

🔧 *Troubleshooting:*
Check logs: tail -f /opt/telegram-media-bot/logs/bot.log
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    import psutil
    
    cpu = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    
    status_text = f"""
📊 *BOT STATUS*

🖥 *System:*
• CPU: {cpu:.1f}%
• Memory: {memory.percent:.1f}%
• Free RAM: {format_size(memory.available)}

🤖 *Bot:*
• Version: 7.0
• Max size: {MAX_SIZE_MB}MB
• Auto-delete: {DELETE_AFTER} min
• Status: ✅ Running

📁 *Directories:*
• Downloads: /opt/telegram-media-bot/downloads/
• Logs: /opt/telegram-media-bot/logs/
• Cookies: /opt/telegram-media-bot/cookies/

💡 *Quick commands:*
/start - Welcome message
/help - This guide
/status - Bot status
"""
    await update.message.reply_text(status_text, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Error: {context.error}")
    try:
        await update.effective_message.reply_text(
            "❌ An error occurred. Please try again.",
            parse_mode=ParseMode.MARKDOWN
        )
    except:
        pass

def main():
    """Main function"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot")
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
    main()
