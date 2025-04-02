#!/bin/bash

set -e

echo "🌐 Déploiement complet de l’interface web IoT Device Manager..."

# === Dossiers ===
WORKDIR="$HOME/IOT-TTN"
APPDIR="$WORKDIR/iot-site"
VENV="$WORKDIR/venv"

mkdir -p "$APPDIR/templates"
cd "$WORKDIR"

# === Environnement Python ===
if [ ! -d "$VENV" ]; then
    echo "🐍 Création de l’environnement virtuel..."
    python3 -m venv "$VENV"
fi

source "$VENV/bin/activate"

echo "📦 Installation des dépendances..."
pip install --upgrade pip
pip install flask psycopg2-binary requests

# === config.py ===
cat > "$APPDIR/config.py" <<EOF
DB_HOST = "localhost"
DB_USER = "iot"
DB_DEVICES_DB = "devices"
DB_DATA_DB = "data"
EOF

# === app.py ===
cat > "$APPDIR/app.py" <<'EOF'
from flask import Flask, render_template, request, redirect, flash
import psycopg2
import requests
import re
import config
import json
import os

app = Flask(__name__)
app.secret_key = "super-secret"
pgpass_file = os.path.join(os.path.dirname(__file__), "pgpass.json")

decoder_repo = "https://api.github.com/repos/fdemierre/decoder/contents"

def get_saved_password():
    if os.path.exists(pgpass_file):
        with open(pgpass_file) as f:
            data = json.load(f)
            return data.get("iot_password")
    return None

def save_password(password):
    with open(pgpass_file, "w") as f:
        json.dump({"iot_password": password}, f)

def get_decoders():
    try:
        r = requests.get(decoder_repo)
        return [item["html_url"] for item in r.json() if item["type"] == "file"]
    except:
        return []

def connect(dbname, password):
    return psycopg2.connect(
        dbname=dbname,
        user=config.DB_USER,
        password=password,
        host=config.DB_HOST
    )

@app.route("/", methods=["GET", "POST"])
def index():
    pg_pass = get_saved_password()
    if not pg_pass:
        return redirect("/setup")

    return show_devices(pg_pass)

@app.route("/setup", methods=["GET", "POST"])
def setup():
    if request.method == "POST":
        pg_pass = request.form["pg_password"]
        try:
            # Test de connexion
            conn = connect(config.DB_DEVICES_DB, pg_pass)
            conn.close()
            save_password(pg_pass)
            flash("✅ Mot de passe enregistré.")
            return redirect("/")
        except:
            flash("❌ Mot de passe incorrect.")
    return render_template("setup.html")

def show_devices(pg_pass):
    try:
        conn_devices = connect(config.DB_DEVICES_DB, pg_pass)
        conn_data = connect(config.DB_DATA_DB, pg_pass)
    except:
        return render_template("setup.html", error="❌ Connexion échouée. Supprimez pgpass.json pour réessayer.")

    if request.method == "POST":
        action = request.form["action"]
        if action == "add":
            dev_eui = request.form["dev_eui"].strip()
            name = request.form["name"].strip()
            decoder = request.form["decoder"]

            if not re.fullmatch(r"[A-Fa-f0-9]{16}", dev_eui):
                flash("❌ dev_eui invalide. Format : 16 caractères hex.")
            elif not name:
                flash("❌ Le nom ne peut pas être vide.")
            else:
                try:
                    cur = conn_devices.cursor()
                    cur.execute("INSERT INTO mapping_decoder (dev_eui, name, decoder) VALUES (%s, %s, %s)",
                                (dev_eui, name, decoder))
                    conn_devices.commit()

                    cur_data = conn_data.cursor()
                    cur_data.execute(f"""
                        CREATE TABLE IF NOT EXISTS "{name}" (
                            id SERIAL PRIMARY KEY,
                            timestamp TIMESTAMPTZ DEFAULT NOW(),
                            payload JSONB
                        )
                    """)
                    conn_data.commit()

                    flash("✅ Device ajouté et table créée.")
                except psycopg2.errors.UniqueViolation:
                    flash("❌ Ce nom de device existe déjà.")
                    conn_devices.rollback()
                except Exception as e:
                    flash(f"❌ Erreur : {e}")

        elif action.startswith("delete:"):
            name = action.split(":", 1)[1]
            try:
                cur = conn_devices.cursor()
                cur.execute("DELETE FROM mapping_decoder WHERE name = %s", (name,))
                conn_devices.commit()

                cur_data = conn_data.cursor()
                cur_data.execute(f'DROP TABLE IF EXISTS "{name}"')
                conn_data.commit()
                flash(f"🗑️ Device '{name}' supprimé.")
            except Exception as e:
                flash(f"❌ Erreur suppression : {e}")

    cur = conn_devices.cursor()
    cur.execute("SELECT dev_eui, name, decoder FROM mapping_decoder")
    devices = cur.fetchall()
    conn_devices.close()
    conn_data.close()

    return render_template("index.html", devices=devices, decoders=get_decoders())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

