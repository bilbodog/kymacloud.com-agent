#!/bin/bash

################################################################################
# kyma-install.sh - Kyma Hosting Platform Installation Script
################################################################################
#
# Dette script installerer Kyma Hosting Platform med:
#   - Docker og Docker Compose
#   - Alle nødvendige dependencies
#   - Dedikeret kymacloud bruger/gruppe (ikke root)
#   - Multi-tenant struktur baseret på organization ID
#   - SSH key setup via API
#
# Usage:
#   curl -sSL https://install.kymacloud.com/install.sh | bash -s -- <QUERY_ID>
#
#   Eller manuelt:
#   ./kyma-install.sh <QUERY_ID>
#
################################################################################

set -e
set -o pipefail

# Farver
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}\n"; }

################################################################################
# Konfiguration
################################################################################

QUERY_ID=__QUERY_ID__
API_URL="https://app.kymacloud.com/api/v1/servers/init/"
KYMA_USER="kymacloud"
KYMA_GROUP="kymacloud"
KYMA_HOME="/opt/kymacloud"
KYMA_UID=3500
KYMA_GID=3500

################################################################################
# Banner
################################################################################

show_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║   ██╗  ██╗██╗   ██╗███╗   ███╗ █████╗                   ║
    ║   ██║ ██╔╝╚██╗ ██╔╝████╗ ████║██╔══██╗                  ║
    ║   █████╔╝  ╚████╔╝ ██╔████╔██║███████║                  ║
    ║   ██╔═██╗   ╚██╔╝  ██║╚██╔╝██║██╔══██║                  ║
    ║   ██║  ██╗   ██║   ██║ ╚═╝ ██║██║  ██║                  ║
    ║   ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝                  ║
    ║                                                           ║
    ║              Hosting Platform v2.1                       ║
    ║            Production Installation                       ║
    ║          36 Unified Commands Available                   ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

################################################################################
# Validering
################################################################################

validate_input() {
    # Check if QUERY_ID is set and not placeholder
    if [ -z "$QUERY_ID" ]; then
        log_error "Manglende QUERY_ID"
        echo ""
        echo "Dette script får QUERY_ID automatisk fra API når det serves."
        echo ""
        echo "Manuel brug:"
        echo "  bash kyma-install.sh <QUERY_ID>"
        echo ""
        echo "Eksempel:"
        echo "  bash kyma-install.sh 2"
        echo ""
        echo "Eller via API (anbefalet):"
        echo "  curl -sSL https://install.kymacloud.com/api/init/2 | bash"
        echo ""
        exit 1
    fi
        
    # Tjek om root
    if [ "$EUID" -ne 0 ]; then
        log_error "Dette script skal køres som root"
        echo "Kør med: sudo bash kyma-install.sh $QUERY_ID"
        exit 1
    fi
    
    log_success "Input valideret"
    return 0
}

################################################################################
# API kommunikation
################################################################################

