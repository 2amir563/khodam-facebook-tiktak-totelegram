#!/bin/bash

# Ultimate Telegram Video Downloader Bot
# Supports: TikTok, Facebook, Instagram, Terabox, Loom, Streamable, Snapchat, Pinterest
# GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

log "Installing Ultimate Video Downloader Bot..."

# Update system
log "Updating system..."
apt-get update -y
apt-get upgrade -y

# Install dependencies
log "Installing dependencies..."
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg

# Create bot directory
BOT_DIR="/root/telegram-video-bot"
log "Creating bot directory at $BOT_DIR..."
mkdir -p "$BOT_DIR"
cd "$BOT_DIR"

# Create virtual environment
log "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python packages
log "Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.6 yt-dlp==2025.12.8 requests==2.31.0 beautifulsoup4==4.12.0 lxml==5.2.0

# Create ultimate config
log "Creating configuration files..."

# config.py
cat > config.py << 'EOF'
#!/usr/bin/env python3
import os

BOT_TOKEN = os.environ.get("BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")

MAX_FILE_SIZE = 2000 * 1024 * 1024
DOWNLOAD_PATH = "./downloads"
TEMP_PATH = "./temp"

# User agents
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.210 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36 Edg/91.0.864.59",
]

# Platform configurations
PLATFORM_CONFIGS = {
    "facebook": {
        "formats": ["best[height<=720]", "best[filesize<100M]", "best", "worst"],
        "headers": {
            "Referer": "https://www.facebook.com/",
            "Origin": "https://www.facebook.com",
        },
        "extractor_args": {"facebook": {"credentials": None}},
    },
    "tiktok": {
        "formats": ["best[height<=720]", "best", "worst", "bestvideo[height<=720]+bestaudio"],
        "headers": {
            "Referer": "https://www.tiktok.com/",
            "Origin": "https://www.tiktok.com",
        },
        "extractor_args": {
            "tiktok": {"app_version": "29.0.0", "manifest_app_version": "29.0.0"}
        },
    },
    "terabox": {
        "formats": ["best", "best[filesize<200M]"],
        "headers": {"Referer": "https://www.terabox.com/"},
    },
    "loom": {
        "formats": ["best", "best[height<=1080]"],
        "headers": {"Referer": "https://www.loom.com/"},
    },
    "streamable": {
        "formats": ["best", "best[height<=1080]"],
        "headers": {"Referer": "https://streamable.com/"},
    },
    "snapchat": {
        "formats": ["best", "best[height<=720]"],
        "headers": {"Referer": "https://www.snapchat.com/"},
    },
    "pinterest": {
        "formats": ["best", "best[ext=mp4]"],
        "headers": {"Referer": "https://www.pinterest.com/"},
    },
    "instagram": {
        "formats": ["best", "best[height<=1080]"],
        "headers": {"Referer": "https://www.instagram.com/"},
    },
}

MESSAGES = {
    "start": """
🤖 **Ultimate Video Downloader Bot**

📥 **Supported Platforms:**
• TikTok (videos)
• Facebook (videos, reels)
• Instagram (reels, posts)
• Terabox (videos)
• Loom (videos)
• Streamable (videos)
• Snapchat (spotlights)
• Pinterest (videos, images)

📌 **Note:** Some videos may be private or require login.

🔧 **Commands:**
/start - Start bot
/help - Show help
/about - About bot
/supported - Show supported platforms
""",
    
    "help": """
📖 **How to use:**

1. Send a video/image link from any supported platform
2. Wait for download
3. Receive file in Telegram

💡 **Tips for better results:**
• Use fresh links from mobile apps
• TikTok: Share → Copy Link
• Facebook: Direct video URLs only
• Some videos are private
""",
    
    "about": """
📱 **Ultimate Video Downloader Bot**

GitHub: https://github.com/2amir563/khodam-facebook-tiktak-totelegram

✅ Supports 8+ platforms
✅ Multiple download methods
✅ Automatic retry
✅ Optimized for each platform
""",
    
    "supported": """
📋 **Supported Platforms:**

1. **TikTok** - All public videos
2. **Facebook** - Videos, Reels (public only)
3. **Instagram** - Reels, Posts (public)
4. **Terabox** - Video files
5. **Loom** - Screen recordings
6. **Streamable** - Uploaded videos
7. **Snapchat** - Spotlights only
8. **Pinterest** - Videos & Images

⚠️ **Limitations:**
• Private videos cannot be downloaded
• Some platforms may require cookies
• Max file size: 2GB
"""
}
EOF

