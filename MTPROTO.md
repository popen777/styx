# MTProto Proxy для Telegram
> **⚠️ Контекст сервера:** На сервере уже развёрнуты VLESS + Reality и Hysteria 2, которые занимают порт 443. Все инструкции используют порт **8444** для MTProto прокси. При необходимости замените на любой другой свободный порт.

---

## Сосуществование с XRay / Hysteria 2

Порт 443 занят — на нём работают VLESS+Reality и Hysteria 2. Есть два подхода:

### Подход A: Отдельный порт (рекомендуемый)

MTProto прокси слушает на порте **8444** (или любом другом свободном). Простейший вариант, не требует изменений в существующей конфигурации XRay.

Плюсы: никакого конфликта, независимая работа, простота.
Минусы: порт 8444 может быть заблокирован некоторыми сетями/провайдерами.

### Подход B: Chaining через XRay (продвинутый)

MTProto прокси (mtg) слушает на произвольном порте и маршрутизирует исходящий трафик через SOCKS5-inbound XRay. Таким образом, исходящий трафик прокси идёт через уже существующий туннель.

Для этого нужно добавить SOCKS5 inbound в конфигурацию XRay:

```json
{
  "inbounds": [
    // ... существующие inbounds (VLESS, Hysteria) ...
    {
      "tag": "socks-in-for-mtg",
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth"
      }
    }
  ]
}
```

Затем в конфиге mtg указать chaining (см. раздел «Proxy Chaining» ниже).

Плюсы: весь трафик идёт через XRay-туннель, дополнительная маскировка.
Минусы: дополнительная сложность, зависимость от работоспособности XRay.

---

## Обзор вариантов

Существует несколько реализаций MTProto прокси. Вот три основных:

| Реализация | Язык | Docker-образ | Особенности |
|---|---|---|---|
| **Официальный MTProxy** (TelegramMessenger/MTProxy) | C | `telegrammessenger/proxy` | Поддержка adtag, продвижение каналов. Репозиторий давно не обновляется. |
| **mtg** (9seconds/mtg) | Go | `nineseconds/mtg:2` | Лёгкий, минималистичный. FakeTLS, domain fronting, proxy chaining. Нет adtag в v2. |
| **mtprotoproxy** (alexbers/mtprotoproxy) | Python | `alexbers/mtprotoproxy` | Простой в настройке. Поддержка adtag, множества пользователей, FakeTLS. |

**Рекомендация:** Для личного использования и обхода блокировок РКН лучший вариант — **mtg v2** (лёгкий, FakeTLS из коробки, поддержка chaining через SOCKS5/v2ray). Если нужен adtag для монетизации — **mtprotoproxy** или **официальный образ**.

---

## Вариант 1: mtg v2 (рекомендуемый)

### Требования

- VPS с Linux (Ubuntu 22.04/24.04, Debian 12+)
- Docker и Docker Compose
- Открытый порт 8444 (порт 443 занят VLESS+Reality и Hysteria 2)
- Серверное время синхронизировано (NTP), отклонение от UTC не более 5 секунд

### Шаг 1: Установка Docker

```bash
# Обновляем систему
sudo apt update && sudo apt upgrade -y

# Устанавливаем Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Устанавливаем Docker Compose plugin
sudo apt install docker-compose-plugin -y

# Перелогиниваемся или:
newgrp docker
```

### Шаг 2: Генерация FakeTLS секрета

FakeTLS маскирует трафик прокси под обычный HTTPS. Выберите домен, который НЕ заблокирован в вашем регионе (например, `bing.com`, `google.com`, `cloudflare.com`).

```bash
docker run --rm nineseconds/mtg:2 generate-secret tls -c bing.com
```

Вывод будет примерно таким:
```
ee1234abcd...5678ef0562696e672e636f6d
```

Сохраните этот секрет — он понадобится для запуска и для ссылки подключения.

### Шаг 3: Создание конфигурации

```bash
mkdir -p ~/mtg-proxy && cd ~/mtg-proxy
```

Создайте файл `config.toml`:

```toml
# Секрет, сгенерированный на шаге 2
secret = "ee<ваш_секрет>"

# Адрес и порт для прослушивания
bind-to = "0.0.0.0:3128"
```

### Шаг 4: Docker Compose

Создайте `docker-compose.yml`:

