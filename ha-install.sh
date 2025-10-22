#!/bin/bash

# ============================================================================
# Home Assistant на Orange Pi Zero 3 - Установочный скрипт (ИСПРАВЛЕННЫЙ)
# ============================================================================
# Устанавливает Home Assistant Container + Zigbee2MQTT + Mosquitto
# ВНИМАНИЕ: Docker-версия НЕ поддерживает аддоны Home Assistant!
# ============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# ФУНКЦИИ
# ============================================================================

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ============================================================================
# ПРОВЕРКИ
# ============================================================================

print_header "Проверка системы"

# Проверка прав администратора
if [[ $EUID -ne 0 ]]; then
    print_error "Скрипт должен запускаться с sudo"
    echo "Используйте: sudo bash ha-install.sh"
    exit 1
fi

print_success "Права администратора: OK"

# Получаем реального пользователя (не root)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo ~$REAL_USER)

print_info "Пользователь: $REAL_USER"
print_info "Домашняя директория: $REAL_HOME"

# Проверка Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker не установлен"
    echo "Установите Docker: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

print_success "Docker: $(docker --version)"

# Проверка Docker Compose
if ! command -v docker-compose &> /dev/null; then
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose не установлен"
        exit 1
    fi
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

print_success "Docker Compose: OK"

# Добавляем пользователя в группу docker
if ! groups "$REAL_USER" | grep -q docker; then
    print_info "Добавление $REAL_USER в группу docker..."
    usermod -aG docker "$REAL_USER"
    print_success "Пользователь добавлен в группу docker (требуется перелогиниться)"
fi

# Включаем автозапуск Docker
print_info "Настройка автозапуска Docker..."
systemctl enable docker
systemctl start docker
print_success "Docker настроен на автозапуск"

# ============================================================================
# ВАЖНОЕ ПРЕДУПРЕЖДЕНИЕ
# ============================================================================

print_header "ВАЖНАЯ ИНФОРМАЦИЯ"

print_warning "Docker-версия Home Assistant НЕ поддерживает:"
echo "  • Аддоны через Supervisor (File Editor, Terminal, etc)"
echo "  • Простую установку интеграций через UI"
echo ""
echo "Вместо этого вы получите:"
echo "  ✓ Home Assistant Core"
echo "  ✓ Zigbee2MQTT (отдельный контейнер)"
echo "  ✓ Mosquitto MQTT"
echo "  ✓ HACS (кастомные интеграции)"
echo ""
read -p "Продолжить установку? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Установка отменена"
    echo "Для полной версии с аддонами используйте Home Assistant OS:"
    echo "https://github.com/home-assistant/operating-system/releases"
    exit 0
fi

# ============================================================================
# СОЗДАНИЕ ДИРЕКТОРИЙ
# ============================================================================

print_header "Создание директорий"

HA_DIR="$REAL_HOME/homeassistant"

if [ -d "$HA_DIR" ]; then
    print_info "Директория $HA_DIR уже существует"
    read -p "Перезаписать конфигурацию? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Установка отменена"
        exit 0
    fi
    rm -rf "$HA_DIR"
fi

mkdir -p "$HA_DIR"/{mosquitto/{config,data,log},config,zigbee2mqtt/data}

# Устанавливаем правильные права
chown -R "$REAL_USER":"$REAL_USER" "$HA_DIR"

print_success "Директории созданы в $HA_DIR"

# ============================================================================
# СОЗДАНИЕ DOCKER COMPOSE ФАЙЛА
# ============================================================================

print_header "Создание docker-compose.yml"

cat > "$HA_DIR/compose.yml" << 'EOF'
version: '3.8'

services:
  # === MOSQUITTO MQTT BROKER ===
  mosquitto:
    container_name: mosquitto
    image: eclipse-mosquitto:latest
    volumes:
      - ./mosquitto/config:/mosquitto/config
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    networks:
      - ha_network

  # === ZIGBEE2MQTT ===
  zigbee2mqtt:
    container_name: zigbee2mqtt
    image: koenkk/zigbee2mqtt:latest
    volumes:
      - ./zigbee2mqtt/data:/app/data
      - /run/udev:/run/udev:ro
    devices:
      - /dev/ttyUSB0:/dev/ttyUSB0  # Измените на ваш Zigbee адаптер
    restart: unless-stopped
    privileged: true
    environment:
      - TZ=Europe/Moscow
    networks:
      - ha_network
    depends_on:
      - mosquitto

  # === HOME ASSISTANT ===
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
      - /run/dbus:/run/dbus:ro
    restart: unless-stopped
    privileged: true
    network_mode: host
    environment:
      TZ: Europe/Moscow
    depends_on:
      - mosquitto
      - zigbee2mqtt

