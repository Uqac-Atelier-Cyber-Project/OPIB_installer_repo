# OPIB - Outil Pentest Indépendant Breton

Ce projet est un projet universitaire réalisé dans le cadre de l'atelier Cybersécurité 2 de l'UQAC. OPIB (Outil Pentest Indépendant Breton) est une suite d'outils conçue pour effectuer des tests de pénétration et des analyses de sécurité. Il intègre plusieurs services backend, un frontend Vue.js, ainsi qu'un outil Python pour la génération de rapports utilisant de l'IA DeepSeek.

## Fichiers de Paramétrage

### Fichiers `application.properties`

Chaque service backend dispose d'un fichier `application.properties` qui configure les paramètres spécifiques à ce service. Voici un aperçu des principaux fichiers et de leur contenu :

- **`opib-api/application.properties`**  
  Configure le service "back-for-front" avec les paramètres suivants :
  - `server.port`: Port d'écoute du service (par défaut `8090`).
  - `api.externe.url-*`: URLs des services externes (scan-port, bruteforce-ssh, etc.).
  - Configuration MySQL : URL, utilisateur, mot de passe, etc.

- **`opib-bruteforce-wifi/application.properties`**  
  Configure le service de brute force WiFi :
  - `server.port`: Port d'écoute (par défaut `8084`).
  - `api.externe.url`: URL de l'API externe.

- **`opib-generate-report/application.properties`**  
  Configure le service de génération de rapports :
  - `server.port`: Port d'écoute (par défaut `8086`).
  - Configuration MySQL : URL, utilisateur, mot de passe, etc.
  - `api.externe.path`: Chemin pour les données externes.

### Script `install.sh`

Le script `install.sh` est utilisé pour installer et configurer l'environnement nécessaire au fonctionnement d'OPIB. Voici ses principales fonctionnalités :
- Installation des dépendances nécessaires (Java, Docker, Node.js, etc.).
- Installation de Docker et Docker Compose.
- Téléchargement des fichiers JAR des services backend depuis leurs dépôts GitHub.
- Clonage du programme Python pour la génération de rapports.
- Configuration des permissions sudo pour exécuter les services sans mot de passe.

### Script `start.sh`

Le script `start.sh` est utilisé pour démarrer l'ensemble des services OPIB. Voici ses principales fonctionnalités :
- Démarrage des conteneurs Docker (MySQL et frontend Vue.js).
- Démarrage des services backend (fichiers JAR) dans un ordre spécifique.
- Démarrage du programme Python pour la génération de rapports.
- Gestion des logs pour chaque composant.
- Surveillance des processus pour s'assurer qu'ils restent actifs.

## Structure du Projet

Le projet est organisé en plusieurs répertoires :
- **`opib-api`**, **`opib-bruteforce-wifi`**, etc. : Services backend Spring Boot.
- **`ihm-vue-project`** : Frontend développé avec Vue.js.
- **`install.sh`** et **`start.sh`** : Scripts d'installation et de démarrage.
- **`docker-compose.yaml`** : Configuration Docker Compose pour les conteneurs MySQL et Vue.js.

## Instructions d'Installation et d'Utilisation

1. **Installation**  
   Exécutez le script `install.sh` en tant que root :
   ```bash
   sudo ./install.sh
    ```

    Lors de l'installation, macchanger peut demander si vous acceptez de changer l'adresse MAC automatiquement. Répondez "no" pour continuer.


    Docker Compose vous demandera si vous voulez le mettre à jour. Répondez "o" pour continuer.

2. **Démarrage des Services**
    Exécutez le script `start.sh` :
    ```bash
    sudo ./start.sh
    ```
    Cela démarrera tous les services OPIB et affichera les logs dans la console.
    Vous pouvez également accéder à l'interface utilisateur via `http://localhost:8091`.

3. **Arrêt des Services**
    Pour arrêter les services, utilisez `Ctrl+C` dans le terminal où le script `start.sh` est en cours d'exécution. Cela arrêtera tous les services et conteneurs Docker.