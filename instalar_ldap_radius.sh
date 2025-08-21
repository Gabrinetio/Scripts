#!/bin/bash

# ==============================================================================
# Script para Instalação e Configuração Automática do OpenLDAP e FreeRADIUS
#
# SO Testado: Debian 11/12, Ubuntu 20.04/22.04
# Autor: Gemini (Personalizado para GabrielTI)
#
# Execute como root ou com sudo: sudo bash ./instalar_ldap_radius.sh
# ==============================================================================

# Saia imediatamente se um comando falhar
set -e

# --- [ PARTE 1: CONFIGURAÇÕES - PERSONALIZADO ] -------------------------------

# Senha para o administrador do OpenLDAP (ex: cn=admin,dc=gti,dc=local)
LDAP_ADMIN_PASSWORD="Mho@0730"

# Domínio base para o LDAP.
LDAP_DC1="gti"
LDAP_DC2="local"

# Nome da sua organização
LDAP_ORGANIZATION="GabrielTI"

# Senha para o usuário de 'bind' que o FreeRADIUS usará para consultar o LDAP
RADIUS_LDAP_BIND_PASSWORD="88221237"

# Rede e segredo compartilhado para clientes RADIUS
RADIUS_CLIENT_IP="192.168.4.0/24"
RADIUS_CLIENT_SECRET="Mgo@2701"

# Usuário de teste que será criado no LDAP
TEST_USER_NAME="atom.ti"
TEST_USER_PASSWORD="88221237"

# --- [ FIM DAS CONFIGURAÇÕES ] ------------------------------------------------

# Derivações automáticas (não edite)
LDAP_BASE_DN="dc=${LDAP_DC1},dc=${LDAP_DC2}"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASE_DN}"

# --- [ PARTE 2: FUNÇÕES DO SCRIPT ] -------------------------------------------

# Função para verificar se o script está sendo executado como root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Este script precisa ser executado como root. Use 'sudo bash $0'"
        exit 1
    fi
}

# Função para instalar os pacotes necessários
install_packages() {
    echo "================================================="
    echo "=> Atualizando repositórios e instalando pacotes..."
    echo "================================================="
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y slapd ldap-utils freeradius freeradius-ldap
}

