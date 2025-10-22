🎯 Что делает скрипт:
✅ Автоматически устанавливает:

Docker (если не установлен)
Home Assistant (stable версия)
Zigbee2MQTT (с автопоиском адаптера)
Mosquitto MQTT (с безопасным паролем)
HACS (кастомные интеграции)

✅ Оптимизация для Orange Pi Zero 3:

Проверка 2GB RAM
Создание SWAP файла (опционально)
Настройка swappiness для SD карты
Автоопределение USB/ACM Zigbee адаптеров

✅ Автозапуск при старте:

Docker в автозагрузке
Systemd service для контейнеров
restart: unless-stopped в compose

📥 Как использовать:
bash# 1. Скачайте скрипт на Orange Pi
wget https://raw.githubusercontent.com/mutalimov95/ha-installer/refs/heads/main/ha-install.sh
# или скопируйте содержимое в файл

# 2. Дайте права на выполнение
chmod +x ha-orangepi-install.sh

# 3. Запустите с sudo
sudo bash ha-orangepi-install.sh
🔌 Поддерживаемые Zigbee адаптеры:

Sonoff Zigbee 3.0 USB Dongle Plus
ConBee II / RaspBee II
SLZB-06 / CC2652P / CC2531
Любые /dev/ttyUSB* или /dev/ttyACM*

⚡ После установки:

Откройте http://IP-адрес:8123
Создайте аккаунт администратора
Добавьте MQTT интеграцию (данные выведет скрипт)
HACS появится автоматически
Zigbee устройства - через веб-интерфейс http://IP:8080

Всё запустится автоматически при включении Orange Pi! 🚀
