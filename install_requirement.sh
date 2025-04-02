#!/bin/bash

set -e

echo "🔄 Mise à jour des paquets..."
sudo apt update && sudo apt upgrade -y

### --- MongoDB (forcé depuis Ubuntu 22.04) ---
echo "📦 Installation de MongoDB (dépôt Ubuntu 22.04)..."
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -

echo "Ajout du dépôt MongoDB pour Jammy (22.04)..."
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list

sudo apt update
sudo apt install -y mongodb-org

echo "Activation et démarrage de MongoDB..."
sudo systemctl enable mongod
sudo systemctl start mongod

### --- PostgreSQL ---
echo "📦 Installation de PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable postgresql
sudo systemctl start postgresql

### --- Mosquitto ---
echo "📦 Installation de Mosquitto MQTT Broker..."
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable mosquitto
sudo systemctl start mosquitto

### --- Grafana ---
echo "📦 Installation de Grafana..."
sudo apt install -y software-properties-common
sudo add-apt-repository -y "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt update
sudo apt install -y grafana

sudo systemctl enable grafana-server
sudo systemctl start grafana-server

### --- Python pour MQTT -> MongoDB ---
echo "🐍 Installation des outils Python..."
sudo apt install -y python3.12-venv python3-full python3-pip

echo ""
echo "✅ Installation terminée avec succès ! Tous les services tournent en local."