# Função para configurar o OpenLDAP de forma não interativa
configure_openldap() {
    echo "================================================="
    echo "=> Configurando o OpenLDAP..."
    echo "================================================="

    # Pré-configura as respostas do debconf para a instalação do slapd
    echo "slapd slapd/root_password password ${LDAP_ADMIN_PASSWORD}" | debconf-set-selections
    echo "slapd slapd/root_password_again password ${LDAP_ADMIN_PASSWORD}" | debconf-set-selections
    echo "slapd slapd/domain string ${LDAP_DC1}.${LDAP_DC2}" | debconf-set-selections
    echo "slapd slapd/organization string ${LDAP_ORGANIZATION}" | debconf-set-selections
    
    # Reconfigura o slapd com as novas senhas e configurações
    dpkg-reconfigure -f noninteractive slapd

    # Gerando senha hasheada para o usuário de bind do RADIUS
    HASHED_RADIUS_BIND_PASSWORD=$(slappasswd -s "${RADIUS_LDAP_BIND_PASSWORD}")

    # Criando arquivos LDIF para a estrutura básica e usuários
    cat <<EOF > /tmp/base_structure.ldif
dn: ou=people,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: people

dn: ou=groups,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: groups

dn: uid=radius,ou=people,${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: person
objectClass: top
cn: Radius Bind User
sn: BindUser
uid: radius
userPassword: ${HASHED_RADIUS_BIND_PASSWORD}

dn: uid=${TEST_USER_NAME},ou=people,${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: person
objectClass: top
cn: ${TEST_USER_NAME}
sn: TI
uid: ${TEST_USER_NAME}
userPassword: ${TEST_USER_PASSWORD}
EOF

    echo "=> Adicionando estrutura base (OUs people, groups) e usuários ao LDAP..."
    # A opção -c continua mesmo se uma entrada já existir
    ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/base_structure.ldif -c || echo "Aviso: Algumas entradas LDIF podem já existir."
    
    rm /tmp/base_structure.ldif
}

# Função para configurar o FreeRADIUS para usar o LDAP
configure_freeradius() {
    echo "================================================="
    echo "=> Configurando o FreeRADIUS..."
    echo "================================================="
    
    # 1. Configurar o módulo LDAP (/etc/freeradius/3.0/mods-available/ldap)
    LDAP_MOD_FILE="/etc/freeradius/3.0/mods-available/ldap"
    sed -i "s|server = .*|server = \"ldap://localhost\"|" ${LDAP_MOD_FILE}
    sed -i "s|identity = .*|identity = \"uid=radius,ou=people,${LDAP_BASE_DN}\"|" ${LDAP_MOD_FILE}
    sed -i "s|password = .*|password = \"${RADIUS_LDAP_BIND_PASSWORD}\"|" ${LDAP_MOD_FILE}
    sed -i "s|base_dn = .*|base_dn = \"ou=people,${LDAP_BASE_DN}\"|" ${LDAP_MOD_FILE}

    # 2. Habilitar o módulo LDAP criando o link simbólico
    if [ ! -L /etc/freeradius/3.0/mods-enabled/ldap ]; then
        echo "=> Habilitando o módulo LDAP para o FreeRADIUS..."
        ln -s ../mods-available/ldap /etc/freeradius/3.0/mods-enabled/ldap
    else
        echo "=> Módulo LDAP já está habilitado."
    fi

    # 3. Adicionar o cliente RADIUS (/etc/freeradius/3.0/clients.conf)
    echo "=> Adicionando cliente RADIUS: ${RADIUS_CLIENT_IP}"
    cat <<EOF >> /etc/freeradius/3.0/clients.conf

client localnet {
    ipaddr = ${RADIUS_CLIENT_IP}
    secret = ${RADIUS_CLIENT_SECRET}
}
EOF

    # 4. Instruir o FreeRADIUS a usar o LDAP para autenticação
    DEFAULT_SITE_FILE="/etc/freeradius/3.0/sites-available/default"
    echo "=> Configurando 'default' site para usar LDAP..."
    # Descomenta a linha 'ldap' na seção 'authorize'
    sed -i '/authorize {/a \\tldap' ${DEFAULT_SITE_FILE}
    # Na seção 'authenticate', comenta 'Auth-Type PAP' e descomenta 'ldap'
    sed -i -e '/authenticate {/ {n; s/^\s*Auth-Type PAP/#\t\tAuth-Type PAP/}' ${DEFAULT_SITE_FILE}
    sed -i '/authenticate {/a \\tldap' ${DEFAULT_SITE_FILE}
    # Na seção 'accounting', descomenta 'ldap'
    sed -i '/accounting {/a \\tldap' ${DEFAULT_SITE_FILE}
    
    # Adiciona o usuário do freeradius ao grupo do slapd para permitir leitura do socket
    usermod -a -G openldap freerad
}

# Função para reiniciar e habilitar os serviços
restart_services() {
    echo "================================================="
    echo "=> Reiniciando e habilitando os serviços..."
    echo "================================================="
    systemctl restart slapd
    systemctl enable slapd
    systemctl restart freeradius
    systemctl enable freeradius

    echo "=> Verificando status dos serviços:"
    systemctl status slapd --no-pager
    systemctl status freeradius --no-pager
}

# --- [ PARTE 3: EXECUÇÃO PRINCIPAL ] ------------------------------------------

main() {
    check_root
    install_packages
    configure_openldap
    configure_freeradius
    restart_services

    echo "======================================================================="
    echo "  INSTALAÇÃO E CONFIGURAÇÃO CONCLUÍDAS COM SUCESSO!                  "
    echo "======================================================================="
    echo
    echo "Resumo das Configurações:"
    echo "--------------------------"
    echo "Base DN LDAP:         ${LDAP_BASE_DN}"
    echo "Admin LDAP DN:        ${LDAP_ADMIN_DN}"
    echo
    echo "Usuário de Teste LDAP:"
    echo "  DN: uid=${TEST_USER_NAME},ou=people,${LDAP_BASE_DN}"
    echo "  Senha: ${TEST_USER_PASSWORD}"
    echo
    echo "Rede de Clientes RADIUS:"
    echo "  Rede:    ${RADIUS_CLIENT_IP}"
    echo "  Segredo: ${RADIUS_CLIENT_SECRET}"
    echo
    echo "Próximos Passos (comandos de teste personalizados para você):"
    echo "1. Teste a busca no LDAP com:"
    echo "   ldapsearch -x -b '${LDAP_BASE_DN}' '(uid=${TEST_USER_NAME})'"
    echo
    echo "2. Teste a autenticação RADIUS com a ferramenta 'radtest':"
    echo "   radtest ${TEST_USER_NAME} ${TEST_USER_PASSWORD} localhost 0 ${RADIUS_CLIENT_SECRET}"
    echo
}

# Inicia a execução do script
main