fetch_organization_data() {
    log_step "STEP 1: Henter organization data fra API"
    
    log_info "Kontakter API: $API_URL"
    log_info "Query ID: $QUERY_ID"
    apt update && apt install jq
    RESPONSE=$(curl -s -X POST "$API_URL" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"id\": \"$QUERY_ID\"}" 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
        log_error "API kald fejlede"
        echo "Response: $RESPONSE"
        exit 1
    fi
    
    log_success "API response modtaget"
    
    # Debug: Show raw response (first 200 chars)
    log_info "Response preview: ${RESPONSE:0:200}..."
    
    # Parse response - API returns: public_key (base64) and organization_id
    export SSH_KEY_RAW=$(echo "$RESPONSE" | jq -r '.public_key // .ssh_rsa // .SSH_RSA // empty')
    export ORG_ID=$(echo "$RESPONSE" | jq -r '.organization_id // .kunde_id // .KundeID // empty')
    export ORG_NAME=$(echo "$RESPONSE" | jq -r '.organization_name // .navn // .name // empty')
    export ORG_EMAIL=$(echo "$RESPONSE" | jq -r '.email // empty')
    
    if [ -z "$SSH_KEY_RAW" ] || [ -z "$ORG_ID" ]; then
        log_error "Kunne ikke parse API response"
        echo "Debug info:"
        echo "  Response: $RESPONSE"
        echo "  SSH Key (first 50 chars): ${SSH_KEY_RAW:0:50}..."
        echo "  Org ID: $ORG_ID"
        exit 1
    fi
    
    # public_key is already the base64 part, format it correctly
    export SSH_KEY_FORMATTED="ssh-rsa ${SSH_KEY_RAW} RSA-by-KymaCloud"
    
    log_success "Organization ID: $ORG_ID"
    log_info "SSH Key: ${SSH_KEY_RAW:0:50}..."
    [ -n "$ORG_NAME" ] && log_info "Organization: $ORG_NAME" || true
    [ -n "$ORG_EMAIL" ] && log_info "Email: $ORG_EMAIL" || true
    
    return 0
}

################################################################################
# System dependencies
################################################################################

install_dependencies() {
    log_step "STEP 2: Installerer system dependencies"
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "Kunne ikke detektere OS"
        exit 1
    fi
    
    log_info "OS: $OS $OS_VERSION"
    
    case $OS in
        ubuntu|debian)
            log_info "Opdaterer package lists..."
            apt-get update -qq
            
            log_info "Installerer dependencies..."
            apt-get install -y -qq \
                curl \
                wget \
                git \
                jq \
                openssl \
                ca-certificates \
                gnupg \
                lsb-release \
                ufw \
                fail2ban \
                unzip \
                > /dev/null
            
            log_success "Dependencies installeret"
            ;;
        
        centos|rhel|fedora)
            log_info "Installerer dependencies..."
            yum install -y -q \
                curl \
                wget \
                git \
                jq \
                openssl \
                ca-certificates \
                firewalld \
                fail2ban \
                unzip \
                > /dev/null
            
            log_success "Dependencies installeret"
            ;;
        
        *)
            log_warning "Ukendt OS: $OS"
            log_info "Fortsætter med installation..."
            ;;
    esac
}

################################################################################
# Docker installation
################################################################################

install_docker() {
    log_step "STEP 3: Installerer Docker"
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker er allerede installeret (version $DOCKER_VERSION)"
        return 0
    fi
    
    log_info "Downloader Docker installation script..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    
    log_info "Installerer Docker..."
    sh /tmp/get-docker.sh > /dev/null 2>&1
    
    log_info "Starter Docker service..."
    systemctl enable docker
    systemctl start docker
    
    # Test Docker
    if docker run --rm hello-world > /dev/null 2>&1; then
        log_success "Docker installeret og virker"
    else
        log_error "Docker installation fejlede"
        exit 1
    fi
    
    rm -f /tmp/get-docker.sh
}

################################################################################
# Kyma bruger setup
################################################################################

setup_kyma_user() {
    log_step "STEP 4: Opretter Kyma bruger og gruppe"
    
    # Opret gruppe
    if ! getent group "$KYMA_GROUP" > /dev/null 2>&1; then
        groupadd -g $KYMA_GID "$KYMA_GROUP"
        log_success "Gruppe oprettet: $KYMA_GROUP (GID: $KYMA_GID)"
    else
        log_info "Gruppe eksisterer allerede: $KYMA_GROUP"
    fi
    
    # Opret bruger
    if ! id "$KYMA_USER" > /dev/null 2>&1; then
        useradd \
            -m \
            -d "$KYMA_HOME" \
            -s /bin/bash \
            -g "$KYMA_GROUP" \
            -u $KYMA_UID \
            -c "Kyma Hosting Platform Service User" \
            "$KYMA_USER"
        
        log_success "Bruger oprettet: $KYMA_USER (UID: $KYMA_UID)"
    else
        log_info "Bruger eksisterer allerede: $KYMA_USER"
    fi
    
    # Tilføj til docker gruppe
    usermod -aG docker "$KYMA_USER"
    log_success "Bruger tilføjet til docker gruppe"
    
    # Setup SSH
    log_info "Opsætter SSH keys..."
    mkdir -p "$KYMA_HOME/.ssh"
    echo "$SSH_KEY_FORMATTED" > "$KYMA_HOME/.ssh/authorized_keys"
    
    chown -R ${KYMA_USER}:${KYMA_GROUP} "$KYMA_HOME/.ssh"
    chmod 700 "$KYMA_HOME/.ssh"
    chmod 600 "$KYMA_HOME/.ssh/authorized_keys"
    
    log_success "SSH keys installeret"
}

################################################################################
# Sudo permissions setup
################################################################################

