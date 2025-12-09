#!/usr/bin/env python3
"""
Telegram Facebook & TikTok Downloader Bot
Download Facebook and TikTok videos with captions
"""

import os
import json
import logging
import asyncio
import threading
import time
import re
from datetime import datetime, timedelta
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes
import yt_dlp
import requests

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class FacebookTikTokBot:
    def __init__(self):
        self.config = self.load_config()
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        # Bot state
        self.is_paused = False
        self.paused_until = None
        
        # Create directories
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # Start auto cleanup
        self.start_auto_cleanup()
        
        logger.info("🤖 Facebook & TikTok Bot initialized")
        print(f"✅ Token: {self.token[:15]}...")
    
    def load_config(self):
        """Load configuration"""
        config_file = 'config.json'
        if os.path.exists(config_file):
            with open(config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        
        # Default config
        config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'auto_cleanup_minutes': 2,
            'facebook_cookie': '',
            'tiktok_session': ''
        }
        
        with open(config_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        
        return config
    
    def start_auto_cleanup(self):
        """Start auto cleanup thread"""
        def cleanup_worker():
            while True:
                try:
                    self.cleanup_old_files()
                    time.sleep(60)
                except Exception as e:
                    logger.error(f"Cleanup error: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=cleanup_worker, daemon=True)
        thread.start()
        logger.info("🧹 Auto cleanup started")
    
    def cleanup_old_files(self):
        """Cleanup files older than 2 minutes"""
        cutoff_time = time.time() - (2 * 60)
        files_deleted = 0
        
        for file_path in self.download_dir.glob('*'):
            if file_path.is_file():
                file_age = time.time() - file_path.stat().st_mtime
                if file_age > (2 * 60):
                    try:
                        file_path.unlink()
                        files_deleted += 1
                    except Exception as e:
                        logger.error(f"Error deleting {file_path}: {e}")
        
        if files_deleted > 0:
            logger.info(f"Cleaned {files_deleted} old files")
    
    def detect_platform(self, url):
        """Detect platform from URL"""
        url_lower = url.lower()
        
        if 'facebook.com' in url_lower or 'fb.com' in url_lower or 'fb.watch' in url_lower:
            return 'facebook'
        elif 'tiktok.com' in url_lower:
            return 'tiktok'
        elif 'instagram.com' in url_lower:
            return 'instagram'
        else:
            return 'unknown'
    
    def format_size(self, bytes_size):
        """Format bytes to human readable size"""
        if bytes_size == 0:
            return "N/A"
        
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_size < 1024.0:
                return f"{bytes_size:.1f} {unit}"
            bytes_size /= 1024.0
        return f"{bytes_size:.1f} TB"
    
    def get_facebook_cookie_header(self):
        """Get Facebook cookie header if available"""
        cookie = self.config.get('facebook_cookie', '')
        if cookie:
            return {'Cookie': cookie}
        return {}
    
    def get_tiktok_session_header(self):
        """Get TikTok session header if available"""
        session = self.config.get('tiktok_session', '')
        if session:
            return {'Cookie': f'sessionid={session}'}
        return {}
    
    async def get_video_info(self, url, platform):
        """Get video information"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'skip_download': True,
            }
            
            # Add platform-specific headers
            if platform == 'facebook':
                headers = self.get_facebook_cookie_header()
                if headers:
                    ydl_opts['http_headers'] = headers
            elif platform == 'tiktok':
                headers = self.get_tiktok_session_header()
                if headers:
                    ydl_opts['http_headers'] = headers
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                return info
                
        except Exception as e:
            logger.error(f"Error getting video info: {e}")
            return None
    
    def extract_caption(self, info, platform):
        """Extract caption from video info"""
        try:
            caption = ""
            
            if platform == 'facebook':
                # Facebook caption
                if 'description' in info and info['description']:
                    caption = info['description']
                elif 'title' in info and info['title']:
                    caption = info['title']
                elif 'uploader' in info and info['uploader']:
                    caption = f"Posted by: {info['uploader']}"
            
            elif platform == 'tiktok':
                # TikTok caption
                if 'description' in info and info['description']:
                    caption = info['description']
                elif 'title' in info and info['title']:
                    caption = info['title']
                elif 'uploader' in info and info['uploader']:
                    caption = f"Creator: @{info['uploader']}"
            
            elif platform == 'instagram':
                # Instagram caption
                if 'description' in info and info['description']:
                    caption = info['description']
                elif 'title' in info and info['title']:
                    caption = info['title']
                elif 'uploader' in info and info['uploader']:
                    caption = f"Posted by: @{info['uploader']}"
            
            # Clean up the caption
            if caption:
                # Remove URLs
                caption = re.sub(r'http\S+', '', caption)
                # Remove extra whitespace
                caption = ' '.join(caption.split())
                # Truncate if too long
                if len(caption) > 1000:
                    caption = caption[:1000] + "..."
            
            return caption
            
        except Exception as e:
            logger.error(f"Error extracting caption: {e}")
            return ""
    
    def create_quality_keyboard(self, formats, platform):
        """Create keyboard for quality selection"""
        keyboard = []
        
        if formats:
            for fmt in formats:
                quality_label = fmt['quality']
                if len(quality_label) > 50:
                    quality_label = quality_label[:47] + "..."
                
                keyboard.append([
                    InlineKeyboardButton(
                        f"🎬 {quality_label}",
                        callback_data=f"download_{fmt['format_id']}"
                    )
                ])
        else:
            # Default options if no formats
            keyboard.append([
                InlineKeyboardButton("📹 Best Quality", callback_data="download_best")
            ])
            keyboard.append([
                InlineKeyboardButton("📹 720p HD", callback_data="download_720")
            ])
            keyboard.append([
                InlineKeyboardButton("📹 480p SD", callback_data="download_480")
            ])
        
        # Add audio option for platforms that support it
        if platform in ['facebook', 'tiktok']:
            keyboard.append([
                InlineKeyboardButton(
                    "🎵 Audio Only",
                    callback_data="download_audio"
                )
            ])
        
        # Add cancel button
        keyboard.append([
            InlineKeyboardButton("❌ Cancel", callback_data="cancel")
        ])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def get_video_formats(self, url, platform):
        """Get available formats with sizes"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'skip_download': True,
            }
            
            # Add platform-specific headers
            if platform == 'facebook':
                headers = self.get_facebook_cookie_header()
                if headers:
                    ydl_opts['http_headers'] = headers
            elif platform == 'tiktok':
                headers = self.get_tiktok_session_header()
                if headers:
                    ydl_opts['http_headers'] = headers
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                formats = []
                if 'formats' in info:
                    for fmt in info['formats']:
                        if not fmt.get('filesize'):
                            continue
                        
                        # Skip audio-only for video selection
                        if fmt.get('vcodec') == 'none' and fmt.get('acodec') != 'none':
                            continue
                        
                        resolution = fmt.get('resolution', 'N/A')
                        if resolution == 'audio only':
                            continue
                        
                        format_note = fmt.get('format_note', '')
                        if not format_note and resolution != 'N/A':
                            format_note = resolution
                        
                        # Calculate size
                        size_mb = fmt['filesize'] / (1024 * 1024)
                        max_size = self.config['telegram']['max_file_size']
                        
                        if size_mb > max_size:
                            continue
                        
                        formats.append({
                            'format_id': fmt['format_id'],
                            'resolution': resolution,
                            'format_note': format_note,
                            'ext': fmt.get('ext', 'mp4'),
                            'filesize_mb': round(size_mb, 1),
                            'quality': f"{format_note} ({resolution}) - {size_mb:.1f}MB"
                        })
                
                # Sort by quality (highest first)
                formats.sort(key=lambda x: (
                    -int(x['resolution'].split('x')[0]) if 'x' in x['resolution'] else 0,
                    -x['filesize_mb']
                ))
                
                return formats[:5]  # Return top 5 formats
                
        except Exception as e:
            logger.error(f"Error getting formats: {e}")
            return []
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        welcome = f"""
Hello {user.first_name}! 👋

🤖 **Facebook & TikTok Downloader Bot**

📥 **Supported Platforms:**
✅ Facebook (videos with captions)
✅ TikTok (videos with captions)
✅ Instagram (videos with captions)

🎯 **How it works:**
1. Send Facebook/TikTok/Instagram link
2. Bot downloads the video
3. Video sent to Telegram with caption
4. Temporary files auto deleted

⚡ **Features:**
• Downloads videos with original captions
• Quality selection available
• Shows file size before download
• Auto cleanup every 2 minutes
• Audio extraction option
• Pause/Resume functionality

🛠️ **Commands:**
/start - Show this menu
/help - Detailed help
/status - Bot status (admin)
/pause [hours] - Pause bot (admin)
/resume - Resume bot (admin)
/clean - Clean files (admin)
/settings - Configure cookies (admin)

💡 **Files auto deleted after 2 minutes**

🔧 **For better downloads:**
Add Facebook cookie or TikTok session in settings
"""
        
        await update.message.reply_text(welcome, parse_mode='Markdown')
        logger.info(f"User {user.id} started bot")
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
📖 **Facebook & TikTok Bot Help Guide**

🎯 **How to use:**
1. Send Facebook, TikTok, or Instagram link
2. Bot analyzes the video
3. Select quality if available
4. Bot downloads and sends video with caption

🔗 **Supported link formats:**
• Facebook: https://www.facebook.com/.../videos/...
• Facebook: https://fb.watch/...
• TikTok: https://www.tiktok.com/@.../video/...
• Instagram: https://www.instagram.com/p/...

📊 **Limits:**
• Max file size: 2GB (Telegram limit)
• Temporary files deleted after 2 minutes
• Some private videos may require cookies

⚡ **Tips:**
• For private Facebook videos, add cookie in settings
• For TikTok, add sessionid in settings
• Use quality selection for smaller file sizes
• Audio option available for audio-only downloads

🛠️ **Admin commands:**
/status - Bot and server status
/settings - Configure cookies and sessions
/clean - Clean temporary files
"""
        
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    async def settings_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /settings command"""
        user = update.effective_user
        if user.id not in self.admin_ids and len(self.admin_ids) > 0:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        settings_text = """
⚙️ **Bot Settings**

For better video downloads, you can configure:

**Facebook Cookie:**
1. Login to Facebook in browser
2. Open Developer Tools (F12)
3. Go to Network tab
4. Refresh page
5. Find any request to facebook.com
6. Copy the `Cookie` header value

**TikTok Session ID:**
1. Login to TikTok in browser
2. Open Developer Tools (F12)
3. Go to Application/Storage tab
4. Find Cookies for tiktok.com
5. Copy the `sessionid` value

**Current Settings:"""
        
        facebook_cookie = self.config.get('facebook_cookie', 'Not set')
        tiktok_session = self.config.get('tiktok_session', 'Not set')
        
        settings_text += f"\n\n📱 Facebook Cookie: {'✅ Set' if facebook_cookie and facebook_cookie != 'Not set' else '❌ Not set'}"
        settings_text += f"\n🎵 TikTok Session: {'✅ Set' if tiktok_session and tiktok_session != 'Not set' else '❌ Not set'}"
        
        keyboard = [
            [InlineKeyboardButton("📱 Set Facebook Cookie", callback_data="set_facebook_cookie")],
            [InlineKeyboardButton("🎵 Set TikTok Session", callback_data="set_tiktok_session")],
            [InlineKeyboardButton("❌ Clear Settings", callback_data="clear_settings")],
            [InlineKeyboardButton("🔙 Back", callback_data="settings_back")]
        ]
        
        await update.message.reply_text(
            settings_text,
            parse_mode='Markdown',
            reply_markup=InlineKeyboardMarkup(keyboard)
        )
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        text = update.message.text.strip()
        user = update.effective_user
        
        logger.info(f"Message from {user.first_name}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            platform = self.detect_platform(text)
            
            if platform in ['facebook', 'tiktok', 'instagram']:
                # Show quality selection
                await update.message.reply_text(f"🔍 Analyzing {platform.capitalize()} video...")
                formats = await self.get_video_formats(text, platform)
                
                if formats:
                    # Get video info for caption preview
                    info = await self.get_video_info(text, platform)
                    caption_preview = ""
                    
                    if info:
                        caption_preview = self.extract_caption(info, platform)
                        if caption_preview:
                            caption_preview = caption_preview[:100] + "..." if len(caption_preview) > 100 else caption_preview
                    
                    info_text = f"📹 **{platform.capitalize()} Video**\n\n"
                    
                    if caption_preview:
                        info_text += f"📝 **Caption:** {caption_preview}\n\n"
                    
                    info_text += "🎬 **Available Qualities:**\n"
                    
                    for i, fmt in enumerate(formats[:3], 1):
                        info_text += f"{i}. {fmt['quality']}\n"
                    
                    if len(formats) > 3:
                        info_text += f"... and {len(formats) - 3} more\n"
                    
                    await update.message.reply_text(info_text, parse_mode='Markdown')
                    
                    keyboard = self.create_quality_keyboard(formats, platform)
                    await update.message.reply_text(
                        "👇 Select quality:",
                        reply_markup=keyboard
                    )
                    
                    # Save for callback
                    context.user_data['last_url'] = text
                    context.user_data['last_platform'] = platform
                    if info:
                        context.user_data['video_info'] = info
                    
                else:
                    # Fallback if no formats
                    await update.message.reply_text("📥 Downloading with best quality...")
                    await self.download_video(update, text, platform, 'best')
            
            else:
                await update.message.reply_text(
                    "❌ Unsupported platform\n\n"
                    "✅ **Supported platforms:**\n"
                    "• Facebook (facebook.com, fb.com, fb.watch)\n"
                    "• TikTok (tiktok.com)\n"
                    "• Instagram (instagram.com)\n\n"
                    "📝 Please send a valid Facebook, TikTok, or Instagram link"
                )
        
        else:
            await update.message.reply_text(
                "Please send a valid URL starting with http:// or https://\n\n"
                "🌟 **Supported:**\n"
                "• Facebook videos with captions\n"
                "• TikTok videos with captions\n"
                "• Instagram videos with captions\n\n"
                "🔗 **Example:**\n"
                "https://www.facebook.com/.../videos/...\n"
                "https://www.tiktok.com/@.../video/..."
            )
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle callback queries"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ Download cancelled.")
            return
        
        # Settings callbacks
        elif data == 'set_facebook_cookie':
            await query.edit_message_text(
                "📱 **Setting Facebook Cookie**\n\n"
                "Please send the Facebook cookie value:\n\n"
                "1. Login to Facebook in browser\n"
                "2. Open Developer Tools (F12)\n"
                "3. Go to Network tab\n"
                "4. Refresh page\n"
                "5. Find any request to facebook.com\n"
                "6. Copy the `Cookie` header value\n\n"
                "Send the cookie value now:"
            )
            context.user_data['awaiting_facebook_cookie'] = True
            return
        
        elif data == 'set_tiktok_session':
            await query.edit_message_text(
                "🎵 **Setting TikTok Session**\n\n"
                "Please send the TikTok sessionid value:\n\n"
                "1. Login to TikTok in browser\n"
                "2. Open Developer Tools (F12)\n"
                "3. Go to Application/Storage tab\n"
                "4. Find Cookies for tiktok.com\n"
                "5. Copy the `sessionid` value\n\n"
                "Send the sessionid value now:"
            )
            context.user_data['awaiting_tiktok_session'] = True
            return
        
        elif data == 'clear_settings':
            self.config['facebook_cookie'] = ''
            self.config['tiktok_session'] = ''
            self.save_config()
            await query.edit_message_text("✅ Settings cleared!")
            return
        
        elif data == 'settings_back':
            await query.delete_message()
            await self.settings_command(update, context)
            return
        
        # Download callbacks
        elif data.startswith('download_'):
            format_spec = data.replace('download_', '')
            
            url = context.user_data.get('last_url')
            platform = context.user_data.get('last_platform')
            
            if not url or not platform:
                await query.edit_message_text("❌ URL not found!")
                return
            
            # Map quality names to yt-dlp format specs
            format_map = {
                'best': 'best',
                '720': 'best[height<=720]',
                '480': 'best[height<=480]',
                'audio': 'bestaudio'
            }
            
            actual_format = format_map.get(format_spec, format_spec)
            
            await query.edit_message_text(f"⏳ Downloading...")
            await self.download_video(update, url, platform, actual_format, query=query)
    
    async def download_video(self, update: Update, url: str, platform: str, format_spec: str, query=None):
        """Download video with specific format"""
        try:
            # Determine if this is from callback or message
            from_callback = query is not None
            message = query.message if from_callback else update.message
            
            if not message:
                error_msg = "❌ Message not found!"
                if query:
                    await query.edit_message_text(error_msg)
                else:
                    await update.message.reply_text(error_msg)
                return
            
            # Update status message
            status_msg = f"⏳ Downloading {platform.capitalize()} video..."
            if from_callback:
                await query.edit_message_text(status_msg)
            else:
                status_message = await update.message.reply_text(status_msg)
            
            # Get video info first for caption
            info = await self.get_video_info(url, platform)
            if not info:
                error_msg = "❌ Could not get video information"
                if from_callback:
                    await query.edit_message_text(error_msg)
                else:
                    await update.message.reply_text(error_msg)
                return
            
            # Extract caption
            caption = self.extract_caption(info, platform)
            
            # Prepare yt-dlp options
            ydl_opts = {
                'format': format_spec,
                'quiet': True,
                'outtmpl': str(self.download_dir / f'%(id)s.%(ext)s'),
                'no_warnings': True,
                'postprocessors': [],
            }
            
            # Add platform-specific headers
            if platform == 'facebook':
                headers = self.get_facebook_cookie_header()
                if headers:
                    ydl_opts['http_headers'] = headers
            elif platform == 'tiktok':
                headers = self.get_tiktok_session_header()
                if headers:
                    ydl_opts['http_headers'] = headers
            
            # Add audio postprocessor for audio downloads
            if format_spec == 'bestaudio':
                ydl_opts['postprocessors'] = [{
                    'key': 'FFmpegExtractAudio',
                    'preferredcodec': 'mp3',
                    'preferredquality': '192',
                }]
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                # Now download
                ydl.download([url])
                
                # Find the downloaded file
                filename = ydl.prepare_filename(info)
                
                # For audio downloads, change extension to mp3
                if format_spec == 'bestaudio':
                    filename = filename.rsplit('.', 1)[0] + '.mp3'
                
                if not os.path.exists(filename):
                    # Try to find with different extension
                    for ext in ['.mp4', '.webm', '.mkv', '.m4a', '.mp3']:
                        alt_name = filename.rsplit('.', 1)[0] + ext
                        if os.path.exists(alt_name):
                            filename = alt_name
                            break
                
                if os.path.exists(filename):
                    file_size = os.path.getsize(filename) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(filename)
                        error_msg = f"❌ File too large: {file_size:.1f}MB"
                        if from_callback:
                            await query.edit_message_text(error_msg)
                        else:
                            await status_message.edit_text(error_msg)
                        return
                    
                    # Upload status
                    upload_msg = f"📤 Uploading ({file_size:.1f}MB)..."
                    if from_callback:
                        await query.edit_message_text(upload_msg)
                    else:
                        await status_message.edit_text(upload_msg)
                    
                    # Prepare final caption
                    final_caption = f"📹 {platform.capitalize()} Video\n\n"
                    
                    # Add video title if available
                    title = info.get('title', '')
                    if title:
                        final_caption += f"**{title}**\n\n"
                    
                    # Add caption if available
                    if caption:
                        final_caption += f"{caption}\n\n"
                    
                    # Add uploader info
                    uploader = info.get('uploader', '')
                    if uploader:
                        final_caption += f"👤 {uploader}\n"
                    
                    # Add duration if available
                    duration = info.get('duration', 0)
                    if duration:
                        minutes = duration // 60
                        seconds = duration % 60
                        final_caption += f"⏱️ {minutes}:{seconds:02d}\n"
                    
                    final_caption += f"📦 Size: {file_size:.1f}MB\n\n"
                    final_caption += f"✅ Downloaded via Telegram Bot"
                    
                    # Send file
                    with open(filename, 'rb') as f:
                        if filename.endswith(('.mp3', '.m4a', '.opus')):
                            await message.reply_audio(
                                audio=f,
                                caption=final_caption[:1024],
                                title=info.get('title', 'Audio')[:50]
                            )
                        else:
                            await message.reply_video(
                                video=f,
                                caption=final_caption[:1024],
                                supports_streaming=True
                            )
                    
                    success_msg = f"✅ {platform.capitalize()} download complete! ({file_size:.1f}MB)"
                    if from_callback:
                        await query.edit_message_text(success_msg)
                    else:
                        await status_message.edit_text(success_msg)
                    
                    # Schedule deletion
                    self.schedule_file_deletion(filename)
                    
                else:
                    error_msg = "❌ File not found after download"
                    if from_callback:
                        await query.edit_message_text(error_msg)
                    else:
                        await update.message.reply_text(error_msg)
                        
        except Exception as e:
            logger.error(f"Download error: {e}")
            error_msg = f"❌ Error: {str(e)[:100]}"
            if query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
    
    def schedule_file_deletion(self, filepath):
        """Schedule file deletion after 2 minutes"""
        def delete_later():
            time.sleep(120)
            if os.path.exists(filepath):
                try:
                    os.remove(filepath)
                    logger.info(f"Auto deleted: {os.path.basename(filepath)}")
                except:
                    pass
        
        threading.Thread(target=delete_later, daemon=True).start()
    
    def save_config(self):
        """Save configuration to file"""
        try:
            with open('config.json', 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4, ensure_ascii=False)
            logger.info("Configuration saved")
        except Exception as e:
            logger.error(f"Error saving config: {e}")
    
    async def handle_settings_input(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle settings input from users"""
        text = update.message.text.strip()
        
        if context.user_data.get('awaiting_facebook_cookie'):
            self.config['facebook_cookie'] = text
            self.save_config()
            await update.message.reply_text("✅ Facebook cookie saved!")
            context.user_data.pop('awaiting_facebook_cookie', None)
            
        elif context.user_data.get('awaiting_tiktok_session'):
            self.config['tiktok_session'] = text
            self.save_config()
            await update.message.reply_text("✅ TikTok session saved!")
            context.user_data.pop('awaiting_tiktok_session', None)
        
        else:
            # Normal message handling
            await self.handle_message(update, context)
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user = update.effective_user
        if user.id not in self.admin_ids and len(self.admin_ids) > 0:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        facebook_cookie = self.config.get('facebook_cookie', '')
        tiktok_session = self.config.get('tiktok_session', '')
        
        status_text = f"""
📊 **Bot Status**

✅ Bot active
📁 Temp files: {len(files)}
💾 Temp size: {total_size:.1f}MB
👤 Your ID: {user.id}

⚙️ **Settings:**
Max file size: {self.config['telegram']['max_file_size']}MB
Auto cleanup: Every 2 minutes
Facebook cookie: {'✅ Set' if facebook_cookie else '❌ Not set'}
TikTok session: {'✅ Set' if tiktok_session else '❌ Not set'}
"""
        
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /pause command"""
        user = update.effective_user
        if user.id not in self.admin_ids and len(self.admin_ids) > 0:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        hours = 1
        if context.args:
            try:
                hours = int(context.args[0])
            except:
                hours = 1
        
        self.is_paused = True
        self.paused_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸️ Bot paused for {hours} hour(s)\n"
            f"Resume at: {self.paused_until.strftime('%H:%M')}"
        )
    
    async def resume_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /resume command"""
        user = update.effective_user
        if user.id not in self.admin_ids and len(self.admin_ids) > 0:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        self.is_paused = False
        self.paused_until = None
        await update.message.reply_text("▶️ Bot resumed!")
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /clean command"""
        user = update.effective_user
        if user.id not in self.admin_ids and len(self.admin_ids) > 0:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        count = len(files)
        
        for f in files:
            try:
                f.unlink()
            except:
                pass
        
        await update.message.reply_text(f"🧹 Cleaned {count} files")
    
    def run(self):
        """Run the bot"""
        print("=" * 50)
        print("🤖 Facebook & TikTok Downloader Bot")
        print("📥 Download videos with captions")
        print("=" * 50)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Configure token in config.json")
            return
        
        print(f"✅ Token: {self.token[:15]}...")
        print(f"✅ Max file size: {self.config['telegram']['max_file_size']}MB")
        print("✅ Bot ready!")
        print("📱 Send Facebook/TikTok/Instagram link to download")
        print("=" * 50)
        
        app = Application.builder().token(self.token).build()
        
        app.add_handler(CommandHandler("start", self.start_command))
        app.add_handler(CommandHandler("help", self.help_command))
        app.add_handler(CommandHandler("status", self.status_command))
        app.add_handler(CommandHandler("pause", self.pause_command))
        app.add_handler(CommandHandler("resume", self.resume_command))
        app.add_handler(CommandHandler("clean", self.clean_command))
        app.add_handler(CommandHandler("settings", self.settings_command))
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_settings_input))
        app.add_handler(CallbackQueryHandler(self.handle_callback))
        
        app.run_polling()

def main():
    try:
        bot = FacebookTikTokBot()
        bot.run()
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped")
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
