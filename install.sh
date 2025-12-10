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

# 6. Create simple bot.py
echo -e "${YELLOW}📝 Creating bot.py...${NC}"

cat << 'EOF' > $BOT_FILE
#!/usr/bin/env python3
"""
Simple Telegram Downloader Bot
"""
import os
import sys
import logging
import subprocess
import asyncio
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
        "• Facebook needs direct video links"
    )
    await update.message.reply_text(message, parse_mode='Markdown')

async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Send help message"""
    help_text = (
        "❓ *Help*\n\n"
        "1. Copy video link\n"
        "2. Send to bot\n"
        "3. Get downloaded file\n\n"
        "For Facebook:\n"
        "Use: https://www.facebook.com/watch/?v=123456789\n"
        "Not: https://www.facebook.com/share/r/...\n\n"
        "Max size: 50MB"
    )
    await update.message.reply_text(help_text, parse_mode='Markdown')

def is_supported(url):
    """Check if URL is supported"""
    url_lower = url.lower()
    for domain in SUPPORTED_DOMAINS:
        if domain in url_lower:
            return True
    return False

async def download_video(url, output_dir):
    """Download video using yt-dlp"""
    unique_id = uuid4().hex[:8]
    output_template = f"{output_dir}/{unique_id}.%(ext)s"
    
    # Simple yt-dlp command without cookies
    cmd = [
        "yt-dlp",
        "--no-warnings",
        "--format", "best[filesize<=50M]",
        "--max-filesize", "50M",
        "--restrict-filenames",
        "-o", output_template,
        url
    ]
    
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=300)
        
        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='ignore').strip()
            if error:
                # Get last error line
                lines = error.split('\n')
                for line in reversed(lines):
                    if line.strip():
                        return None, line.strip()
            return None, "Download failed"
        
        # Find downloaded file
        for file in Path(output_dir).glob(f"{unique_id}.*"):
            if file.is_file() and file.stat().st_size > 0:
                return file, None
        
        return None, "File not found after download"
        
    except asyncio.TimeoutError:
        return None, "Download timeout"
    except Exception as e:
        return None, str(e)

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
    
    # Create user directory
    user_dir = Path(f"downloads/{chat_id}")
    user_dir.mkdir(parents=True, exist_ok=True)
    
    # Send processing message
    msg = await update.message.reply_text("⏳ Processing...")
    
    file_path = None
    try:
        # Download video
        await msg.edit_text("⬇️ Downloading...")
        file_path, error = await download_video(text, str(user_dir))
        
        if error:
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
        
        # Send file
        await msg.edit_text("📤 Uploading...")
        
        with open(file_path, 'rb') as f:
            # Check file type
            result = subprocess.run(
                ['file', '-b', '--mime-type', str(file_path)],
                capture_output=True, text=True
            )
            mime_type = result.stdout.strip() if result.returncode == 0 else 'video/mp4'
            
            if mime_type.startswith('video'):
                await update.message.reply_video(
                    video=f,
                    caption="✅ Downloaded",
                    supports_streaming=True
                )
            elif mime_type.startswith('image'):
                await update.message.reply_photo(
                    photo=f,
                    caption="✅ Downloaded"
                )
            else:
                await update.message.reply_document(
                    document=f,
                    caption="✅ Downloaded"
                )
        
        await msg.edit_text(f"✅ Done! Size: {file_size/1024/1024:.1f}MB")
        
    except Exception as e:
        logger.error(f"Error: {e}")
        await msg.edit_text(f"❌ Error: {str(e)}")
    
    finally:
        # Cleanup
        if file_path and file_path.exists():
            try:
                file_path.unlink()
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

# 7. Create simple management scripts
echo -e "${YELLOW}📁 Creating simple scripts...${NC}"

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
packages = ["telegram", "dotenv", "yt_dlp"]
for pkg in packages:
    try:
        __import__(pkg)
        print(f"✅ {pkg}")
    except:
        print(f"❌ {pkg}")

# Check .env
if os.path.exists(".env"):
    print("✅ .env exists")
else:
    print("❌ .env missing")

# Check yt-dlp
import subprocess
result = subprocess.run(["yt-dlp", "--version"], capture_output=True, text=True)
if result.returncode == 0:
    print(f"✅ yt-dlp: {result.stdout.strip()}")
else:
    print("❌ yt-dlp not working")

print("=" * 30)
print("✅ Setup complete!")
print("\nTo start: ./start.sh")
print("To stop:  ./stop.sh")
EOF

chmod +x test.py

# 9. Final instructions
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
echo -e "\n📝 ${YELLOW}Usage:${NC}"
echo -e "  1. Start bot: ./start.sh"
echo -e "  2. Send /start to your bot"
echo -e "  3. Send video link"
echo -e "\n${RED}⚠️ Note:${NC}"
echo -e "  • No Chrome/cookies needed"
echo -e "  • Facebook: Use direct video links"
echo -e "  • Max 50MB per file"
echo -e "\n${GREEN}🤖 Done!${NC}"

# 10. Test and ask to start
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
