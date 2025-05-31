#!/bin/bash
# Auto-Installer für Web-Panel mit Subdomain/SSL-Verwaltung
# Version: 2.0

# Als root ausführen
if [ "$(id -u)" != "0" ]; then
  echo "Bitte als root ausführen: sudo $0" 1>&2
  exit 1
fi

# Funktionen
error_exit() {
  echo "[ERROR] $1"
  exit 1
}

ask() {
  local prompt default reply
  prompt=$1
  default=$2
  
  if [ "${default}" != "" ]; then
    prompt="${prompt} [${default}]: "
  else
    prompt="${prompt}: "
  fi

  while true; do
    read -p "${prompt}" reply
    if [ -z "${reply}" ] && [ -n "${default}" ]; then
      reply="${default}"
      break
    elif [ -n "${reply}" ]; then
      break
    fi
  done

  echo "${reply}"
}

generate_password() {
  tr -dc 'A-Za-z0-9!@#$%^&*()_+=' </dev/urandom | head -c 24
}

# Hauptinstallation
clear
echo "===== Web-Panel Auto-Installer v2.0 ====="
echo "Dieses Skript installiert ein komplettes Web-Panel mit:"
echo "- Subdomain-Verwaltung"
echo "- Automatischer SSL-Zertifikate"
echo "- PHP-basiertem Admin-Panel"
echo "- Update-Funktionalität"
echo ""

# Benutzereingaben
HAUPTDOMAIN=$(ask "Hauptdomain eingeben (z.B. deine-domain.de)")
ADMIN_EMAIL=$(ask "Admin-Email für SSL-Zertifikate" "admin@${HAUPTDOMAIN}")
DB_PASS=$(ask "Datenbank-Passwort generieren? (leer lassen zum generieren)" "$(generate_password)")
ADMIN_PASS=$(ask "Admin-Panel Passwort" "$(generate_password)")

# Konfiguration
PANEL_DIR="/var/www/panel"
APACHE_CONF="/etc/apache2/sites-available/panel.conf"
MYSQL_ROOT_PASS=$(generate_password)

# Installationsschritte
echo ""
echo "=== Installiere Abhängigkeiten ==="
apt update -q
apt upgrade -y -q
apt install -y -q \
  apache2 mariadb-server php libapache2-mod-php \
  certbot python3-certbot-apache git unzip \
  php-mysql php-curl php-json php-mbstring php-zip \
  ufw

echo ""
echo "=== Konfiguriere Firewall ==="
ufw allow 'OpenSSH'
ufw allow 'Apache Full'
ufw --force enable

echo ""
echo "=== Konfiguriere MariaDB ==="
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DELETE FROM mysql.user WHERE User='';"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DROP DATABASE IF EXISTS test;"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "CREATE DATABASE webpanel;"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "CREATE USER 'paneladmin'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "GRANT ALL PRIVILEGES ON webpanel.* TO 'paneladmin'@'localhost';"
mysql -uroot -p${MYSQL_ROOT_PASS} -e "FLUSH PRIVILEGES;"

echo ""
echo "=== Installiere Web-Panel ==="
mkdir -p ${PANEL_DIR}
cat > ${PANEL_DIR}/index.php <<'EOPHP'
<?php
// Web-Panel Hauptdatei
session_start();

// Konfiguration
require_once 'config.php';

// Datenbankverbindung
$db = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
if ($db->connect_error) {
    die("Datenbankverbindung fehlgeschlagen: " . $db->connect_error);
}

// Login-Überprüfung
function require_login() {
    if (!isset($_SESSION['loggedin']) || $_SESSION['loggedin'] !== true) {
        header('Location: login.php');
        exit;
    }
}

// Hauptseite
if (basename($_SERVER['SCRIPT_NAME']) == 'index.php') {
    require_login();
    include 'dashboard.php';
}
EOPHP

# Konfigurationsdatei erstellen
cat > ${PANEL_DIR}/config.php <<EOPHP
<?php
// Automatisch generierte Konfiguration
define('DB_HOST', 'localhost');
define('DB_NAME', 'webpanel');
define('DB_USER', 'paneladmin');
define('DB_PASSWORD', '${DB_PASS}');
define('BASE_DOMAIN', '${HAUPTDOMAIN}');
define('APACHE_SITES_DIR', '/etc/apache2/sites-available');
define('WEB_ROOT', '/var/www');
define('ADMIN_EMAIL', '${ADMIN_EMAIL}');
define('VERSION', '2.0');
EOPHP

