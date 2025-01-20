#!/bin/bash

# ===============================
# Instalador Automático de BIND9
# ===============================
# Autor: Linoreki
# Descripción: Script interactivo para instalar y configurar BIND9 en Ubuntu Server

# Colores para la terminal
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

# Función para manejar errores
error_exit() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Función para realizar copias de seguridad
backup_file() {
    if [[ -f "$1" ]]; then
        cp "$1" "$1.bak" || error_exit "No se pudo crear la copia de seguridad de $1"
    fi
}

# Verificar permisos
if [[ $EUID -ne 0 ]]; then
    error_exit "Este script debe ejecutarse como root. Usa sudo."
fi

# Menú de configuración avanzada
configure_dns_records() {
    while true; do
        echo "----- Configuración de Registros DNS -----"
        echo "1) Añadir Registro A"
        echo "2) Añadir Registro PTR"
        echo "3) Añadir Registro CNAME"
        echo "4) Añadir Registro MX"
        echo "5) Salir"
        read -p "Seleccione una opción: " OPTION

        case $OPTION in
            1)
                read -p "Ingrese el nombre del host: " HOSTNAME
                read -p "Ingrese la dirección IP: " HOST_IP
                backup_file "/etc/bind/db.${DOMAIN}"
                echo "$HOSTNAME IN A $HOST_IP" >> /etc/bind/db.${DOMAIN}
                named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN} || error_exit "Error en la configuración del registro A"
                echo "Registro A añadido."
                ;;
            2)
                read -p "Ingrese la dirección IP: " PTR_IP
                read -p "Ingrese el nombre del host: " PTR_HOST
                backup_file "/etc/bind/db.${REVERSE_NET}"
                echo "$(echo $PTR_IP | awk -F. '{print $4}') IN PTR $PTR_HOST." >> /etc/bind/db.${REVERSE_NET}
                named-checkzone ${REVERSE_NET}.in-addr.arpa /etc/bind/db.${REVERSE_NET} || error_exit "Error en la configuración del registro PTR"
                echo "Registro PTR añadido."
                ;;
            3)
                read -p "Ingrese el alias: " ALIAS
                read -p "Ingrese el nombre canónico: " CANONICAL
                backup_file "/etc/bind/db.${DOMAIN}"
                echo "$ALIAS IN CNAME $CANONICAL." >> /etc/bind/db.${DOMAIN}
                named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN} || error_exit "Error en la configuración del registro CNAME"
                echo "Registro CNAME añadido."
                ;;
            4)
                read -p "Ingrese la prioridad MX: " MX_PRIORITY
                read -p "Ingrese el servidor de correo: " MX_SERVER
                backup_file "/etc/bind/db.${DOMAIN}"
                echo "@ IN MX $MX_PRIORITY $MX_SERVER." >> /etc/bind/db.${DOMAIN}
                named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN} || error_exit "Error en la configuración del registro MX"
                echo "Registro MX añadido."
                ;;
            5)
                break
                ;;
            *)
                echo "Opción no válida."
                ;;
        esac
    done
}

# Instalador de BIND9
install_bind9() {
    read -p "Ingrese el dominio (ej: midominio.com): " DOMAIN
    read -p "Ingrese el hostname del servidor: " HOSTNAME
    read -p "Ingrese la IP del servidor DNS: " DNS_IP
    read -p "Ingrese la red inversa (ej: 1.168.192): " REVERSE_NET

    echo -e "${YELLOW}Instalando BIND9...${NC}"
    apt update && apt install -y bind9 bind9-utils bind9-doc || error_exit "Fallo al instalar BIND9."
    
    echo -e "${YELLOW}Configurando BIND9...${NC}"
    backup_file "/etc/bind/named.conf.local"
    cat > /etc/bind/named.conf.local <<EOL
zone "${DOMAIN}" {
    type master;
    file "/etc/bind/db.${DOMAIN}";
};

zone "${REVERSE_NET}.in-addr.arpa" {
    type master;
    file "/etc/bind/db.${REVERSE_NET}";
};
EOL

    backup_file "/etc/bind/db.${DOMAIN}"
    cat > /etc/bind/db.${DOMAIN} <<EOL
\$TTL 604800
@   IN  SOA ${HOSTNAME}.${DOMAIN}. root.${DOMAIN}. (
        2025011601 ; Serial
        604800     ; Refresh
        86400      ; Retry
        2419200    ; Expire
        604800 )   ; Negative Cache TTL

@       IN  NS      ${HOSTNAME}.${DOMAIN}.
${HOSTNAME}    IN  A       ${DNS_IP}
EOL

    backup_file "/etc/bind/db.${REVERSE_NET}"
    cat > /etc/bind/db.${REVERSE_NET} <<EOL
\$TTL 604800
@   IN  SOA ${HOSTNAME}.${DOMAIN}. root.${DOMAIN}. (
        2025011601 ; Serial
        604800     ; Refresh
        86400      ; Retry
        2419200    ; Expire
        604800 )   ; Negative Cache TTL

@       IN  NS      ${HOSTNAME}.${DOMAIN}.
$(echo ${DNS_IP} | awk -F. '{print $4}')      IN  PTR     ${HOSTNAME}.${DOMAIN}.
EOL

    named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN} || error_exit "Error en la configuración del archivo de zona directa"
    named-checkzone ${REVERSE_NET}.in-addr.arpa /etc/bind/db.${REVERSE_NET} || error_exit "Error en la configuración del archivo de zona inversa"

    systemctl restart bind9 && systemctl enable bind9 || error_exit "Fallo al reiniciar BIND9."
    echo -e "${GREEN}BIND9 instalado y configurado correctamente.${NC}"
}

# Verificar argumentos
if [[ "$1" == "-c" ]]; then
    configure_dns_records
    exit 0
elif [[ "$1" == "-i" ]]; then
    install_bind9
    exit 0
else
    echo "Uso: $0 [-c para configurar registros] [-i para instalar BIND9]"
    exit 1
fi
