#!/bin/bash

# =========================================================
#         Simple Telegram Downloader Bot Setup
# =========================================================
# Simple bot for downloading videos from social media

set -e

BOT_FILE="bot.py"
ENV_FILE=".env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🛠️ Simple Telegram Downloader Bot Setup${NC}"

# 1. Install basic dependencies
echo -e "${YELLOW}📦 Installing system dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip python3-venv curl ffmpeg

# 2. Install yt-dlp
echo -e "${YELLOW}⬇️ Installing yt-dlp...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp
echo -e "${GREEN}✅ yt-dlp installed${NC}"

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

# 6. Create bot.py with caption support
echo -e "${YELLOW}📝 Creating bot.py...${NC}"

cat << 'EOF' > $BOT_FILE
#!/usr/bin/env python3
"""
Simple Telegram Downloader Bot with Caption
"""
import os
import sys
import logging
import subprocess
import asyncio
import json
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

# Supported platforms
SUPPORTED_DOMAINS = [
    "tiktok.com",
    "facebook.com",
    "fb.watch",
    "youtube.com",
    "youtu.be",
    "instagram.com",
    "twitter.com",
    "x.com",
    "reddit.com"
]

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send welcome message"""
    message = (
        "👋 *Simple Downloader Bot*\n\n"
        "📥 *Supported:*\n"
        "• TikTok\n• Facebook\n• YouTube\n"
        "• Instagram\n• Twitter/X\n• Reddit\n\n"
        "📝 *Send me a link!*\n\n"
        "⚠️ *Note:*\n"
        "• Max 50MB\n• Public videos only\n"
        "• Facebook: Use direct links\n"
        "   ✅ https://www.facebook.com/watch/?v=123\n"
        "   ✅ https://fb.watch/abc123/\n"
        "   ✅ https://www.facebook.com/reel/123\n"
    )
    await update.message.reply_text(message, parse_mode='Markdown')

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send help message"""
    help_text = (
        "❓ *Help*\n\n"
        "1. Copy video link\n"
        "2. Send to bot\n"
        "3. Get downloaded file with video info\n\n"
        "*For Facebook:*\n"
        "✅ Working:\n"
        "• https://www.facebook.com/watch/?v=123\n"
        "• https://fb.watch/abc123/\n"
        "• https://www.facebook.com/reel/123\n\n"
        "❌ Not working:\n"
        "• https://www.facebook.com/share/r/...\n"
        "• Login pages\n\n"
        "*Limits:*\n"
        "• Max 50MB\n• Public videos only"
    )
    await update.message.reply_text(help_text, parse_mode='Markdown')

def is_supported(url):
    """Check if URL is supported"""
    url_lower = url.lower()
    for domain in SUPPORTED_DOMAINS:
        if domain in url_lower:
            return True
    return False

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
            info = json.loads(stdout.decode('utf-8'))
            
            # Extract relevant information
            title = info.get('title', 'Unknown Title')
            duration = info.get('duration', 0)
            uploader = info.get('uploader', 'Unknown Uploader')
            view_count = info.get('view_count', 0)
            like_count = info.get('like_count', 0)
            
            # Format duration
            if duration:
                minutes = duration // 60
                seconds = duration % 60
                duration_str = f"{minutes}:{seconds:02d}"
            else:
                duration_str = "Unknown"
            
            # Create caption
            caption = (
                f"📹 *{title}*\n\n"
                f"👤 Uploader: {uploader}\n"
                f"⏱ Duration: {duration_str}\n"
                f"👁 Views: {view_count:,}\n"
                f"👍 Likes: {like_count:,}\n\n"
                f"🔗 Original URL: {url}"
            )
            
            return caption, info
        else:
            return None, None
            
    except Exception as e:
        logger.error(f"Error getting video info: {e}")
        return None, None