# Login-Datei
cat > ${PANEL_DIR}/login.php <<'EOPHP'
<?php
session_start();

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $username = $_POST['username'];
    $password = $_POST['password'];
    
    // Einfacher Login (Admin/Passwort aus Installer)
    if ($username == 'admin' && $password == '${ADMIN_PASS}') {
        $_SESSION['loggedin'] = true;
        header('Location: index.php');
        exit;
    } else {
        $error = "Falsche Anmeldedaten!";
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Panel Login</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f0f2f5; }
        .login-box { width: 300px; margin: 100px auto; padding: 20px; background: white; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        input { width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 3px; }
        button { background: #4CAF50; color: white; border: none; padding: 10px; width: 100%; cursor: pointer; }
        .error { color: red; }
    </style>
</head>
<body>
    <div class="login-box">
        <h2>Admin Login</h2>
        <?php if (isset($error)): ?>
            <p class="error"><?= $error ?></p>
        <?php endif; ?>
        <form method="POST">
            <input type="text" name="username" placeholder="Benutzername" required>
            <input type="password" name="password" placeholder="Passwort" required>
            <button type="submit">Login</button>
        </form>
    </div>
</body>
</html>
EOPHP

# Dashboard-Datei
cat > ${PANEL_DIR}/dashboard.php <<'EOPHP'
<?php include 'header.php'; ?>

<div class="container">
    <h1>Web-Panel Dashboard</h1>
    
    <div class="card">
        <h2>Systemübersicht</h2>
        <p>Hauptdomain: <?= BASE_DOMAIN ?></p>
        <p>Version: <?= VERSION ?></p>
    </div>
    
    <div class="card">
        <h2>Subdomain-Verwaltung</h2>
        <form action="add_domain.php" method="POST">
            <input type="text" name="subdomain" placeholder="meine-subdomain" required>
            <button type="submit">Subdomain erstellen</button>
        </form>
        
        <h3>Existierende Subdomains:</h3>
        <ul>
            <?php
            $result = $db->query("SELECT * FROM domains");
            while ($row = $result->fetch_assoc()):
            ?>
            <li>
                <a href="http://<?= $row['subdomain'] ?>" target="_blank">
                    <?= $row['subdomain'] ?>
                </a>
                <a href="delete_domain.php?id=<?= $row['id'] ?>" class="delete">Löschen</a>
            </li>
            <?php endwhile; ?>
        </ul>
    </div>
    
    <div class="card">
        <h2>Systemaktualisierung</h2>
        <form action="update.php" method="POST">
            <button type="submit">Panel aktualisieren</button>
        </form>
    </div>
</div>

<?php include 'footer.php'; ?>
EOPHP

# Header-Datei
cat > ${PANEL_DIR}/header.php <<'EOPHP'
<!DOCTYPE html>
<html>
<head>
    <title>Web-Panel</title>
    <style>
        :root { --primary: #4361ee; --secondary: #3f37c9; --dark: #000814; --light: #f8f9fa; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f0f2f5; }
        header { background: var(--primary); color: white; padding: 1rem; display: flex; justify-content: space-between; }
        .container { max-width: 1200px; margin: 2rem auto; padding: 0 1rem; }
        .card { background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); padding: 1.5rem; margin-bottom: 2rem; }
        button, input[type="submit"] { background: var(--primary); color: white; border: none; padding: 0.75rem 1.5rem; border-radius: 4px; cursor: pointer; font-size: 1rem; }
        button:hover, input[type="submit"]:hover { background: var(--secondary); }
        input[type="text"] { padding: 0.75rem; border: 1px solid #ddd; border-radius: 4px; width: 100%; margin-bottom: 1rem; }
        ul { list-style: none; }
        li { padding: 0.5rem 0; border-bottom: 1px solid #eee; }
        .delete { color: red; margin-left: 1rem; }
    </style>
</head>
<body>
<header>
    <h1>Web-Panel</h1>
    <a href="logout.php" style="color: white;">Logout</a>
</header>
EOPHP

# Footer-Datei
cat > ${PANEL_DIR}/footer.php <<'EOPHP'
</body>
</html>
EOPHP

# Domain-Management-Dateien
cat > ${PANEL_DIR}/add_domain.php <<'EOPHP'
<?php
require 'config.php';
require_login();

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $subdomain = trim($_POST['subdomain']).'.'.BASE_DOMAIN;
    $docroot = WEB_ROOT.'/'.trim($_POST['subdomain']);
    
    // Apache-Konfig erstellen
    $conf = "<VirtualHost *:80>\n";
    $conf .= "    ServerName $subdomain\n";
    $conf .= "    DocumentRoot $docroot\n";
    $conf .= "    <Directory $docroot>\n";
    $conf .= "        Options -Indexes +FollowSymLinks\n";
    $conf .= "        AllowOverride All\n";
    $conf .= "        Require all granted\n";
    $conf .= "    </Directory>\n";
    $conf .= "    ErrorLog \${APACHE_LOG_DIR}/$subdomain-error.log\n";
    $conf .= "    CustomLog \${APACHE_LOG_DIR}/$subdomain-access.log combined\n";
    $conf .= "</VirtualHost>\n";
    
    file_put_contents(APACHE_SITES_DIR."/$subdomain.conf", $conf);
    
    // Verzeichnis erstellen
    mkdir($docroot, 0755, true);
    file_put_contents("$docroot/index.html", "<h1>$subdomain ist bereit!</h1>");
    
    // Apache aktivieren
    exec("a2ensite $subdomain.conf");
    exec("systemctl reload apache2");
    
    // SSL hinzufügen
    exec("certbot --apache -d $subdomain --non-interactive --agree-tos --email ".ADMIN_EMAIL);
    
    // In DB speichern
    $stmt = $db->prepare("INSERT INTO domains (subdomain, document_root) VALUES (?, ?)");
    $stmt->bind_param("ss", $subdomain, $docroot);
    $stmt->execute();
    
    header('Location: index.php');
    exit;
}
?>
EOPHP

cat > ${PANEL_DIR}/delete_domain.php <<'EOPHP'
<?php
require 'config.php';
require_login();

if (isset($_GET['id'])) {
    $id = intval($_GET['id']);
    
    // Domain-Daten abrufen
    $result = $db->query("SELECT * FROM domains WHERE id = $id");
    $domain = $result->fetch_assoc();
    
    if ($domain) {
        // Apache-Konfiguration entfernen
        $conf_file = APACHE_SITES_DIR."/".$domain['subdomain'].".conf";
        if (file_exists($conf_file)) {
            exec("a2dissite ".basename($conf_file));
            unlink($conf_file);
        }
        
        // Verzeichnis löschen
        exec("rm -rf ".escapeshellarg($domain['document_root']));
        
        // Aus DB löschen
        $db->query("DELETE FROM domains WHERE id = $id");
        
        // Apache neu laden
        exec("systemctl reload apache2");
    }
    
    header('Location: index.php');
    exit;
}
?>
EOPHP

# Update-Skript
cat > ${PANEL_DIR}/update.php <<'EOPHP'
<?php
require 'config.php';
require_login();

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    // Aktualisiere Panel-Code
    exec("cd ".escapeshellarg(PANEL_DIR)." && git pull 2>&1", $output);
    
    // Datenbank-Updates
    $db->query("ALTER TABLE domains ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP");
    
    echo "<h2>Update durchgeführt</h2>";
    echo "<pre>".implode("\n", $output)."</pre>";
    echo "<a href='index.php'>Zurück zum Panel</a>";
    exit;
}
?>
EOPHP

# Logout-Skript
cat > ${PANEL_DIR}/logout.php <<'EOPHP'
<?php
session_start();
session_destroy();
header('Location: login.php');
exit;
?>
EOPHP

# Datenbank-Schema
mysql -uroot -p${MYSQL_ROOT_PASS} webpanel <<EOSQL
CREATE TABLE IF NOT EXISTS domains (
  id INT AUTO_INCREMENT PRIMARY KEY,
  subdomain VARCHAR(255) NOT NULL,
  document_root VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS settings (
  name VARCHAR(50) PRIMARY KEY,
  value VARCHAR(255) NOT NULL
);

INSERT INTO settings (name, value) VALUES ('version', '2.0');
EOSQL

# Apache-Konfiguration
cat > ${APACHE_CONF} <<EOF
<VirtualHost *:80>
    ServerName panel.${HAUPTDOMAIN}
    DocumentRoot ${PANEL_DIR}

    <Directory ${PANEL_DIR}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/panel-error.log
    CustomLog \${APACHE_LOG_DIR}/panel-access.log combined
</VirtualHost>
EOF

# Berechtigungen setzen
chown -R www-data:www-data ${PANEL_DIR}
chmod -R 755 ${PANEL_DIR}

# Apache aktivieren
a2ensite panel.conf
a2enmod rewrite
systemctl restart apache2

# SSL einrichten
certbot --apache -d panel.${HAUPTDOMAIN} --non-interactive --agree-tos --email ${ADMIN_EMAIL}

# Cronjob für SSL-Erneuerung
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook \"systemctl reload apache2\"") | crontab -

# Installation abschließen
clear
echo "===== Installation abgeschlossen! ====="
echo "Zugriff auf das Panel: https://panel.${HAUPTDOMAIN}"
echo "Admin-Benutzername: admin"
echo "Admin-Passwort: ${ADMIN_PASS}"
echo ""
echo "Wichtige Informationen:"
echo " - MySQL Root Passwort: ${MYSQL_ROOT_PASS}"
echo " - Panel DB Passwort: ${DB_PASS}"
echo ""
echo "Bewahren Sie diese Informationen sicher auf!"
