#!/bin/bash
# =============================================================================
# Instalación de X-Road Security Server
# Plataforma X-BA — GCBA
# =============================================================================

set -e

# Colores para el output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "=============================================="
echo "  Instalación X-Road Security Server - X-BA  "
echo "=============================================="
echo ""

# =============================================================================
# 1. VERIFICACIONES PREVIAS
# =============================================================================
echo "--- Verificando requisitos del sistema ---"

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then
  fail "Este script debe ejecutarse como root. Usá: sudo bash instalar_xroad.sh"
fi

# Verificar SO
if [ ! -f /etc/redhat-release ]; then
  fail "Este script requiere Red Hat Enterprise Linux 8."
fi
RHEL_VERSION=$(cat /etc/redhat-release)
ok "SO: $RHEL_VERSION"

# Verificar RAM (mínimo 4 GB)
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [ "$RAM_MB" -lt 3800 ]; then
  fail "RAM insuficiente: ${RAM_MB} MB. Se requieren al menos 4 GB."
fi
ok "RAM: ${RAM_MB} MB"

# Verificar espacio en disco (mínimo 60 GB)
DISK_GB=$(df / | awk 'NR==2{printf "%d", $4/1024/1024}')
if [ "$DISK_GB" -lt 60 ]; then
  fail "Espacio insuficiente: ${DISK_GB} GB libres en /. Se requieren al menos 60 GB."
fi
ok "Disco: ${DISK_GB} GB libres"

# Verificar conectividad al repositorio de X-Road
echo ""
echo "--- Verificando conectividad ---"
if ! curl -s --max-time 10 https://artifactory.niis.org > /dev/null; then
  fail "Sin acceso al repositorio de X-Road (artifactory.niis.org). Verificá que el servidor tenga salida a internet."
fi
ok "Conectividad al repositorio de X-Road OK"

# =============================================================================
# 2. AGREGAR REPOSITORIO DE X-ROAD
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
# 3. INSTALAR X-ROAD SECURITY SERVER
# =============================================================================
echo ""
echo "--- Instalando X-Road Security Server ---"
echo "    (esto puede tardar unos minutos)"
echo ""

dnf install -y xroad-securityserver 2>&1 | tail -5

ok "X-Road Security Server instalado"

# =============================================================================
# 4. CONFIGURAR local.ini
# =============================================================================
echo ""
echo "--- Aplicando configuración ---"

mkdir -p /etc/xroad/conf.d

cat > /etc/xroad/conf.d/local.ini << 'INI'
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

# =============================================================================
# 5. HABILITAR Y ARRANCAR SERVICIOS
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
# 6. PRUEBA DE FUNCIONAMIENTO
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
echo "  URL de administración:"
echo "  → https://${IP_SERVIDOR}:4000"
echo ""
echo "  PASOS MANUALES PENDIENTES:"
echo "  1. Cargar el Anchor desde la UI"
echo "  2. Configurar el PIN del Signer"
echo "  3. Generar keys AUTH y SIGN"
echo "  4. Enviar los CSR para firma"
echo "  5. Configurar Timestamping"
echo "  6. Esperar aprobación del Management Request"
echo ""
echo "  Enviá el contenido de esta pantalla al equipo de X-BA"
echo "  para validar la instalación."
echo "=============================================="