setup_sudo_permissions() {
    log_step "STEP 4B: Opsætter sudo permissions for kymacloud"
    
    # Installer sudoers fil
    log_info "Installerer sudoers konfiguration..."
    
    local sudoers_source="$KYMA_HOME/platform/sudoers.d/kymacloud"
    local sudoers_dest="/etc/sudoers.d/kymacloud"
    
    if [ -f "$sudoers_source" ]; then
        # Kopier fil
        cp "$sudoers_source" "$sudoers_dest"
        
        # Set korrekte permissions (kritisk for sudoers!)
        chown root:root "$sudoers_dest"
        chmod 440 "$sudoers_dest"
        
        # Verificer sudoers syntax
        if visudo -cf "$sudoers_dest"; then
            log_success "Sudoers konfiguration installeret og verificeret"
        else
            log_error "Sudoers syntax fejl - fjerner fil"
            rm -f "$sudoers_dest"
            return 1
        fi
    else
        log_warning "Sudoers template ikke fundet: $sudoers_source"
        log_info "Opretter basic sudoers konfiguration..."
        
        # Opret basic sudoers fil
        cat > "$sudoers_dest" <<'SUDOERS'
# Allow kymacloud to run site-manager.sh as root (updated path)
kymacloud ALL=(ALL) NOPASSWD: /opt/kymacloud/platform/scripts/utilities/site-manager.sh
kymacloud ALL=(ALL) NOPASSWD: /opt/kymacloud/platform/site-manager.sh

# Allow specific system commands
kymacloud ALL=(ALL) NOPASSWD: /usr/sbin/useradd
kymacloud ALL=(ALL) NOPASSWD: /usr/sbin/userdel
kymacloud ALL=(ALL) NOPASSWD: /usr/sbin/chpasswd
kymacloud ALL=(ALL) NOPASSWD: /bin/chown
kymacloud ALL=(ALL) NOPASSWD: /bin/chmod
kymacloud ALL=(ALL) NOPASSWD: /usr/sbin/sshd
kymacloud ALL=(ALL) NOPASSWD: /usr/bin/docker
kymacloud ALL=(ALL) NOPASSWD: /usr/local/bin/docker-compose

Defaults:kymacloud !requiretty
SUDOERS
        
        chown root:root "$sudoers_dest"
        chmod 440 "$sudoers_dest"
        
        if visudo -cf "$sudoers_dest"; then
            log_success "Basic sudoers konfiguration oprettet"
        else
            log_error "Sudoers syntax fejl"
            rm -f "$sudoers_dest"
            return 1
        fi
    fi
    
    log_info "Testing sudo adgang..."
    if sudo -u kymacloud sudo -n true 2>/dev/null; then
        log_success "✓ Kymacloud bruger kan køre sudo kommandoer"
    else
        log_warning "⚠ Kunne ikke verificere sudo adgang"
    fi
    
    # Opret alias i kymacloud brugers bashrc
    log_info "Opsætter bash aliases for kymacloud bruger..."
    
    local bashrc="$KYMA_HOME/.bashrc"
    
    if ! grep -q "# Kyma Aliases" "$bashrc" 2>/dev/null; then
        cat >> "$bashrc" <<'BASHRC'

################################################################################
# Kyma Aliases
################################################################################

# Site manager alias (kører med sudo automatisk)
alias kyma='sudo /opt/kymacloud/platform/scripts/utilities/site-manager.sh'

# Quick commands
alias kyma-sites='sudo /opt/kymacloud/platform/scripts/utilities/site-manager.sh site:list'
alias kyma-status='sudo /opt/kymacloud/platform/scripts/utilities/site-manager.sh system:status'
alias kyma-logs='sudo /opt/kymacloud/platform/scripts/utilities/site-manager.sh system:logs'
alias kyma-backup='sudo /opt/kymacloud/platform/scripts/utilities/site-manager.sh backup:all'

# Navigate to platform
alias cdp='cd /opt/kymacloud/platform'
alias cds='cd /opt/kymacloud/organizations/org-'

# Docker shortcuts
alias dc='docker compose'
alias dps='docker ps'
alias dlogs='docker compose logs -f'

echo "Kyma Hosting Platform v2.1"
echo "═══════════════════════════════════════"
echo "Unified Command System - 36 commands available!"
echo "═══════════════════════════════════════"
echo "Usage: kyma <category>:<action> [options]"
echo ""
echo "Examples:"
echo "  kyma site:list              # List all sites"
echo "  kyma credentials:show <domain>"
echo "  kyma diagnose:site <domain>"
echo "  kyma backup:all             # Backup everything"
echo ""
echo "Help: kyma --help"
BASHRC
        
        chown ${KYMA_USER}:${KYMA_GROUP} "$bashrc"
        chmod 644 "$bashrc"
        
        log_success "Bash aliases konfigureret"
    else
        log_info "Bash aliases allerede konfigureret"
    fi
    
    return 0
}

