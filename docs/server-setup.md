\# Конфигурация виртуальной машины devops-vm



\## 1. Параметры машины



VirtualBox, Ubuntu Server 24.04 LTS, 2048 МБ оперативной памяти,

2 виртуальных процессора, виртуальный диск 25 ГБ.



\## 2. Сетевые интерфейсы



\- `enp0s3` — NAT, адрес `10.0.2.15/24`. Используется для доступа в интернет.

\- `enp0s8` — Host-only, адрес `192.168.56.101/24`. Используется для прямого подключения из Windows.



\## 3. Проброс портов



В настройках первого адаптера VirtualBox создано правило `ssh` по TCP.

Адрес хоста — `127.0.0.1`, порт хоста — `2222`, адрес гостя оставлен пустым.

При первичной настройке порт гостя — `22`. После переноса SSH на новый порт

порт гостя изменён на `2222`.



\## 4. Учётные записи



`student` — учётная запись, созданная при установке Ubuntu.

`devops` — отдельная учётная запись для администрирования по SSH.



```bash

sudo adduser devops

sudo usermod -aG sudo devops

groups devops

```



На Windows создан ключ ED25519 `\~/.ssh/devops\_vm`. Открытый ключ добавлен

в `/home/devops/.ssh/authorized\_keys`. Права на каталог `.ssh` — `700`,

на `authorized\_keys` — `600`. В Windows настроен псевдоним `ssh devops`

для подключения к `devops@127.0.0.1` на порту `2222` с этим ключом.



\## 5. Служба SSH



Настройки сохранены в `/etc/ssh/sshd\_config.d/99-hardening.conf`.



```text

Port 2222

PermitRootLogin no

PasswordAuthentication no

PubkeyAuthentication yes

PermitEmptyPasswords no

MaxAuthTries 3

LoginGraceTime 30

AllowUsers devops

X11Forwarding no

ClientAliveInterval 300

ClientAliveCountMax 2

```



В `50-cloud-init.conf` закомментирована строка `PasswordAuthentication yes`,

поскольку этот файл читается раньше `99-hardening.conf`. Перед применением

конфигурация проверена командой `sudo sshd -t`.



```bash

sudo systemctl disable --now ssh.socket

sudo systemctl enable --now ssh.service

sudo systemctl restart ssh.service

sudo ss -tlnp | grep sshd

```



После запуска службы обновлён порт гостя в правиле проброса VirtualBox.

Проверены вход `devops` по ключу, отказ во входе по паролю и отказ для `root`.



\## 6. Межсетевой экран и локальное имя



```bash

sudo ufw default deny incoming

sudo ufw default allow outgoing

sudo ufw limit 2222/tcp comment 'SSH rate-limited'

sudo ufw allow 80/tcp comment 'HTTP'

sudo ufw allow 443/tcp comment 'HTTPS'

sudo ufw --force enable

sudo ufw logging medium

sudo ufw status verbose

```



Правило для SSH добавлено перед включением UFW. Блокировка порта `8080`

подтверждена записью `\[UFW BLOCK]` в журнале ядра.



В файл `hosts` на Windows добавлена запись `192.168.56.101 devops.local`.

Имя Ubuntu задано командой `sudo hostnamectl set-hostname devops-vm`.

В `/etc/hosts` Ubuntu добавлено соответствие

`127.0.1.1 devops-vm.devops.local devops-vm`.

Команда `hostname -f` возвращает `devops-vm.devops.local`.



\## 7. Снимки состояния



\- `01-clean-install` — после установки Ubuntu, обновления и проверки сети.

\- `02-keys-configured` — после настройки входа по SSH-ключу.

\- `03-ssh-hardened` — после переноса SSH на порт 2222 и проверки отказов.


## 8. Веб-сервер

Установите nginx и rsync. Создайте каталог `/var/www/devops-site` с владельцем
`devops:devops` и режимом 755. Режим файлов сайта — 644.

Создайте самоподписанный сертификат на 365 дней:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -subj /CN=devops.local -addext subjectAltName=DNS:devops.local \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Владелец обоих файлов — root. Поместите конфигурацию из
`config/devops-site.conf` в `/etc/nginx/sites-available/devops-site`.
Активируйте ресурс символической ссылкой в `sites-enabled`, удалите ссылку
`default` и выполните `sudo nginx -t && sudo systemctl reload nginx`.
Скопируйте открытый сертификат через SSH в `~/devops.crt` на клиенте.
