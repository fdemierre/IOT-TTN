import paho.mqtt.client as mqtt
from pymongo import MongoClient
import datetime

# === Configuration MQTT ===
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
MQTT_TOPIC = "#"

# === Configuration MongoDB ===
MONGO_URI = "mongodb://localhost:27017"
MONGO_DB = "mqtt_data"
MONGO_COLLECTION = "messages"

# Connexion à MongoDB
mongo_client = MongoClient(MONGO_URI)
db = mongo_client[MONGO_DB]
collection = db[MONGO_COLLECTION]

# Callback lors de la connexion MQTT
def on_connect(client, userdata, flags, rc):
    print("✅ Connecté à Mosquitto avec le code de retour", rc)
    client.subscribe(MQTT_TOPIC)
    print(f"📡 Abonné au topic : {MQTT_TOPIC}")

# Callback à chaque message MQTT reçu
def on_message(client, userdata, msg):
    try:
        payload = msg.payload.decode("utf-8")
        print(f"[{msg.topic}] {payload}")
        collection.insert_one({
            "topic": msg.topic,
            "payload": payload,
            "timestamp": datetime.datetime.utcnow()
        })
        print("✅ Message enregistré dans MongoDB")
    except Exception as e:
        print(f"❌ Erreur MongoDB : {e}")

# Initialisation du client MQTT
mqtt_client = mqtt.Client()
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message

mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
mqtt_client.loop_forever()
