#!/bin/bash

# =========================================================
#         Integrated Telegram Downloader Bot Setup
# =========================================================
# This single script handles the installation, configuration, and execution
# of a Telegram downloader bot using yt-dlp and Python.

set -e  # Stop on any error

BOT_FILE="bot.py"
ENV_FILE=".env"
CONFIG_FILE="bot_config.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🛠️ Starting Telegram Downloader Bot Installation...${NC}"

# 1. Update packages and install prerequisites
echo -e "${YELLOW}📦 Updating system packages and installing dependencies...${NC}"
sudo apt update
sudo apt install -y python3 python3-pip git curl libmagic1 ffmpeg python3-venv

# 2. Install yt-dlp (the core downloader tool)
echo -e "${YELLOW}⬇️ Installing yt-dlp...${NC}"
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+x /usr/local/bin/yt-dlp
yt-dlp --version

# 3. Create directory structure
echo -e "${YELLOW}📁 Creating directory structure...${NC}"
mkdir -p downloads
mkdir -p logs

# 4. Create virtual environment and install Python libraries
echo -e "${YELLOW}🐍 Setting up Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Upgrade pip first
pip install --upgrade pip

# Install required packages
pip install python-telegram-bot python-dotenv uuid

# 5. Configure Bot Token
echo -e "${GREEN}🤖 Telegram Bot Configuration${NC}"
echo -e "${YELLOW}Please enter your Telegram Bot Token (from @BotFather):${NC}"
read -r BOT_TOKEN

