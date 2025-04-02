#!/bin/bash

WORKDIR="$HOME/IOT-TTN"
LOGFILE="$WORKDIR/mqtt.log"
SCRIPT="mqtt_to_mongo.py"

echo "📡 Vérification de l'état du système MQTT → MongoDB"
echo "────────────────────────────────────────────────────"

# 1. Processus en cours
echo "🔍 Processus en cours :"
pgrep -af "$SCRIPT" || echo "❌ Le script $SCRIPT n'est pas en cours d'exécution."

# 2. MongoDB status
echo ""
echo "🧩 État de MongoDB :"
if systemctl is-active --quiet mongod; then
    echo "✅ MongoDB est actif"
else
    echo "❌ MongoDB n'est pas actif"
fi

# 3. Contenu de la base MongoDB
echo ""
echo "📦 Contenu de la base 'mqtt_data.messages' :"

source "$WORKDIR/venv/bin/activate"
python3 - <<EOF
from pymongo import MongoClient
from pprint import pprint

try:
    client = MongoClient("mongodb://localhost:27017")
    db = client["mqtt_data"]
    collection = db["messages"]

    count = collection.count_documents({})
    print(f"🔢 Nombre de messages : {count}")

    if count > 0:
        print("📝 Derniers messages :")
        cursor = collection.find().sort("timestamp", -1).limit(5)
        for doc in cursor:
            print(f"- [{doc.get('timestamp')}] {doc.get('topic')}")
    else:
        print("⚠️ Aucun message trouvé.")
except Exception as e:
    print(f"❌ Erreur de connexion à MongoDB : {e}")
EOF
deactivate

# 4. Dernières lignes du log
echo ""
echo "📄 Dernières lignes du log ($LOGFILE) :"
tail -n 10 "$LOGFILE" 2>/dev/null || echo "⚠️ Aucun fichier de log trouvé."

echo ""
echo "✅ Vérification terminée."