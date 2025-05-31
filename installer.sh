#!/bin/bash
# WebPanel Auto-Installer für Subdomain-basiertes Management
# Version: 2.0

if [ "$(id -u)" != "0" ]; then
  echo "Bitte als root ausführen: sudo $0" 1>&2
  exit 1
fi

# Funktionen
error_exit() {
  echo "[ERROR] $1"
  exit 1
}

install_panel() {
  # Benutzereingaben
  PANEL_SUBDOMAIN=$(ask "Subdomain für das Webpanel" "panel")
  MAIN_DOMAIN=$(ask "Hauptdomain" "ihredomain.de")
  ADMIN_EMAIL=$(ask "Admin-E-Mail" "admin@${MAIN_DOMAIN}")
  
  PANEL_DOMAIN="${PANEL_SUBDOMAIN}.${MAIN_DOMAIN}"
  PANEL_DIR="/var/www/${PANEL_DOMAIN}"
  
  echo ""
  echo "=== Installiere Abhängigkeiten ==="
  apt update -q
  apt install -y -q apache2 mariadb-server php libapache2-mod-php \
    certbot python3-certbot-apache git unzip \
    php-mysql php-curl php-json php-mbstring \
    ufw

  echo ""
  echo "=== Konfiguriere Firewall ==="
  ufw allow 'OpenSSH'
  ufw allow 'Apache Full'
  ufw --force enable

  echo ""
  echo "=== Erstelle Webpanel-Verzeichnis ==="
  mkdir -p "${PANEL_DIR}"
  chown -R www-data:www-data "${PANEL_DIR}"

  echo ""
  echo "=== Installiere Webpanel ==="
  cat > "${PANEL_DIR}/index.php" <<'EOPHP'
<?php
session_start();

// Einfache Authentifizierung
define('ADMIN_USER', 'admin');
define('ADMIN_PASS', '<?= $ADMIN_PASS ?>');

if (isset($_POST['login'])) {
    if ($_POST['username'] === ADMIN_USER && $_POST['password'] === ADMIN_PASS) {
        $_SESSION['loggedin'] = true;
        header('Location: index.php');
        exit;
    } else {
        $error = "Falsche Anmeldedaten!";
    }
}

if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: index.php');
    exit;
}

