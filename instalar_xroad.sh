#!/bin/bash
# =============================================================================
# Instalación de X-Road Security Server v7.3.2
# Plataforma X-BA — GCBA / Agencia de Sistemas de Información
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
fail() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# =============================================================================
# ROLLBACK — se ejecuta automáticamente si algo falla
# =============================================================================
rollback() {
  echo ""
  warn "Ocurrió un error. Ejecutando rollback..."
  systemctl stop xroad-proxy xroad-proxy-ui-api xroad-confclient xroad-signer \
    xroad-monitor xroad-addon-messagelog xroad-base 2>/dev/null || true
  dnf remove -y xroad-securityserver xroad-base xroad-addon-opmonitoring \
    xroad-autologin 2>/dev/null || true
  rm -f /etc/yum.repos.d/xroad.repo
  rm -f /etc/xroad/conf.d/local.ini
  rm -f /etc/xroad/organismo.conf
  warn "Rollback completado. El servidor quedó en el estado anterior."
  warn "Revisá el error de arriba, corregilo y volvé a ejecutar el script."
  exit 1
}
trap rollback ERR

# =============================================================================
# FUNCIÓN PARA PREGUNTAR CON CONFIRMACIÓN
# =============================================================================
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
echo "  Instalación X-Road Security Server v7.3.2  "
echo "  Plataforma X-BA — GCBA                     "
echo "=============================================="

# =============================================================================
# 1. VERIFICAR ROOT
# =============================================================================
if [ "$EUID" -ne 0 ]; then
  fail "Este script debe ejecutarse como root: sudo bash instalar_xroad.sh"
fi

# =============================================================================
# 2. DATOS DEL ORGANISMO
# =============================================================================
echo ""
echo "--- Datos del organismo ---"
info "Estos datos son provistos por el equipo de X-BA del GCBA."
echo ""

# Ambiente
while true; do
  echo "  Seleccione el ambiente:"
  echo "  [1] HML - Homologación"
  echo "  [2] PRD - Producción"
  echo ""
  read -p "  Opción (1/2): " OPT </dev/tty
  case $OPT in
    1)
      AMBIENTE="hml"
      AMBIENTE_LABEL="HML - Homologación"
      CENTRAL_SERVER="xroad-central-hml.gcba.gob.ar"
      MSS_SERVER="xroad-mss-hml.gcba.gob.ar"
      break ;;
    2)
      AMBIENTE="prd"
      AMBIENTE_LABEL="PRD - Producción"
      CENTRAL_SERVER="xroad-central.buenosaires.gob.ar"
      MSS_SERVER="xroad-mss.buenosaires.gob.ar"
      break ;;
    *) warn "Opción inválida, ingrese 1 o 2." ; echo "" ;;
  esac
done
read -p "  Confirme ambiente [$AMBIENTE_LABEL] (s/n): " CONFIRM </dev/tty
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
  fail "Instalación cancelada. Volvé a ejecutar el script."
fi
ok "Ambiente: $AMBIENTE_LABEL"

preguntar "Member Class (dato provisto por X-BA, ej: GOB, JUS)" MEMBER_CLASS
MEMBER_CLASS=$(echo "$MEMBER_CLASS" | tr '[:lower:]' '[:upper:]')
ok "Member Class: $MEMBER_CLASS"

preguntar "Member Code (dato provisto por X-BA, ej: 001)" MEMBER_CODE
ok "Member Code: $MEMBER_CODE"

preguntar "Server Code (dato provisto por X-BA, ej: PRD001JUS)" SERVER_CODE
SERVER_CODE=$(echo "$SERVER_CODE" | tr '[:lower:]' '[:upper:]')
ok "Server Code: $SERVER_CODE"

# Resumen y confirmación final
echo ""
echo "=============================================="
echo "  Resumen de configuración"
echo "=============================================="
echo "  Ambiente        : $AMBIENTE_LABEL"
echo "  Central Server  : $CENTRAL_SERVER"
echo "  Member Class    : $MEMBER_CLASS"
echo "  Member Code     : $MEMBER_CODE"
echo "  Server Code     : $SERVER_CODE"
echo "=============================================="
echo ""
read -p "¿Los datos son correctos? ¿Desea continuar? (s/n): " CONFIRM </dev/tty
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
  fail "Instalación cancelada. Volvé a ejecutar el script."
fi

# =============================================================================
# 3. VERIFICACIONES DEL SISTEMA
# =============================================================================
echo ""
echo "--- Verificando requisitos del sistema ---"

# SO RHEL 8
if [ ! -f /etc/redhat-release ]; then
  fail "Este script requiere Red Hat Enterprise Linux 8."
