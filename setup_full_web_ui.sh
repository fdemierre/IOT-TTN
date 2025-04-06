#!/bin/bash
set -e

echo "Installation de l’interface web UI..."

# === Variables et répertoires ===
WORKDIR="$HOME/IOT-TTN"
APPDIR="$WORKDIR/iot-site"
VENV="$WORKDIR/venv"

# Création des dossiers nécessaires
mkdir -p "$APPDIR/templates"
cd "$WORKDIR"

# === Création de l'environnement virtuel ===
if [ ! -d "$VENV" ]; then
    echo "Création de l’environnement virtuel..."
    python3 -m venv "$VENV"
fi

# Activation de l'environnement virtuel
source "$VENV/bin/activate"

echo "Installation des dépendances..."
pip install --upgrade pip
pip install flask psycopg2-binary requests

# === Création du fichier app.py ===
cat > "$APPDIR/app.py" <<'EOF'
#!/usr/bin/env python3
import os
import json
import re
from flask import Flask, render_template, request, redirect, flash, url_for
import psycopg2
from psycopg2 import sql

app = Flask(__name__)
app.secret_key = "super-secret-key"  # À modifier pour la production

# Chemin vers le fichier contenant le mot de passe PostgreSQL
PASSWORD_FILE = os.path.join(os.environ["HOME"], "IOT-TTN", "iot-site", "pgpass.json")

def get_pg_password():
    try:
        with open(PASSWORD_FILE, "r") as f:
            data = json.load(f)
            return data.get("iot_password")
    except Exception as e:
        app.logger.error("Erreur de lecture du fichier de mot de passe: %s", e)
        return None

def get_db_connection(dbname="devices"):
    password = get_pg_password()
    if not password:
        raise Exception("Mot de passe PostgreSQL introuvable.")
    return psycopg2.connect(dbname=dbname, user="iot", password=password, host="localhost")

# Validation du nom du capteur (uniquement lettres, chiffres, underscore)
def validate_sensor_name(name):
    return re.fullmatch(r"[A-Za-z0-9_]+", name) is not None

# Validation du format dev_eui (16 caractères hexadécimaux)
def validate_dev_eui(dev_eui):
    return re.fullmatch(r"[A-Fa-f0-9]{16}", dev_eui) is not None

def list_sensor_tables():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
        tables = cur.fetchall()
        cur.close()
        conn.close()
        return [t[0] for t in tables if validate_sensor_name(t[0])]
    except Exception as e:
        app.logger.error("Erreur lors de la récupération des tables: %s", e)
        return []

# Route /decoder : Crée un décodeur (table) avec un champ dev_eui et name, et liste ses enregistrements.
@app.route("/decoder", methods=["GET", "POST"])
def decoder():
    if request.method == "POST":
        action = request.form.get("action")
        if action == "create":
            sensor_name = request.form.get("sensor_name", "").strip()
            if not sensor_name:
                flash("❌ Le nom du capteur est requis.")
            elif not validate_sensor_name(sensor_name):
                flash("❌ Nom de capteur invalide. Utilisez uniquement lettres, chiffres et underscore.")
            else:
                try:
                    conn = get_db_connection()
                    cur = conn.cursor()
                    # Création de la table avec les colonnes dev_eui et name
                    create_table_query = sql.SQL(
                        "CREATE TABLE IF NOT EXISTS {table} (id SERIAL PRIMARY KEY, dev_eui VARCHAR(16) UNIQUE, name TEXT)"
                    ).format(table=sql.Identifier(sensor_name))
                    cur.execute(create_table_query)
                    conn.commit()
                    flash("✅ Décodeur créé avec succès.")
                except Exception as e:
                    conn.rollback()
                    flash(f"❌ Erreur lors de la création du décodeur : {e}")
                finally:
                    cur.close()
                    conn.close()
        elif action and action.startswith("delete:"):
            sensor_name = action.split(":", 1)[1]
            if not validate_sensor_name(sensor_name):
                flash("❌ Nom de capteur invalide.")
            else:
                try:
                    conn = get_db_connection()
                    cur = conn.cursor()
                    drop_query = sql.SQL("DROP TABLE IF EXISTS {table}").format(table=sql.Identifier(sensor_name))
                    cur.execute(drop_query)
                    conn.commit()
                    flash(f"🗑️ Décodeur '{sensor_name}' supprimé.")
                except Exception as e:
                    conn.rollback()
                    flash(f"❌ Erreur lors de la suppression du décodeur : {e}")
                finally:
                    cur.close()
                    conn.close()
        return redirect(url_for("decoder"))
    
    sensors = list_sensor_tables()
    sensors_data = []
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        for sensor in sensors:
            query = sql.SQL("SELECT dev_eui, name FROM {table}").format(table=sql.Identifier(sensor))
            cur.execute(query)
            records = cur.fetchall()
            sensors_data.append({"sensor": sensor, "records": records})
        cur.close()
        conn.close()
    except Exception as e:
        flash(f"❌ Erreur lors de la récupération des décodeurs : {e}")
    return render_template("decoder.html", sensors_data=sensors_data)