################################################################################
# SFTP gruppe setup
################################################################################

setup_sftp_group() {
    log_step "STEP 5: Opretter SFTP gruppe"
    
    if ! getent group "sftpusers" > /dev/null 2>&1; then
        groupadd -g 5000 sftpusers
        log_success "SFTP gruppe oprettet: sftpusers (GID: 5000)"
    else
        log_info "SFTP gruppe eksisterer allerede"
    fi
}

################################################################################
# Directory struktur
################################################################################

setup_directory_structure() {
    log_step "STEP 6: Opretter directory struktur"
    
    log_info "Opretter organization directory: org-${ORG_ID}"
    
    # Hovedstruktur
    mkdir -p "$KYMA_HOME/organizations/org-${ORG_ID}"
    mkdir -p "$KYMA_HOME/organizations/org-${ORG_ID}/sites"
    mkdir -p "$KYMA_HOME/organizations/org-${ORG_ID}/backups"
    mkdir -p "$KYMA_HOME/organizations/org-${ORG_ID}/logs"
    mkdir -p "$KYMA_HOME/organizations/org-${ORG_ID}/config"
    
    # Platform filer
    mkdir -p "$KYMA_HOME/platform"
    mkdir -p "$KYMA_HOME/platform/nginx/conf.d"
    mkdir -p "$KYMA_HOME/platform/php"
    mkdir -p "$KYMA_HOME/platform/mariadb/data"
    mkdir -p "$KYMA_HOME/platform/mariadb/conf.d"
    mkdir -p "$KYMA_HOME/platform/traefik"
    mkdir -p "$KYMA_HOME/platform/traefik/dynamic"
    mkdir -p "$KYMA_HOME/platform/proftpd"
    
    # Opret acme.json for Let's Encrypt (skal have chmod 600)
    touch "$KYMA_HOME/platform/traefik/acme.json"
    chmod 600 "$KYMA_HOME/platform/traefik/acme.json"
    chown "${KYMA_USER}:${KYMA_GROUP}" "$KYMA_HOME/platform/traefik/acme.json"
    
    log_success "Directory struktur oprettet"
    
    # Gem organization metadata
    cat > "$KYMA_HOME/organizations/org-${ORG_ID}/metadata.json" <<EOF
{
  "organization_id": "$ORG_ID",
  "organization_name": "${ORG_NAME:-Unknown}",
  "email": "${ORG_EMAIL:-}",
  "created_at": "$(date -Iseconds)",
  "platform_version": "2.1.0"
}
EOF
    
    log_success "Organization metadata gemt"
}

################################################################################
# Download og installer platform filer
################################################################################

