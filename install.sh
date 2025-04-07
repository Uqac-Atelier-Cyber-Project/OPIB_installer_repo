#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# ======================== CONFIGURATION ========================

DEPENDENCIES=(
    openjdk-21-jdk
    docker.io
    curl
    git
    g++
    make
    nodejs
    npm
    texlive
    texlive-latex-extra
    pandoc
    qpdf
    fonts-dejavu
    aircrack-ng
    reaver
    pixiewps
    macchanger
    python3
    python3-pip
    python-is-python3
    net-tools
    tshark
    bully
    cowpatty
    john
    hashcat
    hcxdumptool
    jq
    unzip
    zip
    wget
    build-essential
    software-properties-common
    gnupg
    lsb-release
    ca-certificates
    nmap
)

# Version de Docker Compose à installer (dernière version stable)
DOCKER_COMPOSE_VERSION="v2.25.0"

# Configuration des JAR à télécharger
# Format: [nom_package]=[URL de la release]
JAR_PACKAGES=(
    "opib-api=https://github.com/Uqac-Atelier-Cyber-Project/spring-boot-back-for-front-api-rest/releases/download/v0.0.1-SNAPSHOT/back-for-front-0.0.1-SNAPSHOT.jar"
    "opib-scan-port=https://github.com/Uqac-Atelier-Cyber-Project/spring-boot-scan-port/releases/download/v0.0.1-SNAPSHOT/scan-port-0.0.1-SNAPSHOT.jar"
    "opib-bruteforce-ssh=https://github.com/Uqac-Atelier-Cyber-Project/spring-boot-bruteforce-ssh/releases/download/v0.0.1-SNAPSHOT/bruteforce-ssh-0.0.1-SNAPSHOT.jar"
    "opib-bruteforce-wifi=https://github.com/Uqac-Atelier-Cyber-Project/spring-boot-attack-wifi/releases/download/v0.0.1-SNAPSHOT/wifi-attack-0.0.1-SNAPSHOT.jar"
    "opib-analytise-cve=https://github.com/Uqac-Atelier-Cyber-Project/spring-boot-analyse-cve/releases/download/v0.0.1-SNAPSHOT/analyse-cve-0.0.1-SNAPSHOT.jar"
    "opib-generate-report=https://github.com/Uqac-Atelier-Cyber-Project/spring-boot-generate-report/releases/download/v0.0.1-SNAPSHOT/generate-report-0.0.1-SNAPSHOT.jar"
)

# URL du programme Python
PYTHON_REPO="https://github.com/Uqac-Atelier-Cyber-Project/API_Python_IA_Generate_Report.git"

# Répertoire d'installation
INSTALL_DIR="/opt/opib"
JAR_DIR="$INSTALL_DIR/jars"
PYTHON_DIR="$INSTALL_DIR/python-tool"

LOGO='
=======================================
#    /$$$$$$  /$$$$$$$  /$$$$$$ /$$$$$$$
#   /$$__  $$| $$__  $$|_  $$_/| $$__  $$
#  | $$  \ $$| $$  \ $$  | $$  | $$  \ $$
#  | $$  | $$| $$$$$$$/  | $$  | $$$$$$$
#  | $$  | $$| $$____/   | $$  | $$__  $$
#  | $$  | $$| $$        | $$  | $$  \ $$
#  |  $$$$$$/| $$       /$$$$$$| $$$$$$$/
#   \______/ |__/      |______/|_______/
=======================================
Bienvenue dans l'\''installateur OPIB
'

# ======================== FONCTIONS ========================

display_logo() {
    printf "%s\n\n" "$LOGO"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        printf "Erreur : veuillez exécuter ce script en tant que root (sudo).\n" >&2
        return 1
    fi
}

update_system() {
    printf "Mise à jour du système...\n"
    apt update && apt upgrade -y || {
        printf "Échec de la mise à jour des paquets.\n" >&2
        return 1
    }
}

install_dependencies() {
    printf "Installation des dépendances requises...\n"
    if ! apt install -y "${DEPENDENCIES[@]}"; then
        printf "Échec de l'installation des paquets.\n" >&2
        return 1
    fi
}

validate_docker_installation() {
    if ! command -v docker >/dev/null 2>&1; then
        printf "Docker n'est pas installé correctement.\n" >&2
        return 1
    fi
}

configure_docker_user() {
    local current_user; current_user=$(logname)
    if ! getent group docker >/dev/null; then
        groupadd docker
    fi
    if ! id -nG "$current_user" | grep -qw docker; then
        usermod -aG docker "$current_user" || {
            printf "Impossible d'ajouter l'utilisateur %s au groupe docker.\n" "$current_user" >&2
            return 1
        }
        printf "Utilisateur %s ajouté au groupe docker. Déconnectez-vous/reconnectez-vous pour activer les changements.\n" "$current_user"
    else
        printf "L'utilisateur %s est déjà membre du groupe docker.\n" "$current_user"
    fi
}

