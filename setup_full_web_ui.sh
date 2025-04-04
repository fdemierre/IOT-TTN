#!/usr/bin/env python3
import os
import json
import re
from flask import Flask, render_template, request, redirect, flash, url_for
import psycopg2
from psycopg2 import sql

app = Flask(__name__)
app.secret_key = "super-secret-key"  # Changez cette valeur en production

# Chemin vers le fichier de mot de passe
PASSWORD_FILE = os.path.join(os.environ["HOME"], "IOT-TTN", "iot-site", "pgpass.json")

def get_pg_password():
    try:
        with open(PASSWORD_FILE, "r") as f:
            data = json.load(f)
            return data.get("iot_password")
    except Exception as e:
        app.logger.error(f"Erreur de lecture du fichier de mot de passe : {e}")
        return None

def get_db_connection(dbname="devices"):
    password = get_pg_password()
    if not password:
        raise Exception("Mot de passe PostgreSQL introuvable.")
    return psycopg2.connect(dbname=dbname, user="iot", password=password, host="localhost")

# Fonctions de validation
def validate_sensor_name(name):
    # Autorise uniquement lettres, chiffres et underscore (pas d'espaces ni caractères spéciaux)
    return re.fullmatch(r"[A-Za-z0-9_]+", name) is not None

def validate_dev_eui(dev_eui):
    # Vérifie que le dev_eui est composé de 16 caractères hexadécimaux
    return re.fullmatch(r"[A-Fa-f0-9]{16}", dev_eui) is not None

def list_sensor_tables():
    """Liste les tables (décodeurs) présentes dans le schéma public de la base devices."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
        tables = cur.fetchall()
        cur.close()
        conn.close()
        # Filtre les noms correspondant à un nom de capteur valide
        return [t[0] for t in tables if validate_sensor_name(t[0])]
    except Exception as e:
        app.logger.error(f"Erreur lors de la récupération des tables : {e}")
        return []

@app.route("/decoder", methods=["GET", "POST"])
def decoder():
    if request.method == "POST":
        action = request.form.get("action")
        if action == "create":
            sensor_name = request.form.get("sensor_name", "").strip()
            dev_eui = request.form.get("dev_eui", "").strip()

            if not sensor_name:
                flash("❌ Le nom du capteur est requis.")
            elif not validate_sensor_name(sensor_name):
                flash("❌ Nom de capteur invalide. Utilisez uniquement des lettres, chiffres et underscore.")
            elif not dev_eui:
                flash("❌ Le dev_eui est requis.")
            elif not validate_dev_eui(dev_eui):
                flash("❌ dev_eui invalide. Format requis : 16 caractères hexadécimaux.")
            else:
                try:
                    conn = get_db_connection()
                    cur = conn.cursor()
                    # Création de la table pour le nouveau décodeur
                    create_table_query = sql.SQL(
                        "CREATE TABLE IF NOT EXISTS {table} (id SERIAL PRIMARY KEY, dev_eui VARCHAR(16) NOT NULL UNIQUE)"
                    ).format(table=sql.Identifier(sensor_name))
                    cur.execute(create_table_query)
                    # Insertion de l'enregistrement initial
                    insert_query = sql.SQL(
                        "INSERT INTO {table} (dev_eui) VALUES (%s)"
                    ).format(table=sql.Identifier(sensor_name))
                    cur.execute(insert_query, (dev_eui,))
                    conn.commit()
                    flash("✅ Décodeur créé avec succès.")
                except psycopg2.errors.UniqueViolation:
                    conn.rollback()
                    flash("❌ Ce dev_eui existe déjà dans ce décodeur.")
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
    
    # Méthode GET : récupération et affichage des décodeurs existants et de leurs dev_eui
    sensors = list_sensor_tables()
    sensors_data = []
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        for sensor in sensors:
            query = sql.SQL("SELECT dev_eui FROM {table}").format(table=sql.Identifier(sensor))
            cur.execute(query)
            dev_euis = [row[0] for row in cur.fetchall()]
            sensors_data.append({"sensor": sensor, "dev_euis": dev_euis})
        cur.close()
        conn.close()
    except Exception as e:
        flash(f"❌ Erreur lors de la récupération des décodeurs : {e}")
    return render_template("decoder.html", sensors_data=sensors_data)

@app.route("/sensor", methods=["GET", "POST"])
def sensor():
    sensors = list_sensor_tables()
    selected_sensor = request.args.get("sensor")
    dev_euis = []

    if request.method == "POST":
        action = request.form.get("action")
        selected_sensor = request.form.get("sensor")
        dev_eui = request.form.get("dev_eui", "").strip()

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
                    else:
                        insert_query = sql.SQL("INSERT INTO {table} (dev_eui) VALUES (%s)").format(table=sql.Identifier(selected_sensor))
                        cur.execute(insert_query, (dev_eui,))
                        conn.commit()
                        flash("✅ dev_eui ajouté avec succès.")
                elif action == "delete":
                    if not dev_eui:
                        flash("❌ Le dev_eui est requis pour la suppression.")
                    else:
                        delete_query = sql.SQL("DELETE FROM {table} WHERE dev_eui = %s").format(table=sql.Identifier(selected_sensor))
                        cur.execute(delete_query, (dev_eui,))
                        conn.commit()
                        flash("🗑️ dev_eui supprimé avec succès.")
                cur.close()
                conn.close()
            except Exception as e:
                flash(f"❌ Erreur lors de l'opération sur le capteur : {e}")
        return redirect(url_for("sensor", sensor=selected_sensor))
    
    # GET : Si un capteur est sélectionné, on récupère ses dev_eui enregistrés
    if selected_sensor and validate_sensor_name(selected_sensor):
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            query = sql.SQL("SELECT dev_eui FROM {table}").format(table=sql.Identifier(selected_sensor))
            cur.execute(query)
            dev_euis = [row[0] for row in cur.fetchall()]
            cur.close()
            conn.close()
        except Exception as e:
            flash(f"❌ Erreur lors de la récupération des données du capteur : {e}")
    return render_template("sensor.html", sensors=sensors, selected_sensor=selected_sensor, dev_euis=dev_euis)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
