#!/bin/bash
# =============================================================================
# Instalación de X-Road Security Server
# Plataforma X-BA — GCBA
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

preguntar() {
  local LABEL=$1
  local VARNAME=$2
  local VALOR=""
  while true; do
    echo ""
    read -p "  Ingrese $LABEL: " VALOR </dev/tty
    if [ -z "$VALOR" ]; then
      warn "El campo no puede estar vacío."
      continue
    fi
    read -p "  Confirme $LABEL [${VALOR}] (s/n): " CONFIRM </dev/tty
    if [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]]; then
      eval "$VARNAME='$VALOR'"
      break
    else
      warn "Volviendo a ingresar $LABEL..."
    fi
  done
}

echo ""
echo "=============================================="
echo "  Instalación X-Road Security Server - X-BA  "
echo "=============================================="

# =============================================================================
# 1. DATOS DEL ORGANISMO
# =============================================================================
echo ""
echo "--- Datos del organismo ---"
info "Estos datos son provistos por el equipo de X-BA del GCBA."
echo ""

# Ambiente — selección fija
while true; do
  echo "  Seleccione el ambiente:"
  echo "  [1] HML - Homologación"
  echo "  [2] PRD - Producción"
  echo ""
  read -p "  Opción (1/2): " OPT </dev/tty
  case $OPT in
    1) AMBIENTE="hml"; AMBIENTE_LABEL="HML - Homologación"; break ;;
    2) AMBIENTE="prd"; AMBIENTE_LABEL="PRD - Producción"; break ;;
    *) warn "Opción inválida, ingrese 1 o 2." ; echo "" ;;
  esac
done
read -p "  Confirme ambiente [$AMBIENTE_LABEL] (s/n): " CONFIRM </dev/tty
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
  fail "Instalación cancelada. Volvé a ejecutar el script."
fi
ok "Ambiente: $AMBIENTE_LABEL"

# Member Class — texto libre
preguntar "Member Class (dato provisto por X-BA)" MEMBER_CLASS
MEMBER_CLASS=$(echo "$MEMBER_CLASS" | tr '[:lower:]' '[:upper:]')
ok "Member Class: $MEMBER_CLASS"

# Member Code — texto libre
preguntar "Member Code (dato provisto por X-BA)" MEMBER_CODE
ok "Member Code: $MEMBER_CODE"

# Server Code — texto libre
preguntar "Server Code (dato provisto por X-BA)" SERVER_CODE
SERVER_CODE=$(echo "$SERVER_CODE" | tr '[:lower:]' '[:upper:]')
ok "Server Code: $SERVER_CODE"

# Resumen final
echo ""
echo "=============================================="
echo "  Resumen de configuración"
echo "=============================================="
echo "  Ambiente     : $AMBIENTE_LABEL"
echo "  Member Class : $MEMBER_CLASS"
echo "  Member Code  : $MEMBER_CODE"
echo "  Server Code  : $SERVER_CODE"
echo "=============================================="
echo ""
read -p "¿Los datos son correctos? ¿Desea continuar con la instalación? (s/n): " CONFIRM </dev/tty
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
  fail "Instalación cancelada. Volvé a ejecutar el script."
fi

# =============================================================================
# 2. VERIFICACIONES PREVIAS
# =============================================================================
echo ""
echo "--- Verificando requisitos del sistema ---"

if [ "$EUID" -ne 0 ]; then
  fail "Este script debe ejecutarse como root. Usá: sudo bash instalar_xroad.sh"
fi

if [ ! -f /etc/redhat-release ]; then
  fail "Este script requiere Red Hat Enterprise Linux 8."
fi
RHEL_VERSION=$(cat /etc/redhat-release)
ok "SO: $RHEL_VERSION"

RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [ "$RAM_MB" -lt 3800 ]; then
  fail "RAM insuficiente: ${RAM_MB} MB. Se requieren al menos 4 GB."
fi
ok "RAM: ${RAM_MB} MB"

DISK_GB=$(df / | awk 'NR==2{printf "%d", $4/1024/1024}')
if [ "$DISK_GB" -lt 5 ]; then
  fail "Espacio insuficiente: ${DISK_GB} GB libres. Se requieren al menos 60 GB."
