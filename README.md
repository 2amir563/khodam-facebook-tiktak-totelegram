

```
bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-facebook-tiktak-totelegram/main/install.sh)
```


## دستور نصب یک خطی:

فقط این دستور را در سرور لینوکس خود اجرا کنید:

bash

```
bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-facebook-tiktak-totelegram/main/install.sh)
```

یا اگر می‌خواهید دانلود و اجرا کنید:

bash
cd ~ && wget -O install.sh https://raw.githubusercontent.com/2amir563/khodam-facebook-tiktak-totelegram/main/install.sh && chmod +x install.sh && ./install.sh
پس از نصب:
به دایرکتوری بات بروید:

bash
```
cd ~/telegram-video-bot
```

توکن ربات را تنظیم کنید:

bash
```
./quick_setup.sh
```

بات را اجرا کنید:

bash
```
./start_bot.sh
```

ویژگی‌های این نسخه:
✅ بدون نیاز به باز کردن پورت - از polling استفاده می‌کند
✅ FFmpeg داخلی - نیاز به نصب جداگانه ندارد
✅ تمیزکاری خودکار - فایل‌های موقت حذف می‌شوند
✅ سیستم لاگ کامل - برای عیب‌یابی آسان
✅ آمار لحظه‌ای - با دستور /stats
✅ پشتیبانی چند پلتفرم - فیسبوک، تیک‌تاک، اینستاگرام

بات با روش Polling کار می‌کند و به پورت خاصی نیاز ندارد. فقط اینترنت سرور باید به تلگرام دسترسی داشته باشد.





Start bot:

bash
./start_bot.sh
Or run as service:

bash
sudo cp telegram-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable telegram-bot
sudo systemctl start telegram-bot
Commands
/start - Start bot

/help - Show help

/about - About bot

/stats - Bot statistics (admin)

Logs
Service logs: sudo journalctl -u telegram-bot -f

Bot logs: tail -f bot.log

Updates
To update:

bash
cd ~/telegram-video-bot
git pull
source venv/bin/activate
pip install -r requirements.txt --upgrade
sudo systemctl restart telegram-bot
Notes
Max file size: 2GB

Files auto-delete after sending

Only public videos supported

No port forwarding needed
EOF

print_success "✅ Installation complete!"
print_info ""
print_info "📋 Next steps:"
print_info "1. Go to bot directory:"
print_info " cd $BOT_DIR"
print_info ""
print_info "2. Configure bot token:"
print_info " ./quick_setup.sh"
print_info ""
print_info "3. Start bot:"
print_info " ./start_bot.sh"
print_info ""
print_info "4. (Optional) Setup as service:"
print_info " sudo cp telegram-bot.service /etc/systemd/system/"
print_info " sudo systemctl daemon-reload"
print_info " sudo systemctl enable telegram-bot"
print_info " sudo systemctl start telegram-bot"
print_info ""
print_info "📱 Send a Facebook/TikTok link to your bot on Telegram!"
print_info ""
print_success "🎉 Bot is ready! No port configuration needed!"