// Subdomain-Management
if (isset($_POST['add_domain'])) {
    $subdomain = $_POST['subdomain'];
    $domain = $_POST['domain'];
    $full_domain = "{$subdomain}.{$domain}";
    
    // Apache-Konfig erstellen
    $conf = "<VirtualHost *:80>\n";
    $conf .= "    ServerName {$full_domain}\n";
    $conf .= "    DocumentRoot /var/www/{$full_domain}\n";
    $conf .= "    <Directory /var/www/{$full_domain}>\n";
    $conf .= "        Options -Indexes +FollowSymLinks\n";
    $conf .= "        AllowOverride All\n";
    $conf .= "        Require all granted\n";
    $conf .= "    </Directory>\n";
    $conf .= "</VirtualHost>\n";
    
    file_put_contents("/etc/apache2/sites-available/{$full_domain}.conf", $conf);
    
    // Verzeichnis erstellen
    mkdir("/var/www/{$full_domain}", 0755, true);
    file_put_contents("/var/www/{$full_domain}/index.html", "<h1>{$full_domain} ist bereit!</h1>");
    
    // Apache aktivieren
    exec("a2ensite {$full_domain}.conf");
    exec("systemctl reload apache2");
    
    // SSL installieren
    exec("certbot --apache -d {$full_domain} --non-interactive --agree-tos --email <?= ADMIN_EMAIL ?>");
    
    $success = "Subdomain {$full_domain} erfolgreich erstellt!";
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>WebPanel - <?= $PANEL_DOMAIN ?></title>
    <style>
        :root { --primary: #4361ee; --dark: #1d3557; --light: #f1faee; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f0f2f5; }
        header { background: var(--primary); color: white; padding: 1rem; display: flex; justify-content: space-between; }
        .container { max-width: 1200px; margin: 2rem auto; padding: 0 1rem; }
        .card { background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); padding: 1.5rem; margin-bottom: 2rem; }
        .btn { background: var(--primary); color: white; border: none; padding: 0.75rem 1.5rem; border-radius: 4px; cursor: pointer; }
        .form-group { margin-bottom: 1rem; }
        .form-group label { display: block; margin-bottom: 0.5rem; }
        .form-group input { width: 100%; padding: 0.75rem; border: 1px solid #ddd; border-radius: 4px; }
        .error { color: #e63946; margin-bottom: 1rem; }
        .success { color: #2a9d8f; margin-bottom: 1rem; }
    </style>
</head>
<body>
    <?php if (!isset($_SESSION['loggedin'])): ?>
        <div class="container">
            <div class="card">
                <h2>Admin Login</h2>
                <?php if (isset($error)): ?>
                    <p class="error"><?= $error ?></p>
                <?php endif; ?>
                <form method="POST">
                    <div class="form-group">
                        <label>Benutzername</label>
                        <input type="text" name="username" required>
                    </div>
                    <div class="form-group">
                        <label>Passwort</label>
                        <input type="password" name="password" required>
                    </div>
                    <button type="submit" name="login" class="btn">Login</button>
                </form>
            </div>
        </div>
    <?php else: ?>
        <header>
            <h1>WebPanel - <?= $PANEL_DOMAIN ?></h1>
            <a href="?logout" style="color: white;">Logout</a>
        </header>
        
        <div class="container">
            <div class="card">
                <h2>Neue Subdomain erstellen</h2>
                <?php if (isset($success)): ?>
                    <p class="success"><?= $success ?></p>
                <?php endif; ?>
                <form method="POST">
                    <div class="form-group">
                        <label>Subdomain</label>
                        <input type="text" name="subdomain" placeholder="meineseite" required>
                    </div>
                    <div class="form-group">
                        <label>Hauptdomain</label>
                        <input type="text" name="domain" value="<?= $MAIN_DOMAIN ?>" required>
                    </div>
                    <button type="submit" name="add_domain" class="btn">Subdomain erstellen</button>
                </form>
            </div>
            
            <div class="card">
                <h2>Verwaltete Subdomains</h2>
                <ul>
                    <?php
                    $sites = glob('/etc/apache2/sites-available/*.conf');
                    foreach ($sites as $site) {
                        $site_name = basename($site, '.conf');
                        if ($site_name != '000-default' && $site_name != $PANEL_DOMAIN) {
                            echo "<li><a href='https://$site_name' target='_blank'>$site_name</a></li>";
                        }
                    }
                    ?>
                </ul>
            </div>
        </div>
    <?php endif; ?>
</body>
</html>
EOPHP

  echo ""
  echo "=== Konfiguriere Apache für Panel ==="
  cat > "/etc/apache2/sites-available/${PANEL_DOMAIN}.conf" <<EOF
<VirtualHost *:80>
    ServerName ${PANEL_DOMAIN}
    DocumentRoot ${PANEL_DIR}
    
    <Directory ${PANEL_DIR}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/${PANEL_DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${PANEL_DOMAIN}-access.log combined
</VirtualHost>
EOF

  a2ensite "${PANEL_DOMAIN}.conf"
  a2dissite 000-default.conf
  a2enmod rewrite
  systemctl restart apache2

  echo ""
  echo "=== Installiere SSL für Panel ==="
  certbot --apache -d "${PANEL_DOMAIN}" --non-interactive --agree-tos --email "${ADMIN_EMAIL}"

  echo ""
  echo "=== Erstelle Cronjob für SSL-Erneuerung ==="
  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook \"systemctl reload apache2\"") | crontab -

  # Setze Admin-Passwort
  ADMIN_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
  sed -i "s/<\?= \$ADMIN_PASS \?>/${ADMIN_PASS}/" "${PANEL_DIR}/index.php"
  sed -i "s/<\?= ADMIN_EMAIL \?>/${ADMIN_EMAIL}/" "${PANEL_DIR}/index.php"
  sed -i "s/<\?= \$PANEL_DOMAIN \?>/${PANEL_DOMAIN}/" "${PANEL_DIR}/index.php"
  sed -i "s/<\?= \$MAIN_DOMAIN \?>/${MAIN_DOMAIN}/" "${PANEL_DIR}/index.php"

  echo ""
  echo "=== Installation abgeschlossen! ==="
  echo "WebPanel URL: https://${PANEL_DOMAIN}"
  echo "Admin Benutzername: admin"
  echo "Admin Passwort: ${ADMIN_PASS}"
}

ask() {
  read -p "$1 [${2}]: " reply
  echo "${reply:-$2}"
}

# Hauptinstallation
clear
echo "===== WebPanel Installer v2.0 ====="
install_panel
