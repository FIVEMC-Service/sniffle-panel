CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  is_admin BOOLEAN DEFAULT 0
);

CREATE TABLE IF NOT EXISTS domains (
  id INT AUTO_INCREMENT PRIMARY KEY,
  subdomain VARCHAR(255) NOT NULL,
  document_root VARCHAR(255) NOT NULL,
  ssl_enabled BOOLEAN DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Erstelle Admin-User (Passwort wird später gesetzt)
INSERT INTO users (username, password, is_admin) 
VALUES ('admin', '', 1);