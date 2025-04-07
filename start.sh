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

# Liste ordonnée des JAR à démarrer
JAR_PACKAGES=(
    "back-for-front-0.0.1-SNAPSHOT.jar"
    "scan-port-0.0.1-SNAPSHOT.jar"
    "bruteforce-ssh-0.0.1-SNAPSHOT.jar"
    "wifi-attack-0.0.1-SNAPSHOT.jar"
    "analyse-cve-0.0.1-SNAPSHOT.jar"
    "generate-report-0.0.1-SNAPSHOT.jar"
)

# Options JVM pour les JAR
JAVA_OPTS="-Xmx512m"

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
    
    # Attendre que tous les services Docker soient prêts
    log_message "Attente du démarrage de tous les services Docker..."
    
    local services
    services=$(docker-compose -f "$DOCKER_COMPOSE_FILE" config --services)
    
    for service in $services; do
        local is_ready=false
        local retry_count=0
        local max_retries=30  # 5 minutes max (10 sec * 30)
        
        while [ "$is_ready" = false ] && [ $retry_count -lt $max_retries ]; do
            if docker-compose -f "$DOCKER_COMPOSE_FILE" ps "$service" | grep -q "Up"; then
                local container_id
                container_id=$(docker-compose -f "$DOCKER_COMPOSE_FILE" ps -q "$service")
                
                # Vérifier les logs pour des messages de démarrage
                if docker logs "$container_id" 2>&1 | grep -q -E '(started|ready|listening|initialization complete)'; then
                    log_message "Service $service démarré."
                    is_ready=true
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
}

find_latest_jar() {
    local package_dir="$1"
    find "$package_dir" -name "*.jar" -type f -print | sort -r | head -n 1
}

start_jar() {
    local package_name="$1"
    local package_dir="$JAR_DIR/$package_name"
    local jar_file
    
    if [ ! -d "$package_dir" ]; then
        log_message "Erreur: Le répertoire $package_dir n'existe pas."
        return 1
    fi
    
    jar_file=$(find_latest_jar "$package_dir")
    
    if [ -z "$jar_file" ]; then
        log_message "Erreur: Aucun fichier JAR trouvé dans $package_dir."
        return 1
    fi
    
    log_message "Démarrage de $package_name ($jar_file)..."
    
    # Créer un fichier de log spécifique pour chaque JAR
    local log_file="$LOG_DIR/$package_name.log"
    
    # Vérifier s'il s'agit du JAR de génération de rapports et ajouter les paramètres de BDD si nécessaire
    if [[ "$package_name" == "generate-report-0.0.1-SNAPSHOT.jar" ]]; then
        log_message "Configuration des paramètres de base de données pour le générateur de rapports"
        java $JAVA_OPTS \
            -Dspring.datasource.url=jdbc:mysql://localhost:30037/mydatabase \
            -Dspring.datasource.username=myuser \
            -Dspring.datasource.password=secret \
            -jar "$jar_file" > "$log_file" 2>&1 &
    else
        # Lancement standard pour les autres JARs
        java $JAVA_OPTS -jar "$jar_file" > "$log_file" 2>&1 &
    fi
    
    local pid=$!
    PIDS+=($pid)
    
    # Vérifier que le processus a démarré correctement
    if ! ps -p $pid > /dev/null; then
        log_message "Erreur: Le processus $package_name n'a pas démarré correctement."
        return 1
    fi
    
    log_message "$package_name démarré avec PID $pid."
    
    # Attendre un moment pour s'assurer que le JAR est opérationnel
    # On vérifie les logs pour un message de démarrage réussi
    local retry_count=0
    local max_retries=12  # 2 minutes max (10 sec * 12)
    local is_ready=false
    
    while [ "$is_ready" = false ] && [ $retry_count -lt $max_retries ]; do
        if grep -q -E '(started|ready|listening|initialization complete)' "$log_file"; then
            is_ready=true
        else
            retry_count=$((retry_count + 1))
            log_message "En attente du démarrage de $package_name... ($retry_count/$max_retries)"
            sleep 10
        fi
    done
    
    if [ "$is_ready" = true ]; then
        log_message "$package_name est prêt."
    else
        log_message "Avertissement: $package_name semble ne pas être complètement démarré après 2 minutes."
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
    
    log_message "Démarrage du programme Python..."
    
    # Créer un fichier de log pour le programme Python
    local log_file="$LOG_DIR/python-tool.log"
    
    (cd "$PYTHON_DIR" && $PYTHON_CMD > "$log_file" 2>&1) &
    local pid=$!
    PIDS+=($pid)
    
    # Vérifier que le processus a démarré correctement
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
    for package in "${JAR_PACKAGES[@]}"; do
        start_jar "$package" || {
            log_message "Erreur lors du démarrage de $package. Arrêt du lancement."
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