```yaml
services:
  mtg:
    image: nineseconds/mtg:2
    container_name: mtg-proxy
    restart: unless-stopped
    ports:
      - "8444:3128"
    volumes:
      - ./config.toml:/config.toml:ro
    dns:
      - 8.8.8.8
      - 1.1.1.1
```

### Шаг 5: Запуск

```bash
docker compose up -d
```

Проверка:

```bash
docker compose logs -f
docker compose ps
```

### Шаг 6: Настройка файрвола

```bash
# UFW
sudo ufw allow 8444/tcp
sudo ufw enable

# Или iptables
sudo iptables -A INPUT -p tcp --dport 8444 -j ACCEPT
```

### Шаг 7: Ссылка для подключения

Формат ссылки:

```
tg://proxy?server=<IP_СЕРВЕРА>&port=8444&secret=<СЕКРЕТ>
```

Или в формате HTTPS:

```
https://t.me/proxy?server=<IP_СЕРВЕРА>&port=8444&secret=<СЕКРЕТ>
```

Отправьте эту ссылку себе в Telegram — при открытии предложит подключиться к прокси.

---

## Вариант 2: Официальный Docker-образ Telegram

Самый простой способ — одна команда:

```bash
docker run -d \
  -p 8444:443 \
  --name=mtproto-proxy \
  --restart=always \
  -v proxy-config:/data \
  telegrammessenger/proxy:latest
```

После запуска посмотрите логи для получения секрета и ссылки:

```bash
docker logs mtproto-proxy
```

Для добавления рекламного тега (монетизация через @MTProxyBot):

```bash
docker run -d \
  -p 8444:443 \
  --name=mtproto-proxy \
  --restart=always \
  -v proxy-config:/data \
  -e TAG=<ваш_тег_от_MTProxyBot> \
  telegrammessenger/proxy:latest
```

### Docker Compose вариант

```yaml
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    ports:
      - "8444:443"
    environment:
      - SECRET=<32_СИМВОЛА_HEX>   # head -c 16 /dev/urandom | xxd -ps
      # - TAG=<тег_от_MTProxyBot>  # опционально
      # - WORKERS=2                # по умолчанию 2
    volumes:
      - proxy-config:/data
    restart: always

volumes:
  proxy-config:
```

---

## Вариант 3: mtprotoproxy (Python)

Хороший вариант с поддержкой нескольких пользователей и adtag:

```bash
git clone -b stable https://github.com/alexbers/mtprotoproxy.git
cd mtprotoproxy
```

Отредактируйте `config.py`:

```python
PORT = 8444

USERS = {
    "user1": "сгенерированный_секрет_1",
    "user2": "сгенерированный_секрет_2",
}

# Опционально: тег от @MTProxyBot
# AD_TAG = "ваш_тег"
```

Запуск через Docker Compose:

```bash
docker-compose up -d
```

Или напрямую:

```bash
python3 mtprotoproxy.py
```

---

## Продвинутые настройки

### FakeTLS (маскировка под HTTPS)

FakeTLS маскирует MTProto-трафик под обычный TLS/HTTPS. Это критически важно для обхода DPI (Deep Packet Inspection), который используется РКН.

Для **mtg v2** — включён автоматически при генерации секрета с `tls -c <домен>`.

Для **официального MTProxy** — добавьте префикс `ee` к секрету и суффикс — hex-кодирование домена:

```bash
# Генерация: dd-секрет (random padding) + FakeTLS
# dd = random padding
# ee = FakeTLS
echo -n "bing.com" | xxd -ps
# Результат: 62696e672e636f6d
# Итоговый секрет: ee<16_случайных_байт>62696e672e636f6d
```

### Random Padding (защита от анализа размеров пакетов)

Для защиты от DPI по размерам пакетов добавьте префикс `dd` к секрету на стороне клиента:

```
Обычный секрет:   cafe...babe
С padding:        ddcafe...babe
```

### Proxy Chaining (mtg → v2ray/Trojan/Shadowsocks)

mtg поддерживает SOCKS5 upstream — можно маршрутизировать трафик через v2ray или другой туннель:

В `config.toml`:

```toml
secret = "ee<секрет>"
bind-to = "0.0.0.0:3128"

# Chaining через SOCKS5
[proxy]
socks5-address = "127.0.0.1:1080"
# socks5-user = "user"
# socks5-password = "pass"
```