fi
RHEL_MAJOR=$(grep -oP '\d+' /etc/redhat-release | head -1)
if [ "$RHEL_MAJOR" != "8" ]; then
  fail "Se requiere RHEL 8. Detectado: $(cat /etc/redhat-release)"
fi
ok "SO: $(cat /etc/redhat-release)"

# RAM mínimo 4 GB
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [ "$RAM_MB" -lt 3800 ]; then
  fail "RAM insuficiente: ${RAM_MB} MB. Se requieren al menos 4 GB."
fi
ok "RAM: ${RAM_MB} MB"

# Disco mínimo 60 GB
DISK_GB=$(df / | awk 'NR==2{printf "%d", $4/1024/1024}')
if [ "$DISK_GB" -lt 5 ]; then
  fail "Espacio insuficiente: ${DISK_GB} GB libres. Se requieren al menos 60 GB."
fi
ok "Disco: ${DISK_GB} GB libres"

# =============================================================================
# 4. VERIFICACIONES DE CONECTIVIDAD
# =============================================================================
echo ""
echo "--- Verificando conectividad ---"

# Salida a internet
if ! curl -s --max-time 10 https://artifactory.niis.org > /dev/null; then
  fail "Sin acceso al repositorio de X-Road (artifactory.niis.org). El servidor necesita salida a internet."
fi
ok "Salida a internet OK"

# Central Server puerto 4001 y 80
for PUERTO in 4001 80; do
  if nc -zw5 "$CENTRAL_SERVER" "$PUERTO" 2>/dev/null; then
    ok "Conectividad a $CENTRAL_SERVER:$PUERTO OK"
  else
    warn "Sin conectividad a $CENTRAL_SERVER:$PUERTO. Solicitá la apertura del puerto a la mesa de ayuda antes de continuar."
  fi
done

# MSS puertos 5500 y 5577
for PUERTO in 5500 5577; do
  if nc -zw5 "$MSS_SERVER" "$PUERTO" 2>/dev/null; then
    ok "Conectividad a $MSS_SERVER:$PUERTO OK"
  else
    warn  "Sin conectividad a $MSS_SERVER:$PUERTO. Solicitá la apertura del puerto a la mesa de ayuda antes de continuar."
  fi
done

# Puertos locales libres
for PUERTO in 80 443 4000 5500 5577 8080; do
  if ss -tlnp | grep -q ":${PUERTO} "; then
    warn "Puerto ${PUERTO} ya está en uso. Puede generar conflictos."
  else
    ok "Puerto ${PUERTO} disponible"
  fi
done

# =============================================================================
# 5. PREPARAR OS
# =============================================================================
echo ""
echo "--- Preparando sistema operativo ---"

# Configurar locale
if ! grep -q "LC_ALL=en_US.UTF-8" /etc/environment 2>/dev/null; then
  echo "LC_ALL=en_US.UTF-8" >> /etc/environment
fi
export LC_ALL=en_US.UTF-8
ok "Locale configurado (LC_ALL=en_US.UTF-8)"

# Instalar yum-utils
dnf install -y yum-utils nc 2>&1 | tail -3
ok "yum-utils instalado"

# =============================================================================
# 6. REPOSITORIOS
# =============================================================================
echo ""
echo "--- Configurando repositorios ---"

# EPEL
RHEL_MAJOR_VERSION=$(source /etc/os-release; echo ${VERSION_ID%.*})
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-${RHEL_MAJOR_VERSION}.noarch.rpm 2>&1 | tail -3
ok "Repositorio EPEL configurado"

# X-Road 7.3.2
yum-config-manager --add-repo https://artifactory.niis.org/xroad-release-rpm/rhel/${RHEL_MAJOR_VERSION}/7.3.2/ 2>&1 | tail -3
rpm --import https://artifactory.niis.org/api/gpg/key/public
ok "Repositorio X-Road 7.3.2 configurado"

# =============================================================================
# 7. INSTALACIÓN
# =============================================================================
echo ""
echo "--- Instalando X-Road Security Server ---"
echo "    (esto puede tardar unos minutos)"
echo ""

dnf install -y xroad-securityserver 2>&1 | tail -5
ok "xroad-securityserver instalado"

dnf install -y xroad-addon-opmonitoring 2>&1 | tail -3
ok "xroad-addon-opmonitoring instalado"

dnf install -y xroad-autologin 2>&1 | tail -3
ok "xroad-autologin instalado"

# =============================================================================
# 8. CONFIGURAR local.ini
# =============================================================================
echo ""
echo "--- Aplicando configuración ---"

mkdir -p /etc/xroad/conf.d