# Validate token format
if [[ ! $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Invalid bot token format!${NC}"
    exit 1
fi

echo "BOT_TOKEN=$BOT_TOKEN" > $ENV_FILE
echo -e "${GREEN}✅ Token saved to $ENV_FILE${NC}"

# 6. Create configuration file
cat << 'EOF' > $CONFIG_FILE
# =========================================================
#                     Configuration
# =========================================================
import os
from dotenv import load_dotenv

load_dotenv()

# Bot Configuration
BOT_TOKEN = os.getenv("BOT_TOKEN")

# Download Settings
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
DOWNLOAD_TIMEOUT = 300  # 5 minutes
MAX_CONCURRENT_DOWNLOADS = 3

# Paths
DOWNLOAD_BASE_DIR = "./downloads"
LOG_FILE = "./logs/bot.log"

# Supported Platforms
SUPPORTED_PLATFORMS = [
    "tiktok.com",
    "facebook.com", 
    "fb.watch",
    "terabox.com",
    "loom.com",
    "streamable.com",
    "pinterest.com",
    "pin.it",
    "snapchat.com",
    "youtube.com",
    "youtu.be",
    "instagram.com",
    "twitter.com",
    "x.com",
    "reddit.com",
    "likee.video",
    "like.com"
]

# yt-dlp Configuration
YT_DLP_OPTIONS = [
    '--no-warnings',
    '--no-progress',
    '--restrict-filenames',
    '--format', 'best[filesize<=50M]',
    '--max-filesize', '50M',
    '--socket-timeout', '30',
    '--retries', '3',
    '--fragment-retries', '3'
]
EOF

# 7. Create the main bot file
echo -e "${YELLOW}📝 Creating bot.py...${NC}"

cat << 'EOF' > $BOT_FILE
#!/usr/bin/env python3
# =========================================================
#                 Telegram Downloader Bot
# =========================================================
import os
import sys
import logging
import subprocess
import asyncio
from pathlib import Path
from uuid import uuid4
from datetime import datetime

# Add current directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.error import TelegramError
import bot_config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(bot_config.LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DownloadManager:
    def __init__(self):
        self.download_dir = Path(bot_config.DOWNLOAD_BASE_DIR)
        self.download_dir.mkdir(exist_ok=True)
    
    def get_download_path(self, chat_id: int) -> Path:
        """Get download path for specific chat"""
        chat_dir = self.download_dir / str(chat_id)
        chat_dir.mkdir(exist_ok=True)
        return chat_dir
    
    def cleanup_old_files(self, chat_dir: Path, max_age_hours: int = 24):
        """Clean up files older than specified hours"""
        try:
            now = datetime.now()
            for file_path in chat_dir.glob("*"):
                if file_path.is_file():
                    file_age = now - datetime.fromtimestamp(file_path.stat().st_mtime)
                    if file_age.total_seconds() > max_age_hours * 3600:
                        file_path.unlink()
                        logger.info(f"Cleaned up old file: {file_path}")
        except Exception as e:
            logger.warning(f"Cleanup error: {e}")

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    welcome_msg = (
        "👋 *Welcome to Downloader Bot!*\n\n"
        "📥 *Supported Platforms:*\n"
        "• TikTok\n• Facebook\n• Terabox\n• Loom\n"
        "• Streamable\n• Pinterest\n• Snapchat\n"
        "• YouTube\n• Instagram\n• Twitter/X\n• Reddit\n\n"
        "📝 *How to use:*\n"
        "Just send me a link from any supported platform!\n\n"
        "⚠️ *Limitations:*\n"
        "• Max file size: 50MB\n"
        "• Public videos only\n"
        "• May not work with private/restricted content"
    )
    await update.message.reply_text(welcome_msg, parse_mode='Markdown')

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_msg = (
        "❓ *Help*\n\n"
        "1. Copy link from supported platform\n"
        "2. Send link to this bot\n"
        "3. Wait for download and receive file\n\n"
        "If download fails:\n"
        "• Check if link is public\n"
        "• Try again later\n"
        "• Contact admin for support"
    )
    await update.message.reply_text(help_msg, parse_mode='Markdown')

def is_supported_url(url: str) -> bool:
    """Check if URL is from supported platform"""
    import urllib.parse
    try:
        parsed = urllib.parse.urlparse(url)
        domain = parsed.netloc.lower()
        
        # Remove www. prefix
        if domain.startswith("www."):
            domain = domain[4:]
        
        # Check against supported platforms
        for platform in bot_config.SUPPORTED_PLATFORMS:
            if platform in domain:
                return True
        
        # Additional check for full URL
        url_lower = url.lower()
        for platform in bot_config.SUPPORTED_PLATFORMS:
            if platform in url_lower:
                return True
        
        return False
    except:
        return False

async def download_with_ytdlp(url: str, output_path: Path) -> Path:
    """Download using yt-dlp with proper error handling"""
    unique_id = uuid4().hex
    filename_template = f"{unique_id}.%(ext)s"
    output_template = str(output_path / filename_template)
    
    # Build command
    cmd = [
        "yt-dlp",
        *bot_config.YT_DLP_OPTIONS,
        "--output", output_template,
        url
    ]
    
    logger.info(f"Executing: {' '.join(cmd)}")
    
    try:
        # Run yt-dlp and capture output
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            error_msg = stderr.decode('utf-8', errors='ignore').strip()
            logger.error(f"yt-dlp failed: {error_msg}")
            raise Exception(f"Download failed: {error_msg.splitlines()[-1] if error_msg else 'Unknown error'}")
        
        # Parse output to find downloaded file
        output_text = stdout.decode('utf-8', errors='ignore')
        lines = output_text.strip().split('\n')
        
        # Look for file path in output
        downloaded_file = None
        for line in reversed(lines):  # Check from bottom up
            line = line.strip()
            if line and os.path.exists(line):
                downloaded_file = Path(line)
                break
        
        # If not found in output, search directory
        if not downloaded_file:
            for file_path in output_path.glob(f"{unique_id}.*"):
                if file_path.is_file() and file_path.stat().st_size > 0:
                    downloaded_file = file_path
                    break
        
        if not downloaded_file or not downloaded_file.exists():
            # Try to find any new file in directory
            files_before = set(output_path.glob("*"))
            # The download happened, check for new files
            files_after = set(output_path.glob("*"))
            new_files = files_after - files_before
            
            for file_path in new_files:
                if file_path.is_file() and file_path.stat().st_size > 0:
                    downloaded_file = file_path
                    break
        
        if not downloaded_file or not downloaded_file.exists():
            raise FileNotFoundError("Downloaded file not found after yt-dlp execution")
        
        return downloaded_file
        
    except asyncio.TimeoutError:
        raise Exception("Download timed out after 5 minutes")
    except Exception as e:
        raise Exception(f"Download error: {str(e)}")

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle incoming messages"""
    user = update.effective_user
    chat_id = update.effective_chat.id
    text = update.message.text.strip()
    
    logger.info(f"Message from {user.id} ({user.username}): {text}")
    
    # Check if it's a URL
    if not text.startswith(('http://', 'https://')):
        await update.message.reply_text("⚠️ Please send a valid URL starting with http:// or https://")
        return
    
    # Check if supported
    if not is_supported_url(text):
        await update.message.reply_text(
            "❌ This platform is not supported or URL is invalid.\n"
            "Use /start to see supported platforms."
        )
        return
    
    # Initialize download manager
    dm = DownloadManager()
    chat_dir = dm.get_download_path(chat_id)
    dm.cleanup_old_files(chat_dir)
    
    # Send initial message
    status_msg = await update.message.reply_text(
        f"⏳ *Processing your request...*\n"
        f"URL: `{text}`\n"
        f"Please wait...",
        parse_mode='Markdown'
    )
    
    downloaded_file = None
    
    try:
        # Update status
        await status_msg.edit_text("⬇️ *Downloading...* This may take a moment.", parse_mode='Markdown')
        
        # Download file
        downloaded_file = await download_with_ytdlp(text, chat_dir)
        
        if not downloaded_file or not downloaded_file.exists():
            raise FileNotFoundError("File not found after download")
        
        file_size = downloaded_file.stat().st_size
        if file_size > bot_config.MAX_FILE_SIZE:
            raise Exception(f"File too large ({file_size/1024/1024:.1f}MB > 50MB)")
        
        # Update status
        await status_msg.edit_text("📤 *Uploading to Telegram...*", parse_mode='Markdown')
        
        # Send file based on type
        mime_type = subprocess.run(
            ['file', '-b', '--mime-type', str(downloaded_file)],
            capture_output=True, text=True
        ).stdout.strip()
        
        with open(downloaded_file, 'rb') as f:
            if mime_type.startswith('video'):
                await update.message.reply_video(
                    video=f,
                    caption=f"✅ Downloaded from: {text}",
                    supports_streaming=True,
                    write_timeout=60,
                    read_timeout=60,
                    connect_timeout=60
                )
            elif mime_type.startswith('image'):
                await update.message.reply_photo(
                    photo=f,
                    caption=f"✅ Downloaded from: {text}",
                    write_timeout=60
                )
            else:
                await update.message.reply_document(
                    document=f,
                    caption=f"✅ Downloaded from: {text}",
                    write_timeout=60
                )
        
        # Final success message
        await status_msg.edit_text(
            f"✅ *Download complete!*\n"
            f"File size: {file_size/1024/1024:.1f}MB",
            parse_mode='Markdown'
        )
        
        logger.info(f"Successfully sent file to {user.id}: {downloaded_file}")
        
    except FileNotFoundError as e:
        error_msg = f"❌ *File Not Found*\nThe file was downloaded but could not be located.\n\nError: `{str(e)}`"
        await status_msg.edit_text(error_msg, parse_mode='Markdown')
        logger.error(f"File not found for {text}: {e}")
        
    except Exception as e:
        error_msg = f"❌ *Download Failed*\n\nError: `{str(e)}`\n\nPlease try again or use a different link."
        await status_msg.edit_text(error_msg, parse_mode='Markdown')
        logger.error(f"Download failed for {text}: {e}")
        
    finally:
        # Cleanup
        if downloaded_file and downloaded_file.exists():
            try:
                downloaded_file.unlink()
                logger.info(f"Cleaned up: {downloaded_file}")
            except Exception as e:
                logger.warning(f"Failed to cleanup {downloaded_file}: {e}")

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle errors"""
    logger.error(f"Update {update} caused error: {context.error}")
    
    if update and update.effective_chat:
        try:
            await update.effective_chat.send_message(
                "⚠️ An error occurred. Please try again later."
            )
        except:
            pass

def main():
    """Main function to run the bot"""
    if not bot_config.BOT_TOKEN:
        logger.error("❌ BOT_TOKEN not found in .env file!")
        sys.exit(1)
    
    # Create application
    application = Application.builder() \
        .token(bot_config.BOT_TOKEN) \
        .read_timeout(30) \
        .write_timeout(30) \
        .connect_timeout(30) \
        .build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    # Add error handler
    application.add_error_handler(error_handler)
    
    # Start bot
    logger.info("🤖 Bot is starting...")
    print("=" * 50)
    print("✅ Bot is running! Press Ctrl+C to stop.")
    print("=" * 50)
    
    application.run_polling(
        allowed_updates=Update.ALL_TYPES,
        drop_pending_updates=True
    )

if __name__ == "__main__":
    main()
EOF

# Make bot.py executable
chmod +x $BOT_FILE

# 8. Create systemd service file (optional)
echo -e "${YELLOW}⚙️ Creating systemd service...${NC}"

cat << 'EOF' > /tmp/telegram-downloader.service
[Unit]
Description=Telegram Downloader Bot
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$(pwd)
Environment="PATH=$(pwd)/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$(pwd)/venv/bin/python3 $(pwd)/bot.py
Restart=always
RestartSec=10
StandardOutput=append:$(pwd)/logs/bot.log
StandardError=append:$(pwd)/logs/bot-error.log

[Install]
WantedBy=multi-user.target
EOF

# 9. Test installation
echo -e "${YELLOW}🔧 Testing installation...${NC}"

# Test Python
if python3 --version &> /dev/null; then
    echo -e "${GREEN}✅ Python3 is installed${NC}"
else
    echo -e "${RED}❌ Python3 not found${NC}"
    exit 1
fi

# Test yt-dlp
if yt-dlp --version &> /dev/null; then
    echo -e "${GREEN}✅ yt-dlp is installed${NC}"
else
    echo -e "${RED}❌ yt-dlp not found${NC}"
    exit 1
fi

# Test virtual environment
if source venv/bin/activate && python3 -c "import telegram, dotenv" &> /dev/null; then
    echo -e "${GREEN}✅ Python packages are installed${NC}"
else
    echo -e "${RED}❌ Python packages missing${NC}"
    exit 1
fi

# 10. Create startup script
cat << 'EOF' > start_bot.sh
#!/bin/bash

# Start Telegram Downloader Bot

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Check if bot is already running
if pgrep -f "python3.*bot.py" > /dev/null; then
    echo "⚠️ Bot is already running!"
    echo "To restart, run: pkill -f bot.py && ./start_bot.sh"
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check .env file
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    echo "Please create .env file with BOT_TOKEN=your_token_here"
    exit 1
fi

# Create necessary directories
mkdir -p downloads
mkdir -p logs

# Start bot
echo "🚀 Starting Telegram Downloader Bot..."
echo "📝 Logs: logs/bot.log"
echo "🛑 Press Ctrl+C to stop"

python3 bot.py
EOF

chmod +x start_bot.sh

# 11. Create stop script
cat << 'EOF' > stop_bot.sh
#!/bin/bash

# Stop Telegram Downloader Bot

echo "🛑 Stopping bot..."

# Kill bot process
pkill -f "python3.*bot.py" 2>/dev/null && echo "✅ Bot stopped" || echo "⚠️ Bot was not running"

# Kill yt-dlp processes if any
pkill -f "yt-dlp" 2>/dev/null && echo "✅ Cleaned up yt-dlp processes"
EOF

chmod +x stop_bot.sh

# 12. Create log viewer
cat << 'EOF' > view_logs.sh
#!/bin/bash

# View bot logs

LOG_FILE="logs/bot.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "No log file found. Starting bot first..."
    ./start_bot.sh
else
    echo "📋 Showing last 100 lines of logs. Press Ctrl+C to exit."
    echo "=" * 60
    tail -100f "$LOG_FILE"
fi
EOF

chmod +x view_logs.sh

# 13. Final instructions
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "\n📁 ${YELLOW}Project Structure:${NC}"
echo -e "  ├── 📄 bot.py              # Main bot file"
echo -e "  ├── 📄 .env                # Bot token configuration"
echo -e "  ├── 📄 bot_config.py       # Configuration file"
echo -e "  ├── 📁 downloads/          # Temporary downloads"
echo -e "  ├── 📁 logs/              # Log files"
echo -e "  └── 📁 venv/              # Python virtual environment"
echo -e "\n🚀 ${YELLOW}How to start the bot:${NC}"
echo -e "  ${GREEN}./start_bot.sh${NC}           # Start bot in foreground"
echo -e "  ${GREEN}nohup ./start_bot.sh &${NC}   # Start in background"
echo -e "\n⚙️ ${YELLOW}Other commands:${NC}"
echo -e "  ${GREEN}./stop_bot.sh${NC}            # Stop the bot"
echo -e "  ${GREEN}./view_logs.sh${NC}           # View logs"
echo -e "\n🔧 ${YELLOW}To set up as system service:${NC}"
echo -e "  sudo cp /tmp/telegram-downloader.service /etc/systemd/system/"
echo -e "  sudo systemctl daemon-reload"
echo -e "  sudo systemctl enable telegram-downloader"
echo -e "  sudo systemctl start telegram-downloader"
echo -e "\n📝 ${YELLOW}Test the bot:${NC}"
echo -e "  1. Send /start to your bot on Telegram"
echo -e "  2. Send a TikTok/Facebook/YouTube link"
echo -e "\n${RED}⚠️  Important:${NC}"
echo -e "  • Keep your .env file secure!"
echo -e "  • Bot only downloads public content"
echo -e "  • Max file size: 50MB"
echo -e "\n${GREEN}🤖 Happy downloading!${NC}"
echo -e "${GREEN}==================================================${NC}"

# 14. Start bot in background
echo -e "\n${YELLOW}Starting bot in background...${NC}"
nohup ./venv/bin/python3 bot.py > logs/bot.log 2>&1 &

sleep 3

if pgrep -f "python3.*bot.py" > /dev/null; then
    echo -e "${GREEN}✅ Bot started successfully!${NC}"
    echo -e "📝 Check logs: ${YELLOW}tail -f logs/bot.log${NC}"
else
    echo -e "${RED}⚠️  Bot might not have started. Check logs.${NC}"
    echo -e "Run manually: ${YELLOW}./start_bot.sh${NC}"
fi