# === setup.html ===
cat > "$APPDIR/templates/setup.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>🔐 Configuration PostgreSQL</title>
</head>
<body>
  <h2>🔑 Saisir le mot de passe du compte PostgreSQL 'iot'</h2>
  {% with messages = get_flashed_messages() %}
    {% if messages %}
      <ul>{% for msg in messages %}<li>{{ msg }}</li>{% endfor %}</ul>
    {% endif %}
  {% endwith %}
  <form method="POST">
    <label>Mot de passe :</label>
    <input type="password" name="pg_password" required>
    <button type="submit">Enregistrer</button>
  </form>
</body>
</html>
EOF

# === index.html ===
cat > "$APPDIR/templates/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>IoT Device Manager</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: auto; }
    input, select { width: 100%; padding: 0.5em; margin: 0.2em 0; }
    .btn { padding: 0.5em 1em; margin-top: 0.5em; }
  </style>
</head>
<body>
  <h1>📡 IoT Device Manager</h1>
  {% with messages = get_flashed_messages() %}
    {% if messages %}
      <ul>{% for msg in messages %}<li>{{ msg }}</li>{% endfor %}</ul>
    {% endif %}
  {% endwith %}

  <form method="POST">
    <label>🔗 Decoder :</label>
    <select name="decoder" required>
      {% for url in decoders %}
        <option value="{{ url }}">{{ url }}</option>
      {% endfor %}
    </select>

    <label>📡 dev_eui (16 caractères HEX) :</label>
    <input name="dev_eui" maxlength="16" required>

    <label>📛 Nom unique du device :</label>
    <input name="name" required>

    <button class="btn" name="action" value="add">➕ Ajouter le device</button>
  </form>

  <h2>📋 Devices enregistrés</h2>
  <ul>
    {% for dev in devices %}
      <li><b>{{ dev[1] }}</b> ({{ dev[0] }}) — <a href="{{ dev[2] }}" target="_blank">Decoder</a>
        <form method="POST" style="display:inline">
          <button class="btn" name="action" value="delete:{{ dev[1] }}" onclick="return confirm('Supprimer {{ dev[1] }} ?')">🗑️</button>
        </form>
      </li>
    {% endfor %}
  </ul>
</body>
</html>
EOF

# === Service systemd ===
SERVICE_FILE="/etc/systemd/system/iot-web.service"
echo "🧩 Création du service systemd iot-web..."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=IoT Device Manager Web UI
After=network.target postgresql.service

[Service]
User=$USER
WorkingDirectory=$APPDIR
ExecStart=$VENV/bin/python3 app.py
Restart=always
Environment=FLASK_ENV=production

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable iot-web
sudo systemctl restart iot-web

echo ""
echo "✅ Interface Web installée avec succès !"
echo "🌍 Accès via : http://localhost:5000"
echo "🛠️  Gérée par systemd : sudo systemctl status iot-web"