install_docker_compose() {
    printf "Installation de Docker Compose %s...\n" "$DOCKER_COMPOSE_VERSION"
    
    # Vérifier si Docker Compose est déjà installé
    if command -v docker-compose >/dev/null 2>&1; then
        local installed_version; installed_version=$(docker-compose --version | awk '{print $3}' | tr -d ',')
        printf "Docker Compose est déjà installé (version %s).\n" "$installed_version"
        
        # Demander confirmation pour la mise à jour
        read -r -p "Voulez-vous mettre à jour Docker Compose? [o/N] " response
        case "$response" in
            [oO][uU][iI]|[oO])
                printf "Mise à jour de Docker Compose...\n"
                ;;
            *)
                printf "Installation de Docker Compose ignorée.\n"
                return 0
                ;;
        esac
    fi
    
    # Télécharger et installer Docker Compose
    if ! curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
        printf "Échec du téléchargement de Docker Compose.\n" >&2
        return 1
    fi
    
    # Rendre exécutable
    if ! chmod +x /usr/local/bin/docker-compose; then
        printf "Échec lors de la définition des permissions de Docker Compose.\n" >&2
        return 1
    fi
    
    # Vérifier l'installation
    if ! docker-compose --version; then
        printf "Échec de l'installation de Docker Compose.\n" >&2
        return 1
    fi
    
    printf "Docker Compose %s installé avec succès.\n" "$DOCKER_COMPOSE_VERSION"
    return 0
}

install_nvidia_docker() {
    local distribution; distribution=$(. /etc/os-release; printf "%s%s" "$ID" "$VERSION_ID")

    if ! curl -fsSL https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add - >/dev/null 2>&1; then
        printf "Échec de l'ajout de la clé GPG NVIDIA.\n" >&2
        return 1
    fi

    if ! curl -fsSL "https://nvidia.github.io/nvidia-docker/${distribution}/nvidia-docker.list" | tee /etc/apt/sources.list.d/nvidia-docker.list >/dev/null; then
        printf "Échec de l'ajout du dépôt NVIDIA.\n" >&2
        return 1
    fi

    if ! apt update; then
        printf "Échec lors de la mise à jour après ajout du dépôt NVIDIA.\n" >&2
        return 1
    fi

    if ! apt install -y nvidia-container-toolkit; then
        printf "Échec de l'installation de nvidia-container-toolkit.\n" >&2
        return 1
    fi

    if systemctl is-active --quiet docker; then
        systemctl restart docker || {
            printf "Échec du redémarrage de Docker.\n" >&2
            return 1
        }
        printf "Docker redémarré après installation NVIDIA.\n"
    else
        printf "Docker n'est pas actif, redémarrage ignoré.\n"
    fi
}

download_github_packages() {
    printf "Configuration des répertoires d'installation...\n"
    
    # Créer le répertoire principal et celui des JARs s'ils n'existent pas
    mkdir -p "$JAR_DIR" || {
        printf "Échec de la création du répertoire des JARs %s.\n" "$JAR_DIR" >&2
        return 1
    }
    
    # Télécharger les packages JAR depuis les releases GitHub
    printf "Téléchargement des packages JAR depuis GitHub Releases...\n"
    
    for package_info in "${JAR_PACKAGES[@]}"; do
        # Extraire le nom et l'URL du package
        package_name=${package_info%%=*}
        package_url=${package_info#*=}
        
        # Extraire le nom du fichier depuis l'URL
        jar_filename=$(basename "$package_url")
        
        # Créer un sous-répertoire pour le package
        package_dir="$JAR_DIR/$package_name"
        mkdir -p "$package_dir" || {
            printf "Échec de la création du répertoire %s.\n" "$package_dir" >&2
            return 1
        }
        
        printf "Téléchargement de %s...\n" "$jar_filename"
        
        if ! wget -q "$package_url" -O "$package_dir/$jar_filename"; then
            printf "Échec du téléchargement de %s.\n" "$jar_filename" >&2
            return 1
        fi
        
        printf "Package %s téléchargé avec succès.\n" "$jar_filename"
    done
    
    # Cloner le programme Python
    printf "Clonage du programme Python depuis GitHub...\n"
    
    if [ -d "$PYTHON_DIR" ]; then
        printf "Le répertoire %s existe déjà. Mise à jour...\n" "$PYTHON_DIR"
        (cd "$PYTHON_DIR" && git pull) || {
            printf "Échec de la mise à jour du programme Python.\n" >&2
            return 1
        }
    else
        git clone "$PYTHON_REPO" "$PYTHON_DIR" || {
            printf "Échec du clonage du programme Python.\n" >&2
            return 1
        }
    fi
    
    # Installer les dépendances Python si requirements.txt existe
    if [ -f "$PYTHON_DIR/requirements.txt" ]; then
        printf "Installation des dépendances Python...\n"
        pip3 install -r "$PYTHON_DIR/requirements.txt" || {
            printf "Échec de l'installation des dépendances Python.\n" >&2
            return 1
        }
    fi
    
    # Donner les permissions appropriées
    chown -R "$(logname):$(logname)" "$INSTALL_DIR" || {
        printf "Échec lors de la modification des permissions sur %s.\n" "$INSTALL_DIR" >&2
        return 1
    }
    
    printf "Tous les packages ont été téléchargés et configurés avec succès dans %s.\n" "$INSTALL_DIR"
    return 0
}

# ======================== MAIN ========================

main() {
    display_logo
    check_root || return 1
    update_system || return 1
    install_dependencies || return 1
    validate_docker_installation || return 1
    configure_docker_user || return 1
    install_docker_compose || return 1
    install_nvidia_docker || return 1
    download_github_packages || return 1
    printf "Installation terminée avec succès.\n"
}

main "$@"