Это особенно полезно если нужно пустить трафик через существующую VLESS/XRay инфраструктуру.

### Мониторинг

**Официальный образ** экспортирует статистику:
```bash
# Доступно только с localhost
curl http://localhost:2398/stats
```

**mtg v2** поддерживает Prometheus endpoint — можно интегрировать с существующим стеком Grafana/Prometheus.

**mtprotoproxy** поддерживает экспорт в Prometheus.

### Регистрация прокси в Telegram

Для получения статистики и возможности продвигать канал:

1. Откройте @MTProxyBot в Telegram
2. Отправьте `/newproxy`
3. Укажите IP и порт сервера
4. Получите тег (tag)
5. Добавьте тег в конфигурацию (переменная `TAG` или параметр `-P`)

---

## Автоматическое обновление конфигурации

Для официального MTProxy конфигурация Telegram-серверов может меняться. Настройте cron для обновления:

```bash
crontab -e
```

Добавьте:

```cron
0 3 * * * curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/proxy-multi.conf && systemctl restart MTProxy
```

Для Docker-вариантов это обычно не требуется — образы обновляют конфиг автоматически.

---

## Траблшутинг

### Клиент зависает на "Connecting..."

- Проверьте, что порт открыт: `sudo netstat -tlnp | grep :8444`
- Проверьте файрвол: `sudo ufw status` или `sudo iptables -L`
- Убедитесь, что Docker контейнер работает: `docker ps`

### Клиент зависает на "Updating..."

- Проверьте, что сервер может подключиться к серверам Telegram
- Убедитесь, что системное время синхронизировано (отклонение < 5 сек от UTC):
  ```bash
  timedatectl status
  sudo timedatectl set-ntp true
  ```
- Проверьте, нет ли DPI/блокировки между сервером и Telegram

### Ошибка PID (Assertion `!(p & 0xffff0000)' failed)

Известная ошибка официального MTProxy при больших PID. Решения:
- Перезагрузить сервер (чтобы PID стали меньше)
- Использовать community fork: `github.com/GetPageSpeed/MTProxy`
- Использовать mtg или mtprotoproxy вместо официального

### Прокси работает медленно

- Увеличьте количество воркеров: `-e WORKERS=4` (для Docker)
- Для mtg — увеличьте буферы чтения/записи в конфигурации
- Проверьте нагрузку на сервер: `htop`, `docker stats`

---

## Быстрый старт (копипаст для Claude Code)

Минимальный набор команд для развёртывания mtg v2:

```bash
# 1. Установка Docker (если нет)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# 2. Создание директории
mkdir -p ~/mtg-proxy && cd ~/mtg-proxy

# 3. Генерация секрета (замените bing.com на нужный домен)
SECRET=$(docker run --rm nineseconds/mtg:2 generate-secret tls -c bing.com)
echo "Секрет: $SECRET"

# 4. Создание конфига
cat > config.toml << EOF
secret = "$SECRET"
bind-to = "0.0.0.0:3128"
EOF

# 5. Создание docker-compose.yml
cat > docker-compose.yml << 'EOF'
services:
  mtg:
    image: nineseconds/mtg:2
    container_name: mtg-proxy
    restart: unless-stopped
    ports:
      - "8444:3128"
    volumes:
      - ./config.toml:/config.toml:ro
    dns:
      - 8.8.8.8
      - 1.1.1.1
EOF

# 6. Запуск
docker compose up -d

# 7. Проверка
docker compose logs

# 8. Получение IP
SERVER_IP=$(curl -s ifconfig.me)
echo ""
echo "=== Ссылка для подключения ==="
echo "tg://proxy?server=${SERVER_IP}&port=8444&secret=${SECRET}"
echo "https://t.me/proxy?server=${SERVER_IP}&port=8444&secret=${SECRET}"

# 9. Файрвол
sudo ufw allow 8444/tcp 2>/dev/null || sudo iptables -A INPUT -p tcp --dport 8444 -j ACCEPT
```

---

## Безопасность

- MTProto прокси **не видит** содержимое сообщений — трафик шифруется Telegram
- Оператор прокси **может видеть** IP-адрес подключающегося и факт использования Telegram
- Делитесь ссылкой только с доверенными людьми
- Используйте FakeTLS для маскировки от DPI
- Регулярно обновляйте Docker-образы
- Не публикуйте прокси публично — это привлечёт DDoS и нежелательных пользователей