copy_platform_files() {
    log_step "STEP 7: Downloader platform filer"
    
    local PLATFORM_RELEASE_URL="https://kymoso2.vyprojects.org/releases/production/rel.zip"
    local TEMP_DIR="/tmp/kyma-platform-$$"
    local ZIP_FILE="$TEMP_DIR/rel.zip"
    
    log_info "Release URL: $PLATFORM_RELEASE_URL"
    log_info "Target directory: $KYMA_HOME/platform"
    
    # Opret temp directory
    mkdir -p "$TEMP_DIR"
    
    # Download release zip
    log_info "Downloader platform release..."
    if ! curl -fsSL -o "$ZIP_FILE" "$PLATFORM_RELEASE_URL"; then
        log_error "Kunne ikke downloade platform release fra $PLATFORM_RELEASE_URL"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    log_success "Platform release downloadet ($(du -h "$ZIP_FILE" | awk '{print $1}'))"
    
    # Verificer at det er en gyldig zip fil
    if ! unzip -t "$ZIP_FILE" > /dev/null 2>&1; then
        log_error "Downloadet fil er ikke en gyldig ZIP fil"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    log_success "ZIP fil verificeret"
    
    # Udtræk til temp directory
    log_info "Udtrækker platform filer..."
    if ! unzip -q -o "$ZIP_FILE" -d "$TEMP_DIR/extracted"; then
        log_error "Kunne ikke udtrække ZIP fil"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    log_success "Filer udtrukket"
    
    # Kopier filer til platform directory
    log_info "Kopierer filer til $KYMA_HOME/platform..."
    
    # Find source directory (hvis zip'en har en root folder eller ej)
    local EXTRACT_DIR="$TEMP_DIR/extracted"
    if [ -d "$EXTRACT_DIR/platform" ]; then
        # Hvis der er en platform folder i zip'en
        cp -r "$EXTRACT_DIR/platform/"* "$KYMA_HOME/platform/" 2>/dev/null || cp -r "$EXTRACT_DIR/"* "$KYMA_HOME/platform/"
    else
        # Hvis alle filer er i roden af zip'en
        cp -r "$EXTRACT_DIR/"* "$KYMA_HOME/platform/"
    fi
    
    log_success "Platform filer kopieret"
    
    # Ryd op i temp files
    log_info "Rydder op i temporary filer..."
    rm -rf "$TEMP_DIR"
    
    # Opdater paths i config
    log_info "Opdaterer konfiguration paths..."
    
    if [ -f "$KYMA_HOME/platform/lib/config.sh" ]; then
        # Config.sh auto-detecterer paths baseret på directory struktur, så vi behøver ikke sed
        log_info "Config fil fundet - paths vil blive auto-detected"
    else
        log_error "config.sh ikke fundet!"
        return 1
    fi
    
    # Set permissions for ALLE filer og directories under kymacloud
    log_info "Sætter permissions for kymacloud bruger..."
    chown -R ${KYMA_USER}:${KYMA_GROUP} "$KYMA_HOME"
    
    # Set executable permissions på scripts
    chmod +x "$KYMA_HOME/platform/scripts/utilities/site-manager.sh" 2>/dev/null || true
    find "$KYMA_HOME/platform/scripts" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$KYMA_HOME/platform/modules" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$KYMA_HOME/platform/lib" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    log_success "Permissions sat for ${KYMA_USER}:${KYMA_GROUP}"
    
    # Verificer kritiske filer
    local required_files=(
        "$KYMA_HOME/platform/scripts/utilities/site-manager.sh"
        "$KYMA_HOME/platform/lib/config.sh"
        "$KYMA_HOME/platform/docker-compose.yml"
    )
    
    local required_modules=(
        "$KYMA_HOME/platform/modules/site.sh"
        "$KYMA_HOME/platform/modules/user.sh"
        "$KYMA_HOME/platform/modules/database.sh"
        "$KYMA_HOME/platform/modules/system.sh"
        "$KYMA_HOME/platform/modules/credentials.sh"
        "$KYMA_HOME/platform/modules/diagnostics.sh"
        "$KYMA_HOME/platform/modules/backup.sh"
    )
    
    log_info "Verificerer kritiske filer..."
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Kritisk fil mangler: $file"
            return 1
        fi
    done
    
    log_info "Verificerer module filer..."
    for file in "${required_modules[@]}"; do
        if [ ! -f "$file" ]; then
            log_warning "Module mangler: $file (platformen kan have begrænset funktionalitet)"
        fi
    done
    
    # Ekstra permission check for vigtige directories
    log_info "Verificerer permissions..."
    local important_dirs=(
        "$KYMA_HOME/platform"
        "$KYMA_HOME/organizations/org-${ORG_ID}"
        "$KYMA_HOME/organizations/org-${ORG_ID}/sites"
        "$KYMA_HOME/organizations/org-${ORG_ID}/backups"
    )
    
    for dir in "${important_dirs[@]}"; do
        if [ -d "$dir" ]; then
            chown -R ${KYMA_USER}:${KYMA_GROUP} "$dir"
        fi
    done
    
    log_success "Alle filer downloadet, installeret og verificeret"
    return 0
}

################################################################################
# Generer konfiguration
################################################################################

