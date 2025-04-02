#!/bin/bash

set -e

echo "🔧 Configuration sécurisée de Mosquitto (Bridge vers TTN ou autre serveur MQTT)"

# Valeurs par défaut
DEFAULT_HOST="eu1.cloud.thethings.network"
DEFAULT_PORT="8883"

# Demande interactive
read -p "👉 MQTT server host [$DEFAULT_HOST]: " MQTT_HOST
MQTT_HOST=${MQTT_HOST:-$DEFAULT_HOST}

read -p "👉 MQTT username (ex: app1@tenant1): " MQTT_USER
read -s -p "👉 MQTT password (sera masqué): " MQTT_PASS
echo ""

# Création du dossier s'il n'existe pas
sudo mkdir -p /etc/mosquitto/conf.d

# Chemin du fichier de config
CONFIG_FILE="/etc/mosquitto/conf.d/secure.conf"

echo "📄 Écriture de la configuration dans $CONFIG_FILE"

sudo tee "$CONFIG_FILE" > /dev/null <<EOF
# === Bridge vers un serveur MQTT distant (ex: TTN) ===

connection bridge-to-cloud
address $MQTT_HOST:$DEFAULT_PORT

# Abonnement à tous les topics
topic # both 0

# Identifiants d'accès
remote_username $MQTT_USER
remote_password $MQTT_PASS

# TLS requis pour le port 8883
bridge_cafile /etc/ssl/certs/ca-certificates.crt
bridge_insecure false

# Options de session
start_type automatic
cleansession true
try_private false
notifications false

# Désactiver les connexions anonymes
allow_anonymous false

# Logs (utile pour débogage)
log_dest syslog
log_type error
log_type warning
log_type notice
log_type information
EOF

# Redémarrage du service
echo "🔁 Redémarrage de Mosquitto..."
sudo systemctl restart mosquitto

echo ""
echo "✅ Configuration terminée ! Mosquitto est maintenant connecté à $MQTT_HOST via TLS"