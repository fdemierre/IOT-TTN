#!/bin/bash

set -e

echo "🛠️  Initialisation complète de PostgreSQL avec utilisateur 'iot' et bases 'devices' + 'data'"

# === Étape 1 : Demander le mot de passe admin PostgreSQL ===
read -s -p "🔑 Entrez un mot de passe à définir pour l'utilisateur PostgreSQL 'postgres' : " POSTGRES_PASSWORD
echo ""

# === Mise à jour mot de passe postgres ===
echo "🔐 Mise à jour du mot de passe de 'postgres'..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';"

# === Étape 2 : Générer un mot de passe aléatoire pour 'iot' ===
IOT_USER="iot"
IOT_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

# === Étape 3 : Créer ou mettre à jour le compte 'iot' ===
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

# === Étape 4 : Créer les bases devices et data ===
for DB in devices data; do
    echo "🗃️  Création de la base '$DB'..."
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 || \
    sudo -u postgres createdb -O "$IOT_USER" "$DB"
done

# === Étape 5 : Créer la table mapping_decoder dans 'devices' ===
echo "📐 Création de la table 'mapping_decoder' dans 'devices'..."
sudo -u postgres psql -d devices -c "
CREATE TABLE IF NOT EXISTS mapping_decoder (
    dev_eui TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    decoder TEXT NOT NULL
);"

# === Étape 6 : Donner les droits à iot ===
sudo -u postgres psql -d devices -c "GRANT ALL PRIVILEGES ON TABLE mapping_decoder TO $IOT_USER;"

# === Étape 7 : Enregistrer le mot de passe localement ===
PGPASS_FILE="$HOME/IOT-TTN/iot-site/pgpass.json"
mkdir -p "$(dirname "$PGPASS_FILE")"
echo "{\"iot_password\": \"$IOT_PASSWORD\"}" > "$PGPASS_FILE"

# === Affichage final ===
echo ""
echo "✅ PostgreSQL initialisé avec succès !"
echo "👤 Utilisateur      : $IOT_USER"
echo "🔐 Mot de passe     : $IOT_PASSWORD"
echo "📁 Sauvegardé dans  : $PGPASS_FILE"
echo "🗃️  Bases créées    : devices, data"
echo "📄 Table            : mapping_decoder (droits complets accordés à $IOT_USER)"
