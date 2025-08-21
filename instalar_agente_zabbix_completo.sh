#!/bin/bash

# ===================================================================================
# Script Definitivo para Instalação/Migração do Zabbix Agent 2 em Sistemas Debian
#
# Funcionalidades:
# 1. Limpeza Completa: Remove versões antigas do zabbix-agent e zabbix-agent2.
# 2. Instalação do Repositório Zabbix 7.0 LTS.
# 3. Instalação do Zabbix Agent 2.
# 4. Configuração Automática do IP do Servidor e do Hostname da máquina.
# 5. Inicialização e verificação do serviço.
# ===================================================================================

set -e

# --- VARIÁVEIS DE CONFIGURAÇÃO ---
ZABBIX_SERVER_IP="192.168.4.11"
ZABBIX_HOSTNAME=$(hostname)

# --- CORES PARA O OUTPUT ---
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Sem Cor

echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}  Iniciando Instalação/Migração do Zabbix Agent 2      ${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo -e "${AMARELO}Servidor Zabbix a ser configurado: ${NC}$ZABBIX_SERVER_IP"
echo -e "${AMARELO}Hostname do Agente a ser configurado:    ${NC}$ZABBIX_HOSTNAME"


# --- PASSO 1: LIMPEZA COMPLETA DE VERSÕES ANTERIORES ---
echo -e "\n${AMARELO}[PASSO 1/5] Limpeza completa de instalações anteriores...${NC}"

# Para o serviço do zabbix-agent2 se estiver rodando
if systemctl list-units --type=service | grep -q 'zabbix-agent2.service'; then
    echo "--> Parando serviço zabbix-agent2 existente..."
    systemctl stop zabbix-agent2
fi
# Para o serviço do zabbix-agent (clássico) se estiver rodando
if systemctl list-units --type=service | grep -q 'zabbix-agent.service'; then
    echo "--> Parando serviço zabbix-agent (clássico) existente..."
    systemctl stop zabbix-agent
fi

# Remove todos os pacotes zabbix-agent2 e seus plugins
echo "--> Verificando pacotes 'zabbix-agent2'..."
if dpkg -l | grep -q "zabbix-agent2"; then
    echo "--> Removendo pacotes 'zabbix-agent2*' existentes..."
    apt-get remove --purge -y "zabbix-agent2*"
else
    echo "--> Nenhum pacote 'zabbix-agent2' encontrado."
fi

# Remove o pacote zabbix-agent (clássico)
echo "--> Verificando pacotes 'zabbix-agent' (clássico)..."
if dpkg -l | grep -q "zabbix-agent "; then # Espaço no final para evitar match com agent2
     echo "--> Removendo pacotes 'zabbix-agent' existentes..."
     apt-get remove --purge -y zabbix-agent
else
     echo "--> Nenhum pacote 'zabbix-agent' (clássico) encontrado."
fi

echo "--> Limpando dependências não utilizadas..."
apt-get autoremove -y
echo -e "${VERDE}Limpeza concluída com sucesso.${NC}"


# --- PASSO 2: INSTALAR O REPOSITÓRIO DO ZABBIX 7.0 LTS ---
echo -e "\n${AMARELO}[PASSO 2/5] Configurando o repositório do Zabbix 7.0 LTS...${NC}"
# Lógica de detecção do repositório... (mantida a mesma)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    VERSION_ID_MAJOR=$(echo $VERSION_ID | cut -d. -f1)
    REPO_URL=""
    if [ "$ID" == "debian" ]; then
        case "$VERSION_ID_MAJOR" in
            "12") REPO_URL="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-1+debian12_all.deb";;
            "11") REPO_URL="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-1+debian11_all.deb";;
        esac
    fi
    if [ -z "$REPO_URL" ]; then echo "Sistema operacional Debian não suportado."; exit 1; fi
    wget "$REPO_URL" -O /tmp/zabbix-release.deb
    dpkg -i /tmp/zabbix-release.deb
    rm /tmp/zabbix-release.deb
    apt-get update
    echo -e "${VERDE}Repositório Zabbix configurado.${NC}"
else
    echo "Não foi possível detectar a distribuição do sistema."; exit 1
fi


# --- PASSO 3: INSTALAR O ZABBIX AGENT 2 ---
echo -e "\n${AMARELO}[PASSO 3/5] Instalando o Zabbix Agent 2...${NC}"
apt-get install -y zabbix-agent2
echo -e "${VERDE}Zabbix Agent 2 instalado com sucesso.${NC}"


# --- PASSO 4: CONFIGURAR O IP E HOSTNAME AUTOMATICAMENTE ---
echo -e "\n${AMARELO}[PASSO 4/5] Configurando o arquivo zabbix_agent2.conf...${NC}"
CONF_FILE="/etc/zabbix/zabbix_agent2.conf"
sed -i "s/^Server=127.0.0.1/Server=${ZABBIX_SERVER_IP}/" "$CONF_FILE"
sed -i "s/^# ServerActive=127.0.0.1/ServerActive=${ZABBIX_SERVER_IP}/" "$CONF_FILE"
# Comando sed aprimorado para ser mais robusto
sed -i "s/^# Hostname=.*/Hostname=${ZABBIX_HOSTNAME}/" "$CONF_FILE"
echo -e "${VERDE}Arquivo de configuração atualizado com o IP do servidor e o hostname da máquina.${NC}"


# --- PASSO 5: HABILITAR E INICIAR O SERVIÇO ---
echo -e "\n${AMARELO}[PASSO 5/5] Habilitando e reiniciando o serviço do Zabbix Agent 2...${NC}"
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
sleep 2 
systemctl status zabbix-agent2 --no-pager

echo -e "\n\n${VERDE}====================================================="
echo -e "      PROCESSO DE INSTALAÇÃO CONCLUÍDO!"
echo -e "=====================================================${NC}"
echo -e "\n${AMARELO}### VERIFICAÇÃO FINAL! ###"
echo -e "O script configurou o Hostname automaticamente para: ${CYAN}${ZABBIX_HOSTNAME}${NC}"
echo -e "\n${AMARELO}GARANTA que este nome seja ${NC}EXATAMENTE IGUAL${AMARELO} ao nome do host cadastrado na interface web do Zabbix."
echo -e "Se o nome estiver diferente, edite o arquivo ${NC}/etc/zabbix/zabbix_agent2.conf${AMARELO} e reinicie o serviço com:"
echo -e "${NC}sudo systemctl restart zabbix-agent2${NC}\n"