networks:
  ha_network:
    driver: bridge
EOF

print_success "docker-compose.yml создан"

# ============================================================================
# СОЗДАНИЕ MOSQUITTO КОНФИГА
# ============================================================================

print_header "Настройка Mosquitto"

cat > "$HA_DIR/mosquitto/config/mosquitto.conf" << 'EOF'
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_type all

listener 1883
protocol mqtt

listener 9001
protocol websockets

allow_anonymous false
password_file /mosquitto/config/passwd
EOF

print_success "mosquitto.conf создан"

# ============================================================================
# СОЗДАНИЕ ПАРОЛЯ MOSQUITTO
# ============================================================================

print_header "Создание пароля для Mosquitto"

print_info "Введите пароль для пользователя 'homeassistant':"
read -sp "Пароль: " MQTT_PASSWORD
echo
read -sp "Подтверждение пароля: " MQTT_PASSWORD_CONFIRM
echo

if [ "$MQTT_PASSWORD" != "$MQTT_PASSWORD_CONFIRM" ]; then
    print_error "Пароли не совпадают!"
    exit 1
fi

if [ -z "$MQTT_PASSWORD" ]; then
    print_error "Пароль не может быть пустым!"
    exit 1
fi

# Создание пароля через Docker
docker run --rm -v "$HA_DIR/mosquitto/config:/mosquitto/config" eclipse-mosquitto \
    mosquitto_passwd -b /mosquitto/config/passwd homeassistant "$MQTT_PASSWORD"

print_success "Пароль Mosquitto создан"

# ============================================================================
# СОЗДАНИЕ КОНФИГА ZIGBEE2MQTT
# ============================================================================

print_header "Настройка Zigbee2MQTT"

cat > "$HA_DIR/zigbee2mqtt/data/configuration.yaml" << EOF
homeassistant: true
permit_join: false
mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://mosquitto:1883
  user: homeassistant
  password: $MQTT_PASSWORD
serial:
  port: /dev/ttyUSB0  # Измените на ваш адаптер
advanced:
  log_level: info
  network_key: GENERATE
frontend:
  port: 8080
EOF

print_success "Zigbee2MQTT конфигурация создана"
print_warning "Не забудьте изменить /dev/ttyUSB0 на ваш Zigbee адаптер!"

# ============================================================================
# ОПРЕДЕЛЕНИЕ ZIGBEE АДАПТЕРА
# ============================================================================

print_header "Поиск Zigbee адаптера"