# Route /sensor : Permet d'ajouter ou de supprimer un enregistrement dans une table de décodeur.
@app.route("/sensor", methods=["GET", "POST"])
def sensor():
    sensors = list_sensor_tables()
    selected_sensor = request.args.get("sensor")
    records = []
    if request.method == "POST":
        action = request.form.get("action")
        selected_sensor = request.form.get("sensor")
        dev_eui = request.form.get("dev_eui", "").strip()
        record_name = request.form.get("name", "").strip()  # nouveau champ "name"
        if not selected_sensor or not validate_sensor_name(selected_sensor):
            flash("❌ Capteur invalide sélectionné.")
        else:
            try:
                conn = get_db_connection()
                cur = conn.cursor()
                if action == "add":
                    if not dev_eui:
                        flash("❌ Le dev_eui est requis pour l'ajout.")
                    elif not validate_dev_eui(dev_eui):
                        flash("❌ dev_eui invalide. Format requis : 16 caractères hexadécimaux.")
                    elif not record_name:
                        flash("❌ Le nom est requis pour l'ajout.")
                    else:
                        insert_query = sql.SQL("INSERT INTO {table} (dev_eui, name) VALUES (%s, %s)").format(table=sql.Identifier(selected_sensor))
                        cur.execute(insert_query, (dev_eui, record_name))
                        conn.commit()
                        flash("✅ Enregistrement ajouté avec succès.")
                elif action == "delete":
                    if not dev_eui:
                        flash("❌ Le dev_eui est requis pour la suppression.")
                    else:
                        delete_query = sql.SQL("DELETE FROM {table} WHERE dev_eui = %s").format(table=sql.Identifier(selected_sensor))
                        cur.execute(delete_query, (dev_eui,))
                        conn.commit()
                        flash("🗑️ Enregistrement supprimé avec succès.")
                cur.close()
                conn.close()
            except Exception as e:
                flash(f"❌ Erreur lors de l'opération sur le capteur : {e}")
        return redirect(url_for("sensor", sensor=selected_sensor))
    
    if selected_sensor and validate_sensor_name(selected_sensor):
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            query = sql.SQL("SELECT dev_eui, name FROM {table}").format(table=sql.Identifier(selected_sensor))
            cur.execute(query)
            records = cur.fetchall()
            cur.close()
            conn.close()
        except Exception as e:
            flash(f"❌ Erreur lors de la récupération des données du capteur : {e}")
    return render_template("sensor.html", sensors=sensors, selected_sensor=selected_sensor, records=records)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

chmod +x "$APPDIR/app.py"

# === Création des templates HTML ===