async def download_video(url, output_dir, platform=None):
    """Download video using yt-dlp with fallback formats"""
    unique_id = uuid4().hex[:8]
    output_template = f"{output_dir}/{unique_id}.%(ext)s"
    
    # Platform-specific format selection
    if platform == "facebook":
        # Facebook format chain with fallbacks
        format_chain = [
            "best[height<=720][filesize<=50M]",      # Try 720p first
            "best[height<=480][filesize<=50M]",      # Then 480p
            "best[filesize<=50M]",                   # Then any under 50MB
            "worst[filesize<=50M]"                   # Finally worst quality
        ]
        format_str = "/".join(format_chain)
    else:
        # Other platforms - simple format
        format_str = "best[filesize<=50M]/worst"
    
    # Build command
    cmd = [
        "yt-dlp",
        "--no-warnings",
        "--format", format_str,
        "--max-filesize", "50M",
        "--restrict-filenames",
        "-o", output_template,
        url
    ]
    
    try:
        logger.info(f"Downloading with command: {' '.join(cmd[:6])}...")
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='ignore').strip()
            logger.error(f"Download error: {error}")
            
            # Check if it's a format error
            if "format is not available" in error or "Requested format" in error:
                logger.info("Format error detected, trying simple format...")
                
                # Try with simple format as fallback
                simple_cmd = [
                    "yt-dlp",
                    "--no-warnings",
                    "--format", "best",
                    "--max-filesize", "50M",
                    "--restrict-filenames",
                    "-o", output_template,
                    url
                ]
                
                process2 = await asyncio.create_subprocess_exec(
                    *simple_cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                
                stdout2, stderr2 = await asyncio.wait_for(process2.communicate(), timeout=300)
                
                if process2.returncode != 0:
                    error2 = stderr2.decode('utf-8', errors='ignore').strip()
                    if error2:
                        lines = error2.split('\n')
                        for line in reversed(lines):
                            if line.strip():
                                return None, line.strip()
                    return None, "Download failed with fallback too"
        
        # Find downloaded file
        for file in Path(output_dir).glob(f"{unique_id}.*"):
            if file.is_file() and file.stat().st_size > 0:
                return file, None
        
        return None, "File not found after download"
        
    except asyncio.TimeoutError:
        return None, "Download timeout"
    except Exception as e:
        logger.error(f"Exception in download: {e}")
        return None, str(e)

def detect_platform(url):
    """Detect platform from URL"""
    url_lower = url.lower()
    if "facebook.com" in url_lower or "fb.watch" in url_lower:
        return "facebook"
    elif "tiktok.com" in url_lower:
        return "tiktok"
    elif "youtube.com" in url_lower or "youtu.be" in url_lower:
        return "youtube"
    elif "instagram.com" in url_lower:
        return "instagram"
    elif "twitter.com" in url_lower or "x.com" in url_lower:
        return "twitter"
    elif "reddit.com" in url_lower:
        return "reddit"
    else:
        return "unknown"

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
        await update.message.reply_text(
            "❌ Platform not supported.\n\n"
            "Supported: TikTok, Facebook, YouTube, Instagram, Twitter, Reddit"
        )
        return
    
    # Detect platform
    platform = detect_platform(text)
    
    # Create user directory
    user_dir = Path(f"downloads/{chat_id}")
    user_dir.mkdir(parents=True, exist_ok=True)
    
    # Send processing message
    msg = await update.message.reply_text(f"⏳ Processing {platform} link...")
    
    file_path = None
    try:
        # Get video information first
        await msg.edit_text(f"📋 Getting video info...")
        caption, video_info = await get_video_info(text)
        
        if not caption:
            # If can't get info, create simple caption
            caption = f"📹 Downloaded from {platform}\n🔗 {text}"
        
        # Download video
        await msg.edit_text(f"⬇️ Downloading from {platform}...")
        file_path, error = await download_video(text, str(user_dir), platform)
        
        if error:
            # Format error specific message
            if "format is not available" in error:
                await msg.edit_text(
                    f"❌ Format error on {platform}.\n\n"
                    "This video might not be available in the requested format.\n"
                    "Try a different video or platform."
                )
            else:
                await msg.edit_text(f"❌ Error: {error}")
            return
        
        if not file_path or not file_path.exists():
            await msg.edit_text("❌ File not found after download")
            return
        
        # Check file size
        file_size = file_path.stat().st_size
        if file_size > 50 * 1024 * 1024:  # 50MB
            await msg.edit_text(f"❌ File too large ({file_size/1024/1024:.1f}MB > 50MB)")
            file_path.unlink()
            return
        
        # Add file size to caption
        caption += f"\n📦 File Size: {file_size/1024/1024:.1f}MB"
        
        # Send file
        await msg.edit_text("📤 Uploading...")
        
        with open(file_path, 'rb') as f:
            # Check file type
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
        
        await msg.edit_text(f"✅ Done! {platform} - {file_size/1024/1024:.1f}MB")
        
    except Exception as e:
        logger.error(f"Error: {e}")
        error_msg = f"❌ Error: {str(e)}"
        if platform == "facebook":
            error_msg += "\n\n💡 *Facebook Tip:* Try a different video or use TikTok/YouTube"
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
    logger.error(f"Update {update} caused error: {context.error}")
    if update and update.effective_chat:
        try:
            await update.effective_chat.send_message("⚠️ An error occurred. Please try again.")
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
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    # Error handler
    app.add_error_handler(error_handler)
    
    # Start bot
    logger.info("🤖 Bot starting...")
    print("=" * 50)
    print("✅ Bot running! Press Ctrl+C to stop")
    print("=" * 50)
    
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

echo "🚀 Starting bot..."
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

# Make scripts executable
chmod +x start.sh stop.sh restart.sh

# 8. Create test file
cat << 'EOF' > test.py
#!/usr/bin/env python3
# Simple test

import sys
import os
import subprocess

print("🔧 Testing installation...")
print("=" * 30)

# Check Python
try:
    import platform
    print(f"✅ Python {platform.python_version()}")
except:
    print("❌ Python error")
    sys.exit(1)

# Check packages
packages = ["telegram", "dotenv", "json"]
for pkg in packages:
    try:
        __import__(pkg)
        print(f"✅ {pkg}")
    except ImportError as e:
        print(f"❌ {pkg}: {e}")

# Check .env
if os.path.exists(".env"):
    with open(".env", "r") as f:
        if "BOT_TOKEN=" in f.read():
            print("✅ .env with BOT_TOKEN")
        else:
            print("❌ .env missing BOT_TOKEN")
else:
    print("❌ .env missing")

# Check yt-dlp CLI
result = subprocess.run(["yt-dlp", "--version"], capture_output=True, text=True)
if result.returncode == 0:
    print(f"✅ yt-dlp CLI: {result.stdout.strip()}")
else:
    print("❌ yt-dlp CLI not working")

# Check directories
for dir in ["downloads", "logs", "venv"]:
    if os.path.exists(dir):
        print(f"✅ Directory: {dir}")
    else:
        print(f"❌ Missing: {dir}")

print("=" * 30)
print("🎉 Setup complete!")
print("\n📹 Bot now shows video information:")
print("- Title\n- Uploader\n- Duration")
print("- Views & Likes\n- File size\n- Original URL")
print("\nTo start: ./start.sh")
print("To stop:  ./stop.sh")
EOF

chmod +x test.py

# 9. Create requirements.txt
cat << 'EOF' > requirements.txt
python-telegram-bot==20.7
python-dotenv==1.0.0
EOF

# 10. Final instructions
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "\n📁 ${YELLOW}Files created:${NC}"
ls -la

echo -e "\n🚀 ${YELLOW}To start:${NC}"
echo -e "  ${GREEN}./start.sh${NC}"
echo -e "\n⚙️ ${YELLOW}Other commands:${NC}"
echo -e "  ${GREEN}./stop.sh${NC}      # Stop bot"
echo -e "  ${GREEN}./restart.sh${NC}   # Restart"
echo -e "  ${GREEN}./test.py${NC}      # Test setup"
echo -e "\n✨ ${GREEN}New Features:${NC}"
echo -e "  📹 Video information in caption"
echo -e "  📋 Title, uploader, duration"
echo -e "  👁 Views and likes count"
echo -e "  📦 File size"
echo -e "  🔗 Original URL"
echo -e "\n${RED}⚠️ Important:${NC}"
echo -e "  • Some platforms may not provide all info"
echo -e "  • Facebook may have limited info"
echo -e "  • Max 50MB per file"
echo -e "\n${GREEN}🤖 Bot ready with captions!${NC}"

# 11. Test and ask to start
echo -e "\n${YELLOW}Test installation? (y/n)${NC}"
read -r TEST

if [[ "$TEST" =~ ^[Yy]$ ]]; then
    source venv/bin/activate
    python3 test.py
fi

echo -e "\n${YELLOW}Start bot now? (y/n)${NC}"
read -r START

if [[ "$START" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Starting...${NC}"
    ./start.sh
else
    echo -e "${YELLOW}To start later: ./start.sh${NC}"
fi