fi
ok "Disco: ${DISK_GB} GB libres"

echo ""
echo "--- Verificando conectividad ---"
if ! curl -s --max-time 10 https://artifactory.niis.org > /dev/null; then
  fail "Sin acceso al repositorio de X-Road (artifactory.niis.org). Verificá que el servidor tenga salida a internet."
fi
ok "Conectividad al repositorio de X-Road OK"

# =============================================================================
# 3. REPOSITORIO DE X-ROAD
# =============================================================================
echo ""
echo "--- Configurando repositorio de X-Road ---"

cat > /etc/yum.repos.d/xroad.repo << 'REPO'
[xroad]
name=X-Road Security Server
baseurl=https://artifactory.niis.org/xroad-release-rpm/rhel/8/current
enabled=1
gpgcheck=1
gpgkey=https://artifactory.niis.org/api/gpg/key/public
REPO

ok "Repositorio configurado"

# =============================================================================
# 4. INSTALACIÓN
# =============================================================================
echo ""
echo "--- Instalando X-Road Security Server ---"
echo "    (esto puede tardar unos minutos)"
echo ""

dnf install -y xroad-securityserver 2>&1 | tail -5

ok "X-Road Security Server instalado"

# =============================================================================
# 5. CONFIGURACIÓN
# =============================================================================
echo ""
echo "--- Aplicando configuración ---"

mkdir -p /etc/xroad/conf.d

cat > /etc/xroad/conf.d/local.ini << INI
[proxy]
connector-host=0.0.0.0
client-connector-port=8080
ocsp-responder-port=5577

[proxy-ui-api]
server-port=4000
INI

chown xroad:xroad /etc/xroad/conf.d/local.ini
chmod 640 /etc/xroad/conf.d/local.ini
ok "local.ini configurado"

cat > /etc/xroad/organismo.conf << CONF
AMBIENTE=$AMBIENTE
MEMBER_CLASS=$MEMBER_CLASS
MEMBER_CODE=$MEMBER_CODE
SERVER_CODE=$SERVER_CODE
CONF
ok "Datos del organismo guardados en /etc/xroad/organismo.conf"

# =============================================================================
# 6. SERVICIOS
# =============================================================================
echo ""
echo "--- Iniciando servicios ---"

SERVICIOS=(
  xroad-signer
  xroad-base
  xroad-confclient
  xroad-proxy
  xroad-proxy-ui-api
  xroad-monitor
  xroad-addon-messagelog
)

for SERVICIO in "${SERVICIOS[@]}"; do
  systemctl enable "$SERVICIO" --now 2>/dev/null && ok "$SERVICIO" || warn "$SERVICIO no pudo iniciarse"
done

# =============================================================================
# 7. PRUEBA DE FUNCIONAMIENTO
# =============================================================================
echo ""
echo "--- Verificando funcionamiento ---"

sleep 5

if curl -sk --max-time 10 https://localhost:4000 -o /dev/null -w "%{http_code}" | grep -qE "200|302|401"; then
  ok "UI de X-Road respondiendo en puerto 4000"
else
  warn "La UI no responde todavía. Puede que los servicios necesiten unos segundos más."
fi

# =============================================================================
# RESUMEN FINAL
# =============================================================================
IP_SERVIDOR=$(hostname -I | awk '{print $1}')

echo ""
echo "=============================================="
echo -e "${GREEN}  Instalación completada correctamente${NC}"
echo "=============================================="
echo ""
echo "  Organismo    : $MEMBER_CLASS - $MEMBER_CODE"
echo "  Server Code  : $SERVER_CODE"
echo "  Ambiente     : $AMBIENTE_LABEL"
echo "  URL de admin : https://${IP_SERVIDOR}:4000"
echo ""
echo "  PASOS MANUALES PENDIENTES:"
echo "  1. Cargar el Anchor desde la UI"
echo "  2. Configurar el PIN del Signer"
echo "  3. Generar keys AUTH y SIGN"
echo "  4. Enviar los CSR para firma"
echo "  5. Configurar Timestamping"
echo "  6. Esperar aprobación del Management Request"
echo ""
echo "  Enviá el contenido de esta pantalla al equipo"
echo "  de X-BA para validar la instalación."
echo "=============================================="
