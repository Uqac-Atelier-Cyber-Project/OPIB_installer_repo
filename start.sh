#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# ======================== CONFIGURATION ========================

# Répertoire d'installation
INSTALL_DIR="/opt/opib"
JAR_DIR="$INSTALL_DIR/jars"
PYTHON_DIR="$INSTALL_DIR/python-tool"

# Chemin vers le fichier docker-compose.yml
DOCKER_COMPOSE_FILE="docker-compose.yaml"

FOLDERS_JAR=(
    "opib-api"
    "opib-scan-port"
    "opib-bruteforce-ssh"
    "opib-bruteforce-wifi"
    "opib-analytise-cve"
    "opib-generate-report"
)

# Liste ordonnée des JAR à démarrer
JAR_PACKAGES=(
    "back-for-front-0.0.1-SNAPSHOT.jar"
    "scan-port-0.0.1-SNAPSHOT.jar"
    "bruteforce-ssh-0.0.1-SNAPSHOT.jar"
    "wifi-attack-0.0.1-SNAPSHOT.jar"
    "analyse-cve-0.0.1-SNAPSHOT.jar"
    "generate-report-0.0.1-SNAPSHOT.jar"
)


# Commande pour démarrer le programme Python
PYTHON_CMD="python main.py"

# Fichier de log
LOG_DIR="$INSTALL_DIR/logs"
MAIN_LOG="$LOG_DIR/opib-launcher.log"

# Tableau pour stocker les PIDs des processus lancés
declare -a PIDS=()

# ======================== FONCTIONS ========================

setup_log_dir() {
    mkdir -p "$LOG_DIR"
    sudo chown -R "$USER:$USER" "$LOG_DIR"  # 👈 Ajout ici

    # Rotation des logs: on conserve le dernier log avec timestamp
    if [ -f "$MAIN_LOG" ]; then
        mv "$MAIN_LOG" "$LOG_DIR/opib-launcher-$(date +%Y%m%d-%H%M%S).log"
    fi
    touch "$MAIN_LOG"
    echo "=== OPIB Launcher démarré à $(date) ===" >> "$MAIN_LOG"
}

log_message() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" | tee -a "$MAIN_LOG"
}