# Template pour /decoder
cat > "$APPDIR/templates/decoder.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Gestion des Décodeurs</title>
</head>
<body>
  <h1>Gestion des Décodeurs</h1>
  {% with messages = get_flashed_messages() %}
    {% if messages %}
      <ul>
        {% for message in messages %}
          <li>{{ message }}</li>
        {% endfor %}
      </ul>
    {% endif %}
  {% endwith %}
  <h2>Créer un nouveau décodeur</h2>
  <form method="POST">
    <label>Nom du capteur (lettres, chiffres, underscore) :</label>
    <input type="text" name="sensor_name" required>
    <button type="submit" name="action" value="create">Créer</button>
  </form>
  <h2>Décodeurs existants</h2>
  <ul>
    {% for sensor in sensors_data %}
      <li>
        <strong>{{ sensor.sensor }}</strong>
        <ul>
          {% for rec in sensor.records %}
            <li>dev_eui: {{ rec[0] }}, name: {{ rec[1] }}</li>
          {% endfor %}
        </ul>
        <form method="POST" style="display:inline">
          <button type="submit" name="action" value="delete:{{ sensor.sensor }}" onclick="return confirm('Supprimer {{ sensor.sensor }} ?')">Supprimer</button>
        </form>
      </li>
    {% endfor %}
  </ul>
  <a href="{{ url_for('sensor') }}">Accéder à la gestion des sensors</a>
</body>
</html>
EOF

# Template pour /sensor
cat > "$APPDIR/templates/sensor.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Gestion des Sensors</title>
</head>
<body>
  <h1>Gestion des Sensors</h1>
  {% with messages = get_flashed_messages() %}
    {% if messages %}
      <ul>
        {% for message in messages %}
          <li>{{ message }}</li>
        {% endfor %}
      </ul>
    {% endif %}
  {% endwith %}
  <h2>Sélectionner un capteur</h2>
  <form method="GET">
    <select name="sensor" onchange="this.form.submit()">
      <option value="">-- Choisir --</option>
      {% for sensor in sensors %}
        <option value="{{ sensor }}" {% if sensor == selected_sensor %}selected{% endif %}>{{ sensor }}</option>
      {% endfor %}
    </select>
  </form>
  {% if selected_sensor %}
    <h3>Capteur : {{ selected_sensor }}</h3>
    <h4>Ajouter un enregistrement</h4>
    <form method="POST">
      <input type="hidden" name="sensor" value="{{ selected_sensor }}">
      <label>dev_eui (16 caractères HEX) :</label>
      <input type="text" name="dev_eui" maxlength="16" required>
      <label>Nom :</label>
      <input type="text" name="name" required>
      <button type="submit" name="action" value="add">Ajouter</button>
    </form>
    <h4>Liste des enregistrements</h4>
    <ul>
      {% for rec in records %}
        <li>
          dev_eui: {{ rec[0] }}, name: {{ rec[1] }}
          <form method="POST" style="display:inline">
            <input type="hidden" name="sensor" value="{{ selected_sensor }}">
            <input type="hidden" name="dev_eui" value="{{ rec[0] }}">
            <button type="submit" name="action" value="delete" onclick="return confirm('Supprimer cet enregistrement ?')">Supprimer</button>
          </form>
        </li>
      {% endfor %}
    </ul>
  {% endif %}
  <a href="{{ url_for('decoder') }}">Retour à la gestion des décodeurs</a>
</body>
</html>
EOF

# === Création du service systemd ===
SERVICE_FILE="/etc/systemd/system/iot-web.service"
echo "Création du service systemd iot-web..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=IoT Device Manager Web UI
After=network.target postgresql.service

[Service]
User=$USER
WorkingDirectory=$APPDIR
ExecStart=$VENV/bin/python3 $APPDIR/app.py
Restart=always
Environment=FLASK_ENV=production

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable iot-web
sudo systemctl restart iot-web

echo ""
echo "Interface Web installée avec succès !"
echo "Accès via : http://localhost:5000"
echo "Pour vérifier le service : sudo systemctl status iot-web"