cat > /etc/xroad/conf.d/local.ini << INI
[proxy]
client-http-port=80
client-https-port=443

[proxy-ui-api]
server-port=4000
INI

chown xroad:xroad /etc/xroad/conf.d/local.ini
chmod 640 /etc/xroad/conf.d/local.ini
ok "local.ini configurado (puertos 80/443)"

# Guardar datos del organismo
cat > /etc/xroad/organismo.conf << CONF
AMBIENTE=$AMBIENTE
MEMBER_CLASS=$MEMBER_CLASS
MEMBER_CODE=$MEMBER_CODE
SERVER_CODE=$SERVER_CODE
CENTRAL_SERVER=$CENTRAL_SERVER
MSS_SERVER=$MSS_SERVER
CONF
ok "Datos del organismo guardados en /etc/xroad/organismo.conf"

# =============================================================================
# 9. FIREWALL
# =============================================================================
echo ""
echo "--- Configurando firewall ---"

if systemctl is-active firewalld &>/dev/null; then
  for PUERTO in 80/tcp 443/tcp 4000/tcp 5500/tcp 5577/tcp 8080/tcp; do
    firewall-cmd --zone=public --add-port=$PUERTO --permanent 2>/dev/null
    ok "Puerto $PUERTO habilitado en firewall"
  done
  firewall-cmd --reload 2>/dev/null
else
  warn "firewalld no está activo. Verificá manualmente que los puertos estén abiertos."
fi

# =============================================================================
# 10. SERVICIOS
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

systemctl daemon-reload

# =============================================================================
# 11. PRUEBA DE FUNCIONAMIENTO
# =============================================================================
echo ""
echo "--- Verificando funcionamiento ---"

sleep 8

HTTP_CODE=$(curl -sk --max-time 15 https://localhost:4000 -o /dev/null -w "%{http_code}")
if echo "$HTTP_CODE" | grep -qE "200|302|401"; then
  ok "UI de X-Road respondiendo en puerto 4000 (HTTP $HTTP_CODE)"
else
  warn "La UI no responde en puerto 4000. Revisá: systemctl status xroad-proxy-ui-api"
fi

if ss -tlnp | grep -q ":5500 "; then
  ok "Puerto externo 5500 escuchando"
else
  warn "Puerto 5500 no está escuchando. Revisá: systemctl status xroad-proxy"
fi

echo ""
echo "--- Estado de servicios ---"
for SERVICIO in "${SERVICIOS[@]}"; do
  STATUS=$(systemctl is-active "$SERVICIO" 2>/dev/null)
  if [ "$STATUS" == "active" ]; then
    ok "$SERVICIO: activo"
  else
    warn "$SERVICIO: $STATUS"
  fi
done

# =============================================================================
# RESUMEN FINAL
# =============================================================================
IP_SERVIDOR=$(hostname -I | awk '{print $1}')
FECHA=$(date '+%d/%m/%Y %H:%M:%S')

echo ""
echo "=============================================="
echo -e "${GREEN}  Instalación completada correctamente${NC}"
echo "=============================================="
echo ""
echo "  Fecha           : $FECHA"
echo "  Hostname        : $(hostname)"
echo "  IP              : $IP_SERVIDOR"
echo "  Ambiente        : $AMBIENTE_LABEL"
echo "  Central Server  : $CENTRAL_SERVER"
echo "  Member Class    : $MEMBER_CLASS"
echo "  Member Code     : $MEMBER_CODE"
echo "  Server Code     : $SERVER_CODE"
echo "  URL de admin    : https://${IP_SERVIDOR}:4000"
echo ""
echo "  PASOS MANUALES PENDIENTES:"
echo "  1. Acceder a la UI: https://${IP_SERVIDOR}:4000"
echo "  2. Cargar el Anchor File (provisto por X-BA)"
echo "  3. Ingresar Member Class, Member Code y Server Code"
echo "  4. Configurar PIN del Signer (guardarlo, no se puede cambiar)"
echo "  5. Generar keys AUTH y SIGN (formato DER), exportar CSR"
echo "  6. Enviar los CSR a Seguridad Informática de ASI para firma"
echo "  7. Importar los certificados firmados (.PEM) desde la UI"
echo "  8. Registrar el certificado AUTH con la IP/DNS del SS"
echo "  9. Configurar Timestamping: Settings > System Parameters"
echo "     (Para SS externos usar *.buenosaires.gob.ar, NO GCBA-TSU01)"
echo " 10. Esperar aprobación del Management Request (aprox. 5 min)"
echo ""
echo "  *** Enviá el contenido completo de esta pantalla"
echo "  *** al equipo de X-BA para validar la instalación."
echo "=============================================="
