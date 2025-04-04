#!/bin/bash

set -e

echo "🛠️  Initialisation complète de PostgreSQL avec utilisateur 'iot' et bases 'devices' + 'data'"

# === Étape 1 : Mot de passe superutilisateur postgres ===
read -s -p "🔑 Entrez un mot de passe à définir pour l'utilisateur PostgreSQL 'postgres' : " POSTGRES_PASSWORD
echo ""

echo "🔐 Mise à jour du mot de passe de 'postgres'..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';"

# === Étape 2 : Générer un mot de passe aléatoire pour 'iot' ===
IOT_USER="iot"
IOT_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

# === Étape 3 : Créer ou mettre à jour l'utilisateur 'iot' ===
echo "👤 Création/Mise à jour de l'utilisateur PostgreSQL '$IOT_USER'..."
sudo -u postgres psql <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '$IOT_USER'
   ) THEN
      CREATE ROLE $IOT_USER LOGIN PASSWORD '$IOT_PASSWORD';
   ELSE
      ALTER ROLE $IOT_USER WITH PASSWORD '$IOT_PASSWORD';
   END IF;
END
\$do\$;
EOF

# === Étape 4 : Créer les bases 'devices' et 'data' ===
for DB in devices data; do
    echo "🗃️  Création de la base '$DB'..."
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 || \
    sudo -u postgres createdb -O "$IOT_USER" "$DB"
done

# === Étape 7 : Sauvegarder le mot de passe ===
mkdir -p "$HOME/IOT-TTN/iot-site"

# Sauvegarde en JSON
echo "{\"iot_password\": \"$IOT_PASSWORD\"}" > "$HOME/IOT-TTN/iot-site/pgpass.json"

# Sauvegarde en texte brut
echo "$IOT_PASSWORD" > "$HOME/IOT-TTN/pass.txt"

# === Résultat ===
echo ""
echo "✅ PostgreSQL initialisé avec succès !"
echo "👤 Utilisateur      : $IOT_USER"
echo "🔐 Mot de passe     : $IOT_PASSWORD"
echo "📁 JSON sauvegardé  : ~/IOT-TTN/iot-site/pgpass.json"
echo "📄 Mot de passe brut : ~/IOT-TTN/pass.txt"
echo "🗃️  Bases créées    : devices, data"