cleanup() {
    log_message "Arrêt des processus en cours..."
    
    # Arrêt des processus Java en ordre inverse
    for ((i=${#PIDS[@]}-1; i>=0; i--)); do
        if [ -n "${PIDS[$i]}" ] && kill -0 "${PIDS[$i]}" 2>/dev/null; then
            log_message "Arrêt du processus ${PIDS[$i]}..."
            kill "${PIDS[$i]}" 2>/dev/null || true
            wait "${PIDS[$i]}" 2>/dev/null || true
        fi
    done
    
    # Arrêt de Docker Compose
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        log_message "Arrêt de Docker Compose..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" down
    fi
    
    log_message "Tous les processus ont été arrêtés."
    log_message "=== OPIB Launcher terminé à $(date) ==="
    exit 0
}

# Piège le signal d'interruption (CTRL+C)
trap cleanup SIGINT SIGTERM

start_docker_compose() {
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        log_message "Erreur: Le fichier docker-compose.yml n'existe pas à l'emplacement $DOCKER_COMPOSE_FILE"
        exit 1
    fi

    log_message "Démarrage de Docker Compose..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d

    log_message "Attente du démarrage de tous les services Docker..."

    local services
    services=$(docker-compose -f "$DOCKER_COMPOSE_FILE" config --services)

    for service in $services; do
        local is_ready=false
        local retry_count=0
        local max_retries=30  # 5 minutes max (10 sec * 30)

        local container_id
        container_id=$(docker-compose -f "$DOCKER_COMPOSE_FILE" ps -q "$service")

        if [ -z "$container_id" ]; then
            log_message "Erreur: Impossible de récupérer l'ID du conteneur pour le service $service."
            continue
        fi

        if ! docker inspect "$container_id" &>/dev/null; then
            log_message "Erreur: Le conteneur $container_id pour le service $service n'existe pas ou n'est pas inspectable."
            continue
        fi

        while [ "$is_ready" = false ] && [ $retry_count -lt $max_retries ]; do
            local status
            status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)

            if [ "$status" = "running" ]; then
                local has_healthcheck
                has_healthcheck=$(docker inspect --format='{{json .State.Health}}' "$container_id")

                if [ "$has_healthcheck" != "null" ]; then
                    local health_status
                    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_id")

                    if [ "$health_status" = "healthy" ]; then
                        log_message "Service $service est sain (healthy)."
                        is_ready=true
                        break
                    fi
                else
                    # Fallback : analyse des logs
                    if docker logs "$container_id" 2>&1 | grep -q -E '(started|ready|listening|Starting Nginx...)'; then
                        log_message "Service $service semble prêt (via les logs)."
                        is_ready=true
                        break
                    fi
                fi
            fi

            if [ "$is_ready" = false ]; then
                retry_count=$((retry_count + 1))
                log_message "En attente du service $service... ($retry_count/$max_retries)"
                sleep 10
            fi
        done

        if [ "$is_ready" = false ]; then
            log_message "Avertissement: Le service $service semble ne pas être complètement démarré après 5 minutes."
            log_message "Continuer quand même? (y/n)"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log_message "Arrêt du lancement à la demande de l'utilisateur."
                cleanup
            fi
        fi
    done

    log_message "Tous les services Docker sont prêts."
    sleep 10
}


find_latest_jar() {
    local package_dir="$1"
    find "$package_dir" -name "*.jar" -type f -print | sort -r | head -n 1
}

start_jar() {
    local jar_folder="$1"
    local jar_file="$2"
    local jar_dir="$JAR_DIR/$jar_folder"
    local jar_path="$jar_dir/$jar_file"
    local config_file="$jar_dir/application.properties"

    if [ ! -f "$jar_path" ]; then
        log_message "Erreur: Le fichier JAR $jar_path n'existe pas."
        return 1
    fi

    if [ ! -f "$config_file" ]; then
        log_message "Erreur: Le fichier de configuration $config_file n'existe pas."
        return 1
    fi

    log_message "Démarrage de $1 ($jar_path) avec le fichier de configuration $config_file..."
    
    local log_file="$LOG_DIR/$(echo "$1" | tr '/' '_').log"

    (
        cd "$jar_dir" || exit 1
        java -jar "$jar_file" > "$log_file" 2>&1 &
        echo $! > "$log_file.pid"
    )

    local pid=$(cat "$log_file.pid")
    rm "$log_file.pid"
    PIDS+=($pid)

    if ! ps -p $pid > /dev/null; then
        log_message "Erreur: Le processus $1 n'a pas démarré correctement."
        return 1
    fi

    log_message "$1 démarré avec PID $pid."

    local retry_count=0
    local max_retries=12
    local is_ready=false

    while [ "$is_ready" = false ] && [ $retry_count -lt $max_retries ]; do
        if grep -q -E '(process running)' "$log_file"; then
            is_ready=true
        else
            retry_count=$((retry_count + 1))
            log_message "En attente du démarrage de $1... ($retry_count/$max_retries)"
            sleep 10
        fi
    done

    if [ "$is_ready" = true ]; then
        log_message "$1 est prêt."
    else
        log_message "Avertissement: $1 semble ne pas être complètement démarré après 2 minutes."
        log_message "Continuer quand même? (y/n)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_message "Arrêt du lancement à la demande de l'utilisateur."
            cleanup
        fi
    fi

    return 0
}

start_python() {
    if [ ! -d "$PYTHON_DIR" ]; then
        log_message "Erreur: Le répertoire Python $PYTHON_DIR n'existe pas."
        return 1
    fi

    log_message "Vérification du port 8087..."
    local pid_on_port=$(lsof -ti:8087)
    if [ -n "$pid_on_port" ]; then
        log_message "Un processus utilise le port 8087 (PID: $pid_on_port). Arrêt du processus..."
        kill -9 "$pid_on_port" || {
            log_message "Erreur: Impossible de tuer le processus sur le port 8087."
            return 1
        }
    fi

    log_message "Démarrage du programme Python..."

    local log_file="$LOG_DIR/python-tool.log"

    if [ -f "$PYTHON_DIR/venv/bin/activate" ]; then
        log_message "Activation de l'environnement virtuel Python..."
        (cd "$PYTHON_DIR" && bash -c "source venv/bin/activate && $PYTHON_CMD" >> "$log_file" 2>&1) &
    else
        log_message "Erreur: Le fichier d'activation de l'environnement virtuel ($PYTHON_DIR/venv/bin/activate) est introuvable."
        return 1
    fi

    local pid=$!
    PIDS+=($pid)

    if ! ps -p $pid > /dev/null; then
        log_message "Erreur: Le programme Python n'a pas démarré correctement."
        return 1
    fi

    log_message "Programme Python démarré avec PID $pid."
    return 0
}
# ======================== MAIN ========================

main() {
    setup_log_dir
    log_message "Démarrage de l'infrastructure OPIB..."
    
    # Démarrer Docker Compose
    start_docker_compose
    
    # Démarrer les JAR dans l'ordre spécifié
    for i in "${!JAR_PACKAGES[@]}"; do
        local jar_file="${JAR_PACKAGES[$i]}"
        local jar_folder="${FOLDERS_JAR[$i]}"
        start_jar "$jar_folder" "$jar_file" || {
            log_message "Erreur lors du démarrage de $jar_file. Arrêt du lancement."
            cleanup
        }
    done
    
    # Démarrer le programme Python
    start_python || {
        log_message "Erreur lors du démarrage du programme Python. Arrêt du lancement."
        cleanup
    }
    
    log_message "Tous les composants OPIB sont en cours d'exécution."
    log_message "Appuyez sur CTRL+C pour arrêter tous les services."
    
    # Maintenir le script en cours d'exécution pour pouvoir capturer CTRL+C
    while true; do
        # Vérifier que tous les processus sont toujours en cours d'exécution
        for i in "${!PIDS[@]}"; do
            if ! ps -p "${PIDS[$i]}" > /dev/null; then
                log_message "Le processus ${PIDS[$i]} s'est arrêté de manière inattendue."
                cleanup
            fi
        done
        sleep 5
    done
}

main "$@"