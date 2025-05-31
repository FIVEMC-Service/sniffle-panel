#!/bin/bash
# Auto-Installer für Web-Panel mit Subdomain/SSL-Verwaltung
# (c) 2023 WebPanel-Script

# Als root ausführen
if [ "$(id -u)" != "0" ]; then
  echo "Bitte als root ausführen: sudo $0" 1>&2
  exit 1
fi

# Konfiguration
PANEL_DIR="/var/www/panel"
DB_NAME="webpanel"
DB_USER="paneladmin"
MYSQL_CONF="/etc/mysql/my.cnf"
APACHE_CONF="/etc/apache2/sites-available/panel.conf"

# Funktionen
error_exit() {
  echo "[Fehler] $1"
  exit 1
}

install_dependencies() {
  echo "Installiere Abhängigkeiten..."
  apt update > /dev/null 2>&1 || error_exit "Systemupdate fehlgeschlagen"
  apt install -y apache2 mariadb-server php libapache2-mod-php \
    certbot python3-certbot-apache git unzip \
    php-mysql php-curl php-json php-mbstring php-zip \
    ufw || error_exit "Paketinstallation fehlgeschlagen"
}

configure_firewall() {
  echo "Konfiguriere Firewall..."
  ufw allow 'OpenSSH' > /dev/null
  ufw allow 'Apache Full' > /dev/null
  ufw --force enable > /dev/null
}

setup_database() {
  echo "Richte Datenbank ein..."
  local DB_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
  mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
  mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
  mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"
  
  # Passwort in Konfiguration speichern
  sed -i "s/DB_PASSWORD', '.*'/DB_PASSWORD', '${DB_PASS}'/" ${PANEL_DIR}/src/config.php
  echo "Datenbank-Passwort: ${DB_PASS} (wurde in Konfig gespeichert)"
}

install_panel() {
  echo "Installiere Web-Panel..."
  git clone https://github.com/FIVEMC-Service/sniffle-panel.git ${PANEL_DIR} > /dev/null 2>&1 || error_exit "Git-Klon fehlgeschlagen"
  chown -R www-data:www-data ${PANEL_DIR}
  chmod -R 755 ${PANEL_DIR}/storage

  # Apache-Konfiguration
  cat > ${APACHE_CONF} <<EOF
<VirtualHost *:80>
    ServerName panel.${HAUPTDOMAIN}
    DocumentRoot ${PANEL_DIR}/public

    <Directory ${PANEL_DIR}/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/panel-error.log
    CustomLog \${APACHE_LOG_DIR}/panel-access.log combined
</VirtualHost>
EOF

  a2ensite panel.conf > /dev/null
  a2enmod rewrite > /dev/null
  systemctl restart apache2 > /dev/null || error_exit "Apache-Neustart fehlgeschlagen"
}

setup_ssl() {
  echo "Richte SSL für Panel ein..."
  certbot --apache -d panel.${HAUPTDOMAIN} --non-interactive --agree-tos --email admin@${HAUPTDOMAIN} > /dev/null 2>&1
  
  # Cronjob für SSL-Erneuerung
  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook \"systemctl reload apache2\"") | crontab -
}

create_configs() {
  # Hauptkonfiguration anlegen
  cat > ${PANEL_DIR}/src/config.php <<EOF
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', '${DB_NAME}');
define('DB_USER', '${DB_USER}');
define('DB_PASSWORD', 'temp_password');
define('BASE_DOMAIN', '${HAUPTDOMAIN}');
define('APACHE_SITES_DIR', '/etc/apache2/sites-available');
define('WEB_ROOT', '/var/www');
?>
EOF

  # Apache-Template für Subdomains
  cat > ${PANEL_DIR}/config/apache-template.conf <<EOF
<VirtualHost *:80>
    ServerName {SUBDOMAIN}
    DocumentRoot {DOCROOT}
    
    <Directory {DOCROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/{SUBDOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/{SUBDOMAIN}-access.log combined
</VirtualHost>
EOF
}

finalize() {
  # Datenbank-Schema importieren
  mysql ${DB_NAME} < ${PANEL_DIR}/database/schema.sql || error_exit "Datenbank-Import fehlgeschlagen"
  
  echo "Installation abgeschlossen!"
  echo "==================================================="
  echo "Zugriff auf das Panel: https://panel.${HAUPTDOMAIN}"
  echo "Initial-Login: admin / changeme"
  echo "==================================================="
}

# Hauptinstallation
clear
echo "===== Web-Panel Auto-Installer ====="

# Benutzereingaben
read -p "Hauptdomain eingeben (z.B. meine-domain.de): " HAUPTDOMAIN

install_dependencies
configure_firewall
install_panel
create_configs
setup_database
setup_ssl
finalize