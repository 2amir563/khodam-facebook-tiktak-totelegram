#!/bin/bash

# Telegram Media Downloader Bot - Installation Script
# Optimized for weak servers

set -e  # Exit on error

echo "======================================"
echo "Telegram Media Downloader Bot Installer"
echo "======================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or use sudo"
    exit 1
fi

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install system dependencies
echo "Installing system dependencies..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    ffmpeg \
    curl \
    wget \
    screen \
    cron \
    nano

# Install Python packages
echo "Installing Python packages..."
pip3 install --upgrade pip
pip3 install \
    python-telegram-bot==20.7 \
    yt-dlp==2024.4.9 \
    python-dotenv==1.0.0 \
    aiofiles==23.2.1 \
    psutil==5.9.8 \
    requests==2.31.0 \
    beautifulsoup4==4.12.3

# Clone the repository (update with your repo)
echo "Cloning bot repository..."
cd /opt
if [ -d "telegram-media-bot" ]; then
    echo "Directory exists, updating..."
    cd telegram-media-bot
    git pull
else
    git clone https://github.com/2amir563/khodam-facebook-tiktak-totelegram telegram-media-bot
    cd telegram-media-bot
fi

# Create necessary directories
echo "Creating directories..."
mkdir -p downloads logs cookies tmp
chmod 755 downloads logs cookies tmp

# Create environment file
echo "Creating environment configuration..."
cat > .env << EOF
# Telegram Bot Configuration
BOT_TOKEN=YOUR_BOT_TOKEN_HERE

# Server Settings
MAX_FILE_SIZE=2000  # MB
DELETE_AFTER_MINUTES=2
CONCURRENT_DOWNLOADS=1
MAX_RETRIES=3

# yt-dlp Settings
YTDLP_COOKIES_FILE=cookies/cookies.txt
YTDLP_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
EOF

echo "Please edit the .env file and add your bot token:"
echo "1. nano /opt/telegram-media-bot/.env"
echo "2. Replace YOUR_BOT_TOKEN_HERE with your actual token"
echo ""
echo "Get your token from @BotFather on Telegram"
echo "Press Enter to continue..."
read

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/telegram-media-bot.service << EOF
[Unit]
Description=Telegram Media Downloader Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/telegram-media-bot
ExecStart=/usr/bin/python3 /opt/telegram-media-bot/bot.py
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=telegram-media-bot
Environment=PYTHONUNBUFFERED=1

# Security and resource limits
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/telegram-media-bot/downloads /opt/telegram-media-bot/logs

# Resource limits for weak servers
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

# Create cleanup cron job
echo "Creating cleanup cron job..."
cat > /etc/cron.d/telegram-media-cleanup << EOF
*/5 * * * * root find /opt/telegram-media-bot/downloads -type f -mmin +5 -delete 2>/dev/null
*/5 * * * * root find /opt/telegram-media-bot/tmp -type f -mmin +5 -delete 2>/dev/null
EOF

# Enable and start service
echo "Enabling and starting bot service..."
systemctl daemon-reload
systemctl enable telegram-media-bot.service
systemctl start telegram-media-bot.service

# Create management script
cat > /usr/local/bin/manage-bot << 'EOF'
#!/bin/bash
case "$1" in
    start)
        systemctl start telegram-media-bot
        ;;
    stop)
        systemctl stop telegram-media-bot
        ;;
    restart)
        systemctl restart telegram-media-bot
        ;;
    status)
        systemctl status telegram-media-bot
        ;;
    logs)
        journalctl -u telegram-media-bot -f
        ;;
    update)
        cd /opt/telegram-media-bot
        git pull
        systemctl restart telegram-media-bot
        ;;
    *)
        echo "Usage: manage-bot {start|stop|restart|status|logs|update}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/manage-bot

echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "IMPORTANT: Edit the .env file with your bot token:"
echo "nano /opt/telegram-media-bot/.env"
echo ""
echo "Bot management commands:"
echo "  manage-bot start     - Start bot"
echo "  manage-bot stop      - Stop bot"
echo "  manage-bot restart   - Restart bot"
echo "  manage-bot status    - Check status"
echo "  manage-bot logs      - View logs"
echo "  manage-bot update    - Update bot"
echo ""
echo "Bot should be running. Check status with:"
echo "systemctl status telegram-media-bot"
echo ""
echo "To test, send /start to your bot on Telegram"