if ls /dev/ttyUSB* 1> /dev/null 2>&1; then
    print_success "Найдены USB устройства:"
    ls -la /dev/ttyUSB* | awk '{print "  " $9}'
    
    USB_DEVICES=($(ls /dev/ttyUSB* 2>/dev/null))
    if [ ${#USB_DEVICES[@]} -eq 1 ]; then
        ZIGBEE_DEVICE="${USB_DEVICES[0]}"
        print_info "Автоматически выбран: $ZIGBEE_DEVICE"
        
        # Обновляем конфиг
        sed -i "s|/dev/ttyUSB0|$ZIGBEE_DEVICE|g" "$HA_DIR/compose.yml"
        sed -i "s|port: /dev/ttyUSB0|port: $ZIGBEE_DEVICE|g" "$HA_DIR/zigbee2mqtt/data/configuration.yaml"
        
        print_success "Конфигурация обновлена для $ZIGBEE_DEVICE"
    else
        print_warning "Найдено несколько USB устройств"
        print_info "Проверьте и отредактируйте конфиг вручную"
    fi
else
    print_warning "USB устройства не найдены"
    print_info "Подключите Zigbee адаптер и отредактируйте:"
    echo "  • $HA_DIR/compose.yml (devices:)"
    echo "  • $HA_DIR/zigbee2mqtt/data/configuration.yaml (serial:port:)"
fi

# ============================================================================
# ПРАВА ДОСТУПА
# ============================================================================

chown -R "$REAL_USER":"$REAL_USER" "$HA_DIR"

# ============================================================================
# ЗАПУСК КОНТЕЙНЕРОВ
# ============================================================================

print_header "Запуск контейнеров Docker"

cd "$HA_DIR"

print_info "Загрузка образов и запуск контейнеров..."
print_info "Первый запуск может занять 5-10 минут..."

$COMPOSE_CMD up -d

# Ожидание запуска
print_info "Ожидание инициализации сервисов..."
sleep 30

# Проверка статуса
$COMPOSE_CMD ps

print_success "Контейнеры запущены"

# ============================================================================
# ПОЛУЧЕНИЕ IP АДРЕСА
# ============================================================================

print_header "Информация о доступе"

IP_ADDR=$(hostname -I | awk '{print $1}')

if [ -z "$IP_ADDR" ]; then
    IP_ADDR="<IP-адрес-устройства>"
fi

echo ""
print_success "🏠 Home Assistant:    http://$IP_ADDR:8123"
print_success "🔌 Zigbee2MQTT UI:    http://$IP_ADDR:8080"
print_success "📡 MQTT Broker:       $IP_ADDR:1883"
echo ""

# ============================================================================
# УСТАНОВКА HACS
# ============================================================================

print_header "Установка HACS"

print_info "Ожидание полной загрузки Home Assistant (60 сек)..."
sleep 60

print_info "Установка HACS..."

# Скачиваем HACS напрямую
docker exec homeassistant bash -c '
cd /config
wget -q -O - https://get.hacs.xyz | bash -
' && print_success "HACS установлен" || print_warning "Установите HACS вручную из UI"

# Перезапуск HA
print_info "Перезапуск Home Assistant..."
docker restart homeassistant
sleep 30

# ============================================================================
# СОЗДАНИЕ SYSTEMD SERVICE (необязательно, но полезно)
# ============================================================================

print_header "Настройка автозапуска через systemd"

cat > /etc/systemd/system/homeassistant.service << EOF
[Unit]
Description=Home Assistant Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$HA_DIR
ExecStart=$COMPOSE_CMD up -d
ExecStop=$COMPOSE_CMD down
User=$REAL_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable homeassistant.service
print_success "Systemd service создан и включен"

# ============================================================================
# ИТОГОВАЯ ИНФОРМАЦИЯ
# ============================================================================

print_header "✅ Установка завершена!"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Веб-интерфейсы"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Home Assistant:  http://$IP_ADDR:8123"
echo "  Zigbee2MQTT:     http://$IP_ADDR:8080"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Учетные данные MQTT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Broker:   mosquitto (или $IP_ADDR)"
echo "  Port:     1883"
echo "  Username: homeassistant"
echo "  Password: $MQTT_PASSWORD"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Первые шаги"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1. Откройте: http://$IP_ADDR:8123"
echo "  2. Создайте учетную запись администратора"
echo "  3. Settings → Devices & Services → Add Integration"
echo "     → MQTT (учетные данные выше)"
echo "  4. HACS появится в Settings → Devices & Services"
echo "  5. Zigbee устройства будут видны после сопряжения"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Полезные команды"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  cd $HA_DIR"
echo ""
echo "  Управление:"
echo "    $COMPOSE_CMD restart              # Перезапуск всех"
echo "    $COMPOSE_CMD restart homeassistant # Только HA"
echo "    $COMPOSE_CMD down                 # Остановить все"
echo "    $COMPOSE_CMD up -d                # Запустить все"
echo ""
echo "  Логи:"
echo "    $COMPOSE_CMD logs -f homeassistant"
echo "    $COMPOSE_CMD logs -f zigbee2mqtt"
echo "    $COMPOSE_CMD logs -f mosquitto"
echo ""
echo "  Статус:"
echo "    $COMPOSE_CMD ps"
echo "    systemctl status homeassistant"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Автозапуск"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Docker запускается автоматически"
echo "  ✓ Контейнеры перезапускаются после сбоев"
echo "  ✓ Systemd service: homeassistant.service"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_warning "ВАЖНО: Для работы Docker без sudo перелогиньтесь!"
print_info "Установка завершена в: $HA_DIR"
echo ""
