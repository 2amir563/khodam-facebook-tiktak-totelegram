#!/usr/bin/env python3
"""
Telegram Media Downloader Bot - UNIVERSAL VERSION (v10 - Optimized for Format and Access Errors)
Fixes common installation errors and improves download stability, especially for Pinterest/Reddit/BiliBili.
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
    """Download video using yt-dlp with advanced options and format fallback"""
    
    # Preferred format (720p or best)
    preferred_format = "best[height<=720]/best" 
    
    # Fallback format for difficult sites (e.g., Pinterest/Reddit format errors)
    fallback_format = "bestvideo+bestaudio/best" 
    
    # List of formats to try
    formats_to_try = [preferred_format, fallback_format]
    
    final_success = False
    final_result = "Unknown error before attempt."
    
    for fmt in formats_to_try:
        logger.info(f"Attempting download for {url} with format: {fmt}")
        
        cmd = [
            "yt-dlp",
            "-f", fmt, 
            "-o", output_path,
            "--no-warnings",
            "--ignore-errors",
            "--no-playlist",
            "--concurrent-fragments", "4", # Increased concurrency
            "--limit-rate", "10M",        # Increased rate limit to 10M
            # --- Advanced Options for stability and bypassing blocks ---
            "--retries", "10",            # Increased retries for flaky connections/BiliBili 412
            "--fragment-retries", "10",
            "--buffer-size", "256K",      # Increased buffer size
            "--user-agent", USER_AGENT, 
            "--geo-bypass-country", "US,DE,GB", # Geo-bypass through multiple countries
            "--geo-bypass-resume", 
            "--no-check-certificate", 
            # -----------------------------------------------------------
            url
        ]
        
        # Add cookies if available
        cookies_file = "cookies/cookies.txt"
        if os.path.exists(cookies_file):
            cmd.extend(["--cookies", cookies_file])
        
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # Increased timeout to 8 minutes (480 seconds)
            try:
                stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=480) 
            except asyncio.TimeoutError:
                process.kill()
                logger.error(f"Download Timeout: {url}")
                final_result = "Timeout (8 minutes) - Server might be too slow or file too large."
                continue # Try next format if applicable
            
            if process.returncode == 0:
                final_success = True
                final_result = "Success"
                break # Exit loop on success
            else:
                error_output = stderr.decode('utf-8', errors='ignore')
                
                # --- Better Error Parsing ---
                error_summary = "Unknown Download Error"
                
                # Handle 403 / 412 / Blocked errors (BiliBili fix)
                if "HTTP Error 403" in error_output or "Forbidden" in error_output or "Blocked" in error_output or "HTTP Error 412" in error_output:
                    error_summary = "Access Denied (403/412/Blocked). Try adding cookies.txt or check URL."
                # Handle 404
                elif "HTTP Error 404" in error_output or "NOT FOUND" in error_output:
                    error_summary = "File Not Found (404). Check URL validity."
                # Handle Vimeo/Login
                elif "logged-in" in error_output or "--cookies" in error_output:
                    error_summary = "Login Required. Provide cookies.txt or use public link."
                # Handle Requested Format Error (If this occurs on the preferred format, we'll try the fallback)
                elif "Requested format is not available" in error_output and fmt == preferred_format:
                    logger.warning(f"Format not found ({preferred_format}). Trying fallback...")
                    continue # Continue to the next format (fallback_format)
                # General error
                else:
                    lines = [line.strip() for line in error_output.split('\n') if line.strip()]
                    error_summary = lines[-1][:200] if lines else "Unknown Download Error"
                
                final_result = f"Download error: {error_summary}"
                
        except Exception as e:
            logger.error(f"Exception during download: {e}")
            final_result = f"Internal Error: {str(e)}"
        
        # If we reached here without success, and format was fallback, then break
        if fmt == fallback_format:
             break
        
    return final_success, final_result

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome = f"""
🤖 *UNIVERSAL Media Downloader Bot - V10*

✅ *Supported Sites:*
• YouTube, TikTok, Instagram
• Facebook, Twitter/X, Reddit
• Pinterest, Vimeo, Dailymotion and many more!

📝 *How to Use:*
1. Send any media URL.
2. The bot will download and send the file.

⚡ *Features (V10 Update):*
✅ Improved format detection (Fixes Pinterest/Reddit format error)
✅ Enhanced access handling (Better fix for BiliBili 412/403)
✅ Automatic file deletion after {DELETE_AFTER} minutes
✅ Max file size: {MAX_SIZE_MB}MB