generate_configuration() {
    log_step "STEP 8: Genererer konfiguration"
    
    # Generer stærkt database password
    DB_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
    
    log_success "Database password genereret"
    
    # Generer .env fil fra template
    log_info "Opretter .env fil fra template..."
    
    if [ -f "$KYMA_HOME/platform/env.template" ]; then
        # Ny metode: Brug env.template
        cp "$KYMA_HOME/platform/env.template" "$KYMA_HOME/platform/.env"
        
        # Erstat placeholders i .env
        sed -i "s|__ORG_ID__|${ORG_ID}|g" "$KYMA_HOME/platform/.env"
        sed -i "s|__ORG_NAME__|${ORG_NAME:-Unknown}|g" "$KYMA_HOME/platform/.env"
        sed -i "s|__ORG_EMAIL__|${ORG_EMAIL:-admin@example.com}|g" "$KYMA_HOME/platform/.env"
        sed -i "s|__DB_ROOT_PASSWORD__|${DB_ROOT_PASSWORD}|g" "$KYMA_HOME/platform/.env"
        
        # Set permissions (640 allows group read for containers like PHP-FPM)
        chmod 640 "$KYMA_HOME/platform/.env"
        chown "${KYMA_USER}:${KYMA_GROUP}" "$KYMA_HOME/platform/.env"
        
        log_success ".env fil oprettet fra template"
    else
        # Fallback: Opret minimal .env fil direkte (backward compatibility)
        log_warning "env.template ikke fundet - opretter minimal .env"
        
        cat > "$KYMA_HOME/platform/.env" <<ENVEOF
# Auto-generated by kyma-install.sh (fallback mode)
ORGANIZATION_ID=${ORG_ID}
ORGANIZATION_NAME=${ORG_NAME:-Unknown}
ORGANIZATION_EMAIL=${ORG_EMAIL:-admin@example.com}
MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
SETUP_TYPE=multi-tenant
PLATFORM_VERSION=2.1.0
ENVEOF
        
        chmod 640 "$KYMA_HOME/platform/.env"
        chown "${KYMA_USER}:${KYMA_GROUP}" "$KYMA_HOME/platform/.env"
        
        log_success ".env fil oprettet (fallback mode)"
    fi
    
    # Opdater docker-compose.yml med organization paths
    if [ -f "$KYMA_HOME/platform/docker-compose.yml" ]; then
        log_info "Opdaterer docker-compose.yml med org-${ORG_ID} paths..."
        
        # Tjek at ORG_ID er sat
        if [ -z "$ORG_ID" ]; then
            log_error "ORG_ID er ikke sat! Kan ikke konfigurere docker-compose.yml"
            return 1
        fi
        
        # Erstat kun __ORG_ID__ placeholders (resten håndteres af .env)
        sed -i "s|__ORG_ID__|${ORG_ID}|g" "$KYMA_HOME/platform/docker-compose.yml"
        
        # Verificer at erstatningen skete
        if grep -q "__ORG_ID__" "$KYMA_HOME/platform/docker-compose.yml"; then
            log_error "docker-compose.yml indeholder stadig __ORG_ID__ placeholder!"
            log_error "sed kommando fejlede. ORG_ID var: ${ORG_ID}"
            return 1
        fi
        
        # Verificer at den korrekte path eksisterer
        if ! grep -q "organizations/org-${ORG_ID}/sites" "$KYMA_HOME/platform/docker-compose.yml"; then
            log_warning "docker-compose.yml indeholder ikke forventet path: org-${ORG_ID}"
        fi
        
        log_success "docker-compose.yml konfigureret med org-${ORG_ID} paths"
    else
        log_error "docker-compose.yml ikke fundet"
        return 1
    fi
    
    # Opdater Traefik email
    if [ -n "$ORG_EMAIL" ] && [ -f "$KYMA_HOME/platform/traefik/traefik.yml" ]; then
        sed -i "s/admin@vyprojects.org/${ORG_EMAIL}/g" "$KYMA_HOME/platform/traefik/traefik.yml" 2>/dev/null || true
        log_success "Traefik email opdateret"
    fi
    
    # Gem admin credentials
    cat > "$KYMA_HOME/organizations/org-${ORG_ID}/config/README.txt" <<EOF
═══════════════════════════════════════════════════════════════
 KYMA HOSTING PLATFORM - CONFIGURATION
═══════════════════════════════════════════════════════════════

Organization ID:    $ORG_ID
Organization:       ${ORG_NAME:-Unknown}
Created:            $(date '+%Y-%m-%d %H:%M:%S')

🔐 ALLE CREDENTIALS ER I .env FILEN

Platform .env:      $KYMA_HOME/platform/.env

📝 For at se platform credentials:
   cat $KYMA_HOME/platform/.env

🔧 For at redigere .env:
   nano $KYMA_HOME/platform/.env

SYSTEM USER:
  User:             $KYMA_USER
  Group:            $KYMA_GROUP  
  Home:             $KYMA_HOME
  SSH Key:          Installeret fra API

PLATFORM PATHS:
  Platform:         $KYMA_HOME/platform
  Scripts:          $KYMA_HOME/platform/scripts
  Modules:          $KYMA_HOME/platform/modules
  Sites:            $KYMA_HOME/organizations/org-${ORG_ID}/sites
  Backups:          $KYMA_HOME/organizations/org-${ORG_ID}/backups
  Logs:             $KYMA_HOME/organizations/org-${ORG_ID}/logs

MANAGEMENT:
  SSH Login:        ssh ${KYMA_USER}@$(hostname -I | awk '{print $1}')
  Unified Command:  kyma <category>:<action>
  
AVAILABLE COMMANDS (36 total):
  Site:         kyma site:add|remove|list|info|backup|restore
  Users:        kyma user:sftp:add|remove|list
                kyma user:ftp:add|remove|list
  Database:     kyma db:backup|restore|list
  Credentials:  kyma credentials:show|sftp
  Diagnostics:  kyma diagnose:ftp|sftp|site
  Backup:       kyma backup:all|platform
  System:       kyma system:start|stop|restart|status|verify|update

⚠️  VIGTIGT:
  - Database root password er i $KYMA_HOME/platform/.env
  - Backup .env filen sikkert!
  - Commit ALDRIG .env til git
  - .env filen er beskyttet (chmod 600)

═══════════════════════════════════════════════════════════════
EOF
    
    chmod 644 "$KYMA_HOME/organizations/org-${ORG_ID}/config/README.txt"
    chown ${KYMA_USER}:${KYMA_GROUP} "$KYMA_HOME/organizations/org-${ORG_ID}/config/README.txt"
    
    log_success "Platform README oprettet"
}