# Create ultimate bot file
log "Creating ultimate bot.py..."

cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Ultimate Telegram Video Downloader Bot
Supports: TikTok, Facebook, Instagram, Terabox, Loom, Streamable, Snapchat, Pinterest
"""

import os
import re
import sys
import json
import logging
import shutil
import tempfile
import random
import time
from urllib.parse import urlparse, unquote, quote, parse_qs
from datetime import datetime

from telegram import Update, InputFile
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
from telegram.constants import ParseMode

import yt_dlp
import requests
from bs4 import BeautifulSoup

import config

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Create directories
os.makedirs(config.DOWNLOAD_PATH, exist_ok=True)
os.makedirs(config.TEMP_PATH, exist_ok=True)

class UltimateDownloader:
    def __init__(self):
        self.session = requests.Session()
        self.cookies_file = 'cookies.txt' if os.path.exists('cookies.txt') else None
        
    def detect_platform(self, url):
        """Detect platform from URL"""
        url_lower = url.lower()
        
        platform_patterns = {
            "tiktok": [r'tiktok\.com', r'vm\.tiktok\.com', r'vt\.tiktok\.com'],
            "facebook": [r'facebook\.com', r'fb\.watch', r'fb\.com'],
            "instagram": [r'instagram\.com', r'instagr\.am'],
            "terabox": [r'terabox\.com', r'1024tera\.com'],
            "loom": [r'loom\.com', r'loom\.share'],
            "streamable": [r'streamable\.com'],
            "snapchat": [r'snapchat\.com', r'snap\.ly'],
            "pinterest": [r'pinterest\.com', r'pin\.it'],
        }
        
        for platform, patterns in platform_patterns.items():
            for pattern in patterns:
                if re.search(pattern, url_lower):
                    return platform
        
        return "unknown"
    
    def fix_facebook_url(self, url):
        """Fix Facebook URL issues"""
        # Remove login redirects
        if 'facebook.com/login' in url or 'facebook.com/dialog' in url:
            # Try to extract actual URL
            match = re.search(r'next=(https?%3A%2F%2F[^&]+)', url)
            if match:
                try:
                    decoded = unquote(unquote(match.group(1)))
                    if 'facebook.com' in decoded:
                        url = decoded
                except:
                    pass
        
        # Remove tracking parameters
        url = re.sub(r'[?&](share_|rdid|set|ref|comment_id|reply_comment_id)=[^&]+', '', url)
        url = re.sub(r'[?&]__cft__[^&]+', '', url)
        url = re.sub(r'[?&]__tn__=[^&]+', '', url)
        
        # Convert to mobile version for better access
        url = url.replace('www.facebook.com', 'm.facebook.com')
        
        # Ensure it's a video URL
        if '/videos/' not in url and '/reel/' not in url and '/watch/' not in url:
            # Try to find video ID
            video_id_match = re.search(r'v=(\d+)', url) or re.search(r'/videos/(\d+)', url)
            if video_id_match:
                url = f"https://m.facebook.com/watch/?v={video_id_match.group(1)}"
        
        return url
    
    def get_facebook_direct_url(self, url):
        """Try to get direct Facebook video URL"""
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
                'Accept-Encoding': 'gzip, deflate, br',
                'DNT': '1',
                'Connection': 'keep-alive',
            }
            
            response = self.session.get(url, headers=headers, timeout=10)
            
            # Look for video sources in HTML
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Method 1: Look for video tag
            video_tags = soup.find_all('video')
            for video in video_tags:
                if video.get('src'):
                    return video['src']
            
            # Method 2: Look for meta tags
            meta_tags = soup.find_all('meta', property='og:video')
            for meta in meta_tags:
                if meta.get('content'):
                    return meta['content']
            
            meta_tags = soup.find_all('meta', property='og:video:url')
            for meta in meta_tags:
                if meta.get('content'):
                    return meta['content']
            
            # Method 3: Look for JSON data
            script_tags = soup.find_all('script', type='application/ld+json')
            for script in script_tags:
                try:
                    data = json.loads(script.string)
                    if isinstance(data, dict) and 'contentUrl' in data:
                        return data['contentUrl']
                except:
                    continue
            
            # Method 4: Look for JavaScript variables
            text = response.text
            patterns = [
                r'"video_data":\s*({[^}]+})',
                r'"sd_src":"([^"]+)"',
                r'"hd_src":"([^"]+)"',
                r'video_url":"([^"]+)"',
            ]
            
            for pattern in patterns:
                matches = re.findall(pattern, text)
                for match in matches:
                    if match and ('http' in match or '//' in match):
                        return match if match.startswith('http') else f'https:{match}'
            
        except Exception as e:
            logger.error(f"Facebook direct URL error: {e}")
        
        return None
    
    def download_with_ytdlp(self, url, platform, temp_dir):
        """Download using yt-dlp with platform-specific settings"""
        if platform not in config.PLATFORM_CONFIGS:
            platform = "default"
            config.PLATFORM_CONFIGS["default"] = {"formats": ["best"], "headers": {}}
        
        platform_config = config.PLATFORM_CONFIGS[platform]
        
        # Special handling for Facebook
        if platform == "facebook":
            # Try to get direct video URL first
            direct_url = self.get_facebook_direct_url(url)
            if direct_url:
                logger.info(f"Found direct Facebook URL: {direct_url}")
                url = direct_url
            
            # Also try with cookies if available
            if self.cookies_file:
                logger.info("Using cookies for Facebook download")
        
        ydl_opts = {
            'outtmpl': os.path.join(temp_dir, 'video.%(ext)s'),
            'quiet': False,
            'no_warnings': False,
            'extractaudio': False,
            'keepvideo': True,
            'writethumbnail': True,
            'merge_output_format': 'mp4',
            'http_headers': {
                'User-Agent': random.choice(config.USER_AGENTS),
                'Accept': '*/*',
                'Accept-Language': 'en-US,en;q=0.9',
                **platform_config.get('headers', {})
            },
            'cookiefile': self.cookies_file,
            'ignoreerrors': True,
            'retries': 10,
            'fragment_retries': 10,
            'skip_unavailable_fragments': True,
            'no_check_certificate': True,
            'geo_bypass': True,
            'geo_bypass_country': 'US',
            'extractor_args': platform_config.get('extractor_args', {}),
            'postprocessors': [
                {
                    'key': 'FFmpegVideoConvertor',
                    'preferedformat': 'mp4',
                }
            ] if platform != 'pinterest' else [],
        }
        
        # Try multiple formats
        formats = platform_config.get('formats', ['best'])
        
        for fmt in formats:
            ydl_opts['format'] = fmt
            try:
                logger.info(f"Trying {platform} with format: {fmt}")
                
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=True)
                    
                    # Find downloaded file
                    for file in os.listdir(temp_dir):
                        if platform == 'pinterest':
                            # Pinterest can be image or video
                            if file.endswith(('.mp4', '.webm', '.mkv', '.jpg', '.jpeg', '.png', '.webp')):
                                return self.prepare_result(file, temp_dir, info, platform, url)
                        else:
                            if file.endswith(('.mp4', '.webm', '.mkv', '.avi', '.mov')):
                                return self.prepare_result(file, temp_dir, info, platform, url)
                
            except Exception as e:
                logger.warning(f"Format {fmt} failed for {platform}: {e}")
                continue
        
        return {'success': False, 'error': f'All formats failed for {platform}'}
    
    def prepare_result(self, filename, temp_dir, info, platform, original_url):
        """Prepare result dictionary"""
        file_path = os.path.join(temp_dir, filename)
        
        # Get metadata
        title = info.get('title', f'{platform.title()} Media') if info else f'{platform.title()} Media'
        uploader = info.get('uploader', platform.title()) if info else platform.title()
        duration = info.get('duration', 0) if info else 0
        
        # Clean title
        title = re.sub(r'[^\w\s\-\.]', '', title)[:100]
        
        return {
            'success': True,
            'file_path': file_path,
            'title': title,
            'uploader': uploader,
            'duration': duration,
            'url': original_url,
            'platform': platform,
            'is_video': filename.endswith(('.mp4', '.webm', '.mkv', '.avi', '.mov')),
            'is_image': filename.endswith(('.jpg', '.jpeg', '.png', '.webp', '.gif')),
            'temp_dir': temp_dir,
        }
    
    def download_terabox(self, url, temp_dir):
        """Special downloader for Terabox"""
        try:
            # Terabox often requires special handling
            headers = {
                'User-Agent': random.choice(config.USER_AGENTS),
                'Referer': 'https://www.terabox.com/',
                'Accept': '*/*',
            }
            
            # Try yt-dlp first
            result = self.download_with_ytdlp(url, 'terabox', temp_dir)
            if result['success']:
                return result
            
            # Try direct download
            response = self.session.get(url, headers=headers, timeout=10)
            
            # Look for download links
            soup = BeautifulSoup(response.text, 'html.parser')
            download_links = []
            
            for a in soup.find_all('a', href=True):
                href = a['href']
                if any(ext in href.lower() for ext in ['.mp4', '.avi', '.mkv', '.mov', '.webm']):
                    download_links.append(href)
            
            for link in download_links[:3]:  # Try first 3 links
                try:
                    if not link.startswith('http'):
                        link = 'https://www.terabox.com' + link
                    
                    video_response = self.session.get(link, headers=headers, stream=True, timeout=30)
                    if video_response.status_code == 200:
                        file_path = os.path.join(temp_dir, 'terabox_video.mp4')
                        with open(file_path, 'wb') as f:
                            for chunk in video_response.iter_content(chunk_size=8192):
                                if chunk:
                                    f.write(chunk)
                        
                        return {
                            'success': True,
                            'file_path': file_path,
                            'title': 'Terabox Video',
                            'uploader': 'Terabox',
                            'duration': 0,
                            'url': url,
                            'platform': 'terabox',
                            'is_video': True,
                            'is_image': False,
                            'temp_dir': temp_dir,
                        }
                except:
                    continue
            
            return {'success': False, 'error': 'Terabox download failed'}
            
        except Exception as e:
            logger.error(f"Terabox error: {e}")
            return {'success': False, 'error': str(e)}
    
    def download_loom(self, url, temp_dir):
        """Special downloader for Loom"""
        try:
            # Loom usually works well with yt-dlp
            result = self.download_with_ytdlp(url, 'loom', temp_dir)
            if result['success']:
                return result
            
            # Alternative method
            headers = {
                'User-Agent': random.choice(config.USER_AGENTS),
                'Referer': 'https://www.loom.com/',
            }
            
            # Extract video ID
            video_id_match = re.search(r'loom\.com/share/([a-f0-9]+)', url)
            if video_id_match:
                video_id = video_id_match.group(1)
                api_url = f"https://www.loom.com/api/campaigns/sessions/{video_id}"
                
                api_response = self.session.get(api_url, headers=headers)
                if api_response.status_code == 200:
                    data = api_response.json()
                    if 'url' in data:
                        video_url = data['url']
                        
                        video_response = self.session.get(video_url, headers=headers, stream=True)
                        if video_response.status_code == 200:
                            file_path = os.path.join(temp_dir, 'loom_video.mp4')
                            with open(file_path, 'wb') as f:
                                for chunk in video_response.iter_content(chunk_size=8192):
                                    if chunk:
                                        f.write(chunk)
                            
                            return {
                                'success': True,
                                'file_path': file_path,
                                'title': data.get('title', 'Loom Video'),
                                'uploader': data.get('owner', {}).get('name', 'Loom User'),
                                'duration': 0,
                                'url': url,
                                'platform': 'loom',
                                'is_video': True,
                                'is_image': False,
                                'temp_dir': temp_dir,
                            }
            
            return {'success': False, 'error': 'Loom download failed'}
            
        except Exception as e:
            logger.error(f"Loom error: {e}")
            return {'success': False, 'error': str(e)}
    
    def download_streamable(self, url, temp_dir):
        """Download from Streamable"""
        try:
            # Extract video ID
            video_id_match = re.search(r'streamable\.com/([a-z0-9]+)', url)
            if video_id_match:
                video_id = video_id_match.group(1)
                
                # Try multiple quality levels
                qualities = ['1080p', '720p', '480p', '360p', '240p']
                
                for quality in qualities:
                    video_url = f"https://cdn-cf-east.streamable.com/video/mp4/{video_id}.mp4?quality={quality}"
                    
                    headers = {
                        'User-Agent': random.choice(config.USER_AGENTS),
                        'Referer': 'https://streamable.com/',
                    }
                    
                    try:
                        response = self.session.head(video_url, headers=headers)
                        if response.status_code == 200:
                            video_response = self.session.get(video_url, headers=headers, stream=True)
                            if video_response.status_code == 200:
                                file_path = os.path.join(temp_dir, f'streamable_{quality}.mp4')
                                with open(file_path, 'wb') as f:
                                    for chunk in video_response.iter_content(chunk_size=8192):
                                        if chunk:
                                            f.write(chunk)
                                
                                return {
                                    'success': True,
                                    'file_path': file_path,
                                    'title': f'Streamable Video ({quality})',
                                    'uploader': 'Streamable',
                                    'duration': 0,
                                    'url': url,
                                    'platform': 'streamable',
                                    'is_video': True,
                                    'is_image': False,
                                    'temp_dir': temp_dir,
                                }
                    except:
                        continue
            
            # Fallback to yt-dlp
            return self.download_with_ytdlp(url, 'streamable', temp_dir)
            
        except Exception as e:
            logger.error(f"Streamable error: {e}")
            return {'success': False, 'error': str(e)}
    
    def download_pinterest(self, url, temp_dir):
        """Download from Pinterest (images and videos)"""
        try:
            result = self.download_with_ytdlp(url, 'pinterest', temp_dir)
            if result['success']:
                return result
            
            # Alternative method for Pinterest
            headers = {
                'User-Agent': random.choice(config.USER_AGENTS),
                'Referer': 'https://www.pinterest.com/',
            }
            
            response = self.session.get(url, headers=headers, timeout=10)
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Look for video
            video_tags = soup.find_all('video')
            for video in video_tags:
                if video.get('src'):
                    video_url = video['src']
                    if not video_url.startswith('http'):
                        video_url = 'https:' + video_url
                    
                    return self.download_media(video_url, temp_dir, 'pinterest_video.mp4', 'Pinterest Video', url)
            
            # Look for image
            img_tags = soup.find_all('img')
            for img in img_tags:
                src = img.get('src') or img.get('data-src') or img.get('data-original')
                if src and any(ext in src.lower() for ext in ['.jpg', '.jpeg', '.png', '.webp', '.gif']):
                    if not src.startswith('http'):
                        src = 'https:' + src
                    
                    # Get highest resolution
                    if 'originals' in src:
                        return self.download_media(src, temp_dir, 'pinterest_image.jpg', 'Pinterest Image', url)
            
            # Try JSON-LD data
            script_tags = soup.find_all('script', type='application/ld+json')
            for script in script_tags:
                try:
                    data = json.loads(script.string)
                    if isinstance(data, dict) and 'image' in data:
                        image_url = data['image']
                        if isinstance(image_url, dict):
                            image_url = image_url.get('url', '')
                        
                        if image_url:
                            return self.download_media(image_url, temp_dir, 'pinterest_image.jpg', 'Pinterest Image', url)
                except:
                    continue
            
            return {'success': False, 'error': 'Pinterest download failed'}
            
        except Exception as e:
            logger.error(f"Pinterest error: {e}")
            return {'success': False, 'error': str(e)}
    
    def download_media(self, media_url, temp_dir, filename, title, original_url):
        """Download media file"""
        try:
            headers = {'User-Agent': random.choice(config.USER_AGENTS)}
            response = self.session.get(media_url, headers=headers, stream=True, timeout=30)
            
            if response.status_code == 200:
                file_path = os.path.join(temp_dir, filename)
                with open(file_path, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                
                is_video = filename.endswith(('.mp4', '.webm', '.mkv', '.avi', '.mov'))
                is_image = filename.endswith(('.jpg', '.jpeg', '.png', '.webp', '.gif'))
                
                return {
                    'success': True,
                    'file_path': file_path,
                    'title': title,
                    'uploader': 'User',
                    'duration': 0,
                    'url': original_url,
                    'platform': 'pinterest' if 'pinterest' in original_url else 'unknown',
                    'is_video': is_video,
                    'is_image': is_image,
                    'temp_dir': temp_dir,
                }
            
            return {'success': False, 'error': f'HTTP {response.status_code}'}
            
        except Exception as e:
            logger.error(f"Media download error: {e}")
            return {'success': False, 'error': str(e)}
    
    def download_video(self, url, platform):
        """Main download method with platform-specific handlers"""
        temp_dir = tempfile.mkdtemp(dir=config.TEMP_PATH)
        logger.info(f"Downloading {platform} from {url}")
        
        try:
            # Platform-specific handlers
            if platform == "terabox":
                result = self.download_terabox(url, temp_dir)
            elif platform == "loom":
                result = self.download_loom(url, temp_dir)
            elif platform == "streamable":
                result = self.download_streamable(url, temp_dir)
            elif platform == "pinterest":
                result = self.download_pinterest(url, temp_dir)
            elif platform == "facebook":
                # Special handling for Facebook
                url = self.fix_facebook_url(url)
                result = self.download_with_ytdlp(url, platform, temp_dir)
                
                # If failed, try alternative methods
                if not result['success']:
                    logger.info("Trying alternative Facebook methods...")
                    # Try with different URL variations
                    variations = [
                        url.replace('m.facebook.com', 'www.facebook.com'),
                        url.replace('/watch/', '/videos/'),
                        url + '&__tn__=%2CO',
                    ]
                    
                    for variation in variations:
                        if variation != url:
                            result = self.download_with_ytdlp(variation, platform, temp_dir)
                            if result['success']:
                                break
            else:
                # Use yt-dlp for other platforms
                result = self.download_with_ytdlp(url, platform, temp_dir)
            
            if result['success']:
                return result
            
            # Cleanup on failure
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {'success': False, 'error': 'Download failed after all attempts'}
            
        except Exception as e:
            logger.error(f"Download error for {platform}: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {'success': False, 'error': str(e)}

# Global downloader instance
downloader = UltimateDownloader()

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        config.MESSAGES['start'],
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
    )

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        config.MESSAGES['help'],
        parse_mode=ParseMode.MARKDOWN
    )

async def about_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        config.MESSAGES['about'],
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
    )

async def supported_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        config.MESSAGES['supported'],
        parse_mode=ParseMode.MARKDOWN,
        disable_web_page_preview=True
    )

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    message = update.message
    text = message.text.strip()
    
    # Extract URL
    urls = re.findall(r'https?://[^\s]+', text)
    
    if not urls:
        await message.reply_text("Please send a valid URL from supported platforms.")
        return
    
    url = urls[0]
    
    # Detect platform
    platform = downloader.detect_platform(url)
    if platform == "unknown":
        await message.reply_text(
            "❌ Unsupported platform.\n\n"
            "Send /supported to see all supported platforms."
        )
        return
    
    # Send status
    status_msg = await message.reply_text(f"🔍 Detected {platform.upper()} link...\n⏳ Processing...")
    
    try:
        await status_msg.edit_text(f"📥 Downloading from {platform}...")
        
        # Download
        result = downloader.download_video(url, platform)
        
        if not result['success']:
            error_msg = result['error']
            
            # Platform-specific suggestions
            suggestions = ""
            if platform == "facebook":
                suggestions = (
                    "\n\n🔧 **Facebook Tips:**\n"
                    "1. Use direct video URLs (not login pages)\n"
                    "2. Try mobile link: m.facebook.com\n"
                    "3. Video must be public\n"
                    "4. Add cookies.txt file for private videos"
                )
            elif platform == "tiktok":
                suggestions = "\n\n🔧 **TikTok Tips:**\n• Get fresh link from TikTok app\n• Some videos are private"
            
            await status_msg.edit_text(f"❌ Download failed: {error_msg}{suggestions}")
            return
        
        # Check file size
        try:
            file_size = os.path.getsize(result['file_path'])
            if file_size > config.MAX_FILE_SIZE:
                await status_msg.edit_text(
                    f"❌ File too large ({file_size/(1024*1024):.1f}MB). "
                    f"Max: {config.MAX_FILE_SIZE/(1024*1024):.0f}MB"
                )
                shutil.rmtree(result['temp_dir'], ignore_errors=True)
                return
        except:
            pass
        
        # Prepare caption
        caption = f"📹 *{result['title']}*\n"
        caption += f"👤 *From:* {result['uploader']}\n"
        caption += f"📱 *Platform:* {platform.title()}\n"
        
        if result['duration'] > 0:
            mins = result['duration'] // 60
            secs = result['duration'] % 60
            caption += f"⏱ *Duration:* {mins}:{secs:02d}\n"
        
        # Send file
        await status_msg.edit_text("📤 Uploading to Telegram...")
        
        with open(result['file_path'], 'rb') as f:
            if result.get('is_video', True):
                await message.reply_video(
                    video=InputFile(f, filename=f"{platform}_video.mp4"),
                    caption=caption,
                    parse_mode=ParseMode.MARKDOWN,
                    duration=result['duration'],
                    supports_streaming=True,
                    read_timeout=180,
                    write_timeout=180
                )
            elif result.get('is_image', False):
                await message.reply_photo(
                    photo=InputFile(f, filename=f"{platform}_image.jpg"),
                    caption=caption,
                    parse_mode=ParseMode.MARKDOWN,
                    read_timeout=180,
                    write_timeout=180
                )
            else:
                await message.reply_document(
                    document=InputFile(f, filename=f"{platform}_file.bin"),
                    caption=caption,
                    parse_mode=ParseMode.MARKDOWN,
                    read_timeout=180,
                    write_timeout=180
                )
        
        await status_msg.edit_text("✅ File sent successfully!")
        
        # Cleanup
        try:
            shutil.rmtree(result['temp_dir'], ignore_errors=True)
        except:
            pass
        
    except Exception as e:
        logger.error(f"Error: {e}")
        try:
            await status_msg.edit_text(f"❌ Error: {str(e)[:100]}")
        except:
            pass

def main():
    if config.BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("\n" + "="*60)
        print("ERROR: Bot token not configured!")
        print("="*60)
        print("1. Get token from @BotFather")
        print("2. Edit config.py")
        print("3. Replace YOUR_BOT_TOKEN_HERE")
        print("="*60)
        sys.exit(1)
    
    print("🤖 ULTIMATE Video Downloader Bot")
    print("✅ Supports: TikTok, Facebook, Instagram")
    print("✅ Added: Terabox, Loom, Streamable")
    print("✅ Added: Snapchat, Pinterest")
    print("✅ Platform-specific optimizations")
    print("")
    
    application = Application.builder() \
        .token(config.BOT_TOKEN) \
        .read_timeout(180) \
        .write_timeout(180) \
        .connect_timeout(180) \
        .build()
    
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("about", about_command))
    application.add_handler(CommandHandler("supported", supported_command))
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND,
        handle_message
    ))
    
    print("🚀 Starting ultimate bot...")
    print("📝 Logs: bot.log")
    print("🛑 Stop with Ctrl+C")
    print("")
    
    try:
        application.run_polling(
            poll_interval=1.0,
            timeout=60,
            drop_pending_updates=True
        )
    except KeyboardInterrupt:
        print("\n👋 Bot stopped")
    except Exception as e:
        print(f"\n💥 Error: {e}")

if __name__ == '__main__':
    main()
EOF

# Create start script
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 ULTIMATE Video Downloader Bot"
echo "================================"

# Check if running
if pgrep -f "python3 bot.py" > /dev/null; then
    echo "⚠️ Bot is already running!"
    exit 1
fi

# Check Python
if ! command -v python3 > /dev/null; then
    echo "❌ Python3 not found!"
    exit 1
fi

# Check venv
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found!"
    exit 1
fi

# Activate venv
source venv/bin/activate

# Check token
if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "❌ Bot token not configured!"
    echo ""
    echo "To fix:"
    echo "1. Get token from @BotFather"
    echo "2. Edit config.py"
    echo "3. Replace YOUR_BOT_TOKEN_HERE"
    echo ""
    exit 1
fi

# Create directories
mkdir -p downloads temp

echo ""
echo "✅ All checks passed"
echo "🚀 Starting ultimate bot..."
echo ""
echo "📋 Supported Platforms:"
echo "• TikTok, Facebook, Instagram"
echo "• Terabox, Loom, Streamable"
echo "• Snapchat, Pinterest"
echo ""
echo "📝 Logs: tail -f bot.log"
echo "🛑 Stop: Ctrl+C"
echo ""

python3 bot.py
EOF

chmod +x start.sh

cat > stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping bot..."
pkill -f "python3 bot.py" 2>/dev/null
sleep 3
echo "✅ Bot stopped"
EOF

chmod +x stop.sh

cat > setup.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🤖 Ultimate Bot Setup"
echo "===================="

if grep -q "YOUR_BOT_TOKEN_HERE" config.py; then
    echo ""
    echo "Enter your bot token from @BotFather:"
    read -p "Token: " TOKEN
    
    if [ -z "$TOKEN" ]; then
        echo "❌ Token cannot be empty"
        exit 1
    fi
    
    sed -i "s/YOUR_BOT_TOKEN_HERE/$TOKEN/g" config.py
    echo "✅ Token saved"
    
    echo ""
    echo "💡 **For better Facebook downloads:**"
    echo "You can add Facebook cookies to 'cookies.txt' file"
    echo "Export cookies from browser and save in this directory"
    echo ""
    
    echo "🎉 Setup complete!"
    echo "Start bot: ./start.sh"
else
    echo "✅ Bot already configured"
    echo "Start bot: ./start.sh"
fi
EOF

chmod +x setup.sh

# Create cookies help file
cat > README_COOKIES.md << 'EOF'
# How to add cookies for better downloads

## For Facebook:
1. Login to Facebook in your browser
2. Install a cookie exporter extension (like "Get cookies.txt" for Chrome)
3. Export cookies for facebook.com
4. Save as `cookies.txt` in bot directory

## For other sites:
Same process - login and export cookies for each site.

Cookies help with:
- Private videos
- Age-restricted content
- Login-required videos
- Better download success rate
EOF

# Make files executable
chmod +x bot.py

success "✅ ULTIMATE bot installed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Configure bot token:"
echo "   cd $BOT_DIR && ./setup.sh"
echo ""
echo "2. Start the bot:"
echo "   ./start.sh"
echo ""
echo "3. For Facebook issues:"
echo "   - Add cookies.txt for better results"
echo "   - Use direct video URLs"
echo "   - Try mobile links (m.facebook.com)"
echo ""
echo "4. New platforms added:"
echo "   • Terabox.com"
echo "   • Loom.com"
echo "   • Streamable.com"
echo "   • Snapchat (Spotlights)"
echo "   • Pinterest (Videos & Images)"
echo ""
success "🎉 Ultimate bot ready with 8+ platforms support!"