🍪 *Cookie Setup (Important for Vimeo/403/412):*
For sites with access restrictions (like Vimeo, Pinterest/Reddit often causing 403 errors), please place your `cookies.txt` file here:
`/opt/telegram-media-bot/cookies/`
"""
    await update.message.reply_text(welcome, parse_mode=ParseMode.MARKDOWN)

async def handle_url(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle URL messages"""
    original_text = update.message.text
    url = clean_url(original_text)
    
    if not url:
        await update.message.reply_text(
            "❌ *Invalid URL*\nPlease send a valid URL starting with http:// or https://",
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
        f"🔗 *Processing URL*\n\n"
        f"Site: *{site.upper()}*\n"
        f"URL: `{url[:50]}...`\n\n"
        f"Starting download...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name = site 
    filename = f"{safe_name}_{timestamp}"
    output_template = f"downloads/{filename}.%(ext)s"
    
    # Download
    await msg.edit_text(
        f"📥 *Downloading...*\n\n"
        f"Site: {site.upper()}\n"
        f"Please wait (Max 8 minutes)...",
        parse_mode=ParseMode.MARKDOWN
    )
    
    success, result = await download_video(url, output_template)
    
    # If download fails, report error with more details
    if not success:
        # Check if the error is due to a login requirement (Vimeo, Private content)
        if "Login Required" in result:
             error_message = (
                f"❌ *Download Failed (Login Required)*\n\n"
                f"Error: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *Solution:* This link is private or requires login (e.g., Vimeo).\n"
                f"Please place your `cookies.txt` file in `/opt/telegram-media-bot/cookies/`."
            )
        # Check if the error is due to Access Denied/412 (BiliBili, Geo-block)
        elif "Access Denied" in result:
            error_message = (
                f"❌ *Download Failed (Access Blocked)*\n\n"
                f"Error: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *Solution:* Server (or Geo-block) rejected access (403/412).\n"
                f"If the link is public, try again. If it is restricted, you need `cookies.txt`."
            )
        # Check if the error is 404 (File Not Found)
        elif "File Not Found" in result:
            error_message = (
                f"❌ *Download Failed (404)*\n\n"
                f"Error: `{result.replace('Download error: ', '')}`\n\n"
                f"💡 *Solution:* The provided URL does not point to an existing file/page."
            )
        # Other errors
        else:
             error_message = (
                f"❌ *Download Failed*\n\n"
                f"Error: `{result}`\n\n"
                f"Possible reasons:\n"
                f"• URL is inaccessible or broken.\n"
                f"• Cookies file (`cookies.txt`) is required.\n"
                f"• Content is restricted (Geo/Private)."
            )

        await msg.edit_text(error_message, parse_mode=ParseMode.MARKDOWN)
        return
    
    # Find downloaded file
    downloaded_files = list(Path("downloads").glob(f"{filename}.*"))
    downloaded_files.sort(key=lambda p: p.stat().st_size, reverse=True)
    
    if not downloaded_files:
        await msg.edit_text(
            "❌ Download completed but the final file was not found.",
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
            f"❌ *File Too Large*\n\n"
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
            caption_text = (
                f"✅ *Download Complete!*\n\n"
                f"Site: {site.upper()}\n"
                f"Size: {format_size(file_size)}\n"
                f"Auto-deletes in {DELETE_AFTER} minutes"
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
            f"🎉 *SUCCESS!*\n\n"
            f"✅ File downloaded and sent!\n"
            f"📊 Size: {format_size(file_size)}\n"
            f"⏰ Auto-deletes in {DELETE_AFTER} minutes\n\n"
            f"Ready for next URL!",
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
            f"❌ *Upload Failed*\n\n"
            f"Error: {str(upload_error)[:200]}",
            parse_mode=ParseMode.MARKDOWN
        )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = f"""
🆘 *HELP GUIDE (V10)*

📋 *How to Use:*
1. Send any media URL.
2. The bot automatically handles the download.
3. Receive the file in Telegram.
4. Files are auto-deleted after {DELETE_AFTER} minutes.

🌐 *Supported Sites:*
- Almost all sites supported by yt-dlp.

⚙️ *Cookie Setup (CRITICAL for Access):*
To bypass login/access errors (like 403, 412, or Vimeo login), you need a `cookies.txt` file.
Place it in: `/opt/telegram-media-bot/cookies/`

📏 *Limits:*
- Max file size: {MAX_SIZE_MB}MB
- Auto-delete: {DELETE_AFTER} minutes
"""
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /status command"""
    
    cpu = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    status_text = f"""
📊 *BOT STATUS (V10)*

🖥 *System:*
• CPU: {cpu:.1f}%
• RAM: {memory.percent:.1f}% ({format_size(memory.available)} Free)
• Disk: {disk.percent:.1f}% ({format_size(disk.free)} Free)

🤖 *Bot:*
• Version: V10 (Format/Access Optimized)
• Max size: {MAX_SIZE_MB}MB
• Auto-delete: {DELETE_AFTER} min
• Status: ✅ Running

💡 *Quick Commands:*
/start - Welcome message
/help - Guide
/status - Bot status
"""
    await update.message.reply_text(status_text, parse_mode=ParseMode.MARKDOWN)

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Unhandled error: {context.error}")
    if update and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "❌ An internal error occurred. Please try again.",
                parse_mode=ParseMode.MARKDOWN
            )
        except Exception as e:
            logger.error(f"Failed to send error message: {e}")

def main():
    """Main function"""
    print("=" * 60)
    print("🤖 Telegram Media Downloader Bot - V10 (Format/Access Optimized)")
    print("=" * 60)
    print(f"Token: {BOT_TOKEN[:20]}...")
    print(f"Max size: {MAX_SIZE_MB}MB")
    print(f"Auto-delete: {DELETE_AFTER} minutes")
    print("=" * 60)
    
    app = Application.builder().token(BOT_TOKEN).build()
    
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
    if not os.access(__file__, os.X_OK):
        try:
            os.chmod(__file__, 0o755) 
        except Exception as e:
            pass
    main()