################################################################################
# Firewall setup
################################################################################

setup_firewall() {
    log_step "STEP 9: Konfigurerer firewall"
    
    if command -v ufw &> /dev/null; then
        log_info "Konfigurerer UFW..."
        
        # Tillad SSH først!
        ufw allow 22/tcp comment "SSH" > /dev/null 2>&1 || true
        ufw allow 80/tcp comment "HTTP" > /dev/null 2>&1 || true
        ufw allow 443/tcp comment "HTTPS" > /dev/null 2>&1 || true
        ufw allow 21/tcp comment "FTP" > /dev/null 2>&1 || true
        ufw allow 21000:21010/tcp comment "FTP Passive" > /dev/null 2>&1 || true
        
        # Enable firewall (non-interactive)
        echo "y" | ufw enable > /dev/null 2>&1 || true
        
        log_success "UFW konfigureret"
        
    elif command -v firewall-cmd &> /dev/null; then
        log_info "Konfigurerer firewalld..."
        
        firewall-cmd --permanent --add-service=ssh > /dev/null 2>&1 || true
        firewall-cmd --permanent --add-service=http > /dev/null 2>&1 || true
        firewall-cmd --permanent --add-service=https > /dev/null 2>&1 || true
        firewall-cmd --permanent --add-service=ftp > /dev/null 2>&1 || true
        firewall-cmd --reload > /dev/null 2>&1 || true
        
        log_success "Firewalld konfigureret"
    else
        log_warning "Ingen firewall fundet - installer manuelt"
    fi
}

################################################################################
# Start platform
################################################################################

start_platform() {
    log_step "STEP 10: Starter Hosting Platform"
    
    log_info "Skifter til kymacloud bruger..."
    
    # Verificer at platform directory findes
    if [ ! -d "$KYMA_HOME/platform" ]; then
        log_error "Platform directory findes ikke: $KYMA_HOME/platform"
        return 1
    fi
    
    # Start platform som kymacloud bruger (i baggrunden for at undgå pipe issues)
    log_info "Starter Docker services (dette kan tage et par minutter første gang)..."
    
    su - "$KYMA_USER" -c "cd $KYMA_HOME/platform && docker compose up -d" > /tmp/docker-compose-up.log 2>&1 &
    local compose_pid=$!
    
    # Vent på at compose processen er færdig
    log_info "Venter på Docker Compose (PID: $compose_pid)..."
    while kill -0 $compose_pid 2>/dev/null; do
        echo -n "."
        sleep 2
    done
    echo ""
    
    # Tjek exit code
    wait $compose_pid
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Docker Compose fejlede (exit code: $exit_code)"
        log_info "Log output:"
        cat /tmp/docker-compose-up.log | tail -30
        return 1
    fi
    
    log_success "Docker services startet"
    
    log_info "Venter på at services bliver healthy..."
    sleep 10
    
    # Verificer core services (not per-site PHP containers yet)
    local all_ok=true
    local core_services=("traefik" "nginx" "mariadb")
    
    log_info "Verificerer core services..."
    for service in "${core_services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            log_success "✓ $service kører"
        else
            log_warning "✗ $service kører IKKE"
            all_ok=false
        fi
    done
    
    # Check if any legacy shared PHP containers exist (from old installations)
    log_info "Tjekker for PHP containers..."
    if docker ps --format '{{.Names}}' | grep -q "php-fpm-"; then
        local php_count=$(docker ps --format '{{.Names}}' | grep -c "php-fpm-" || true)
        log_success "✓ $php_count PHP container(s) kører"
    else
        log_info "ℹ Ingen PHP containers endnu (oprettes per site)"
    fi
    
    if [ "$all_ok" = "true" ]; then
        log_success "Alle services kører korrekt"
        return 0
    else
        log_warning "Nogle services kører ikke - tjek med: docker compose ps"
        log_info "Se fuld log: /tmp/docker-compose-up.log"
        return 1
    fi
}

################################################################################
# Afslutning
################################################################################

show_completion() {
    local server_ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║              ✓ INSTALLATION COMPLETED                    ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo ""
    
    log_success "Kyma Hosting Platform v2.1 er installeret!"
    echo ""
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} NÆSTE SKRIDT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo "1. Log ind som kymacloud bruger:"
    echo -e "   ${YELLOW}ssh ${KYMA_USER}@${server_ip}${NC}"
    echo ""
    
    echo "2. Tilføj dit første website:"
    echo -e "   ${YELLOW}kyma site:add example.com php-fpm-82 wordpress${NC}"
    echo ""
    
    echo "3. Se system status:"
    echo -e "   ${YELLOW}kyma system:status${NC}"
    echo ""
    
    echo "4. Se alle tilgængelige kommandoer:"
    echo -e "   ${YELLOW}kyma --help${NC}"
    echo ""
    
    echo "5. Diagnosticer site efter oprettelse:"
    echo -e "   ${YELLOW}kyma diagnose:site example.com${NC}"
    echo ""
    
    echo "6. Se credentials for site:"
    echo -e "   ${YELLOW}kyma credentials:show example.com${NC}"
    echo ""
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} VIGTIG INFORMATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo "Organization ID: ${ORG_ID}"
    echo "Platform Path:   $KYMA_HOME/platform"
    echo "Sites Path:      $KYMA_HOME/organizations/org-${ORG_ID}/sites"
    echo ""
    echo "Platform Features:"
    echo "  ✓ 36 unified commands via 'kyma' interface"
    echo "  ✓ Per-site PHP containers (isolation & custom config)"
    echo "  ✓ Built-in diagnostics (kyma diagnose:*)"
    echo "  ✓ Comprehensive backup system (kyma backup:*)"
    echo "  ✓ Credentials management (kyma credentials:*)"
    echo "  ✓ JSON API support (--json flag)"
    echo ""
    
    echo -e "${YELLOW}⚠️  BACKUP .env filen til et sikkert sted!${NC}"
    echo ""
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo "Quick Reference: cat $KYMA_HOME/platform/QUICK_REFERENCE.md"
    echo "Full Docs:       cat $KYMA_HOME/platform/README.md"
    echo "Command Guide:   cat $KYMA_HOME/platform/COMMAND_SYSTEM.md"
    echo ""
    echo "Dokumentation:   https://docs.kymacloud.com"
    echo "Support:         support@kymacloud.com"
    echo ""
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    show_banner
    
    # Pre-flight checks
    validate_input
    
    # Installation steps
    fetch_organization_data
    install_dependencies
    install_docker
    setup_kyma_user
    setup_sudo_permissions
    setup_sftp_group
    setup_directory_structure
    copy_platform_files
    generate_configuration
    setup_firewall
    start_platform
    
    # Show completion
    show_completion
    
    log_success "Installation afsluttet!"
    exit 0
}

# Kør installation
main "$@"

