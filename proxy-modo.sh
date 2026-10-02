#!/bin/bash
# ============================================================
# proxy-modo.sh  (v4 - base + flags, com estado de prova)
# Controle de filtragem do Squid | CT101 | rodar como root
# ============================================================
#
# ---------- MODELO ----------
#
# Tres BASES, da mais restritiva para a mais permissiva:
#
#   bloqueado  nada passa - nem a whitelist        (provas, atividades)
#   restrito   so passa sites_permitidos.txt       (padrao de aula)
#   aberto     tudo passa, sem whitelist
#
# FLAGS, que liberam categorias normalmente bloqueadas:
#
#   +ia        libera ferramentas de IA      (sites_ia.txt)
#   +social    libera redes sociais          (sites_redes_sociais.txt)
#   +prova     libera sites_prova.txt        (SO com a base "bloqueado")
#
# Sem flag, a categoria fica bloqueada - inclusive na base "aberto".
#
# ---------- USO ----------
#
#   ./proxy-modo.sh status
#   ./proxy-modo.sh restrito                      # padrao de aula
#   ./proxy-modo.sh restrito +ia                  # whitelist + IA
#   ./proxy-modo.sh restrito +social              # whitelist + redes sociais
#   ./proxy-modo.sh bloqueado                     # nada passa
#   ./proxy-modo.sh bloqueado +prova              # so o AVA / plataforma
#   ./proxy-modo.sh aberto                        # tudo, menos IA e sociais
#   ./proxy-modo.sh aberto +ia +social            # tudo liberado
#
# ALVO: passe um ou mais IPs para aplicar so a certas maquinas.
#   ./proxy-modo.sh bloqueado +prova 10.137.144.209
#   IPs: hostname + 200. NOTE09 = .209, NOTE34 = .234
#
# PRAZO: passe minutos como ultimo argumento. Ao fim, volta sozinho
# para "restrito" sem flags. Use SEMPRE em prova - assim a sala
# reabre no fim do tempo mesmo se ninguem lembrar.
#   ./proxy-modo.sh bloqueado +prova 90
#
# A ordem dos argumentos nao importa, exceto a base, que vem primeiro.
#
# ---------- OBSERVACOES ----------
#
# Cada execucao REESCREVE o modo.conf por inteiro. Os modos nao se somam.
#
# O corte de ruido (regra 3 do squid.conf) e anterior a este arquivo e
# vence qualquer combinacao. Por isso .bing.com segue bloqueado mesmo em
# "aberto +ia +social".
#
# A base "bloqueado" NAO afeta o Veyon: ele usa a porta 11100 direta,
# sem passar pelo proxy. O monitoramento da sala continua funcionando.
#
# ============================================================

MODO_CONF="/etc/squid/modo.conf"
LOG="/var/log/squid/modo.log"
REDE_LAB="10.137.144.0/24"
TIMER="proxy-modo-expira"

BASE=""
FLAG_IA=0
FLAG_SOCIAL=0
FLAG_PROVA=0
IPS=()
MINUTOS=""

# ------------------------------------------------------------
# Funcoes auxiliares
# ------------------------------------------------------------

registrar() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOG"
}

aplicar() {
    if squid -k parse >/dev/null 2>&1; then
        squid -k reconfigure
        sleep 1
        echo "  Squid recarregado."
        return 0
    else
        echo ""
        echo "  ERRO: configuracao invalida. NADA foi aplicado."
        squid -k parse 2>&1 | tail -20
        return 1
    fi
}

cancelar_expiracao() {
    systemctl stop "${TIMER}.timer" 2>/dev/null
    systemctl reset-failed "${TIMER}.service" 2>/dev/null
}

agendar_expiracao() {
    local minutos="$1"
    if systemd-run --unit="$TIMER" --on-active="${minutos}min" \
        /root/proxy-modo.sh restrito >/dev/null 2>&1; then
        echo "  Volta automatica para RESTRITO em $minutos min."
        registrar "agendado retorno em ${minutos}min"
    else
        echo "  AVISO: nao foi possivel agendar a volta automatica."
        echo "  Lembre-se de rodar: $0 restrito"
    fi
}

uso() {
    echo ""
    echo "Uso: $0 <base> [flags] [ip...] [minutos]"
    echo ""
    echo "BASES"
    echo "  bloqueado      nada passa                  (provas)"
    echo "  restrito       so a whitelist passa        (padrao de aula)"
    echo "  aberto         tudo passa, sem whitelist"
    echo ""
    echo "FLAGS"
    echo "  +ia            libera ferramentas de IA"
    echo "  +social        libera redes sociais"
    echo "  +prova         libera sites_prova.txt (so com 'bloqueado')"
    echo ""
    echo "OUTROS"
    echo "  status         mostra a combinacao ativa"
    echo "  <ip>           aplica so a essas maquinas"
    echo "  <minutos>      volta a restrito depois do prazo"
    echo ""
    echo "EXEMPLOS"
    echo "  $0 restrito"
    echo "  $0 restrito +ia 10.137.144.209"
    echo "  $0 bloqueado +prova 90"
    echo "  $0 aberto +ia +social 30"
    echo ""
}

# ------------------------------------------------------------
# Parsing
# ------------------------------------------------------------

if [ $# -eq 0 ]; then
    uso
    exit 1
fi

case "$1" in
    bloqueado)    BASE="bloqueado" ;;
    restrito)     BASE="restrito" ;;
    aberto)       BASE="aberto" ;;
    status)       BASE="status" ;;
    -h|--help|help) uso; exit 0 ;;
    *)
        echo ""
        echo "  ERRO: base desconhecida: '$1'"
        echo "  As bases sao 'bloqueado', 'restrito' e 'aberto'. Categorias"
        echo "  como IA e redes sociais sao flags: use +ia e +social."
        uso
        exit 1
        ;;
esac
shift

for arg in "$@"; do
    case "$arg" in
        +ia|ia)          FLAG_IA=1 ;;
        +social|social)  FLAG_SOCIAL=1 ;;
        +prova|prova)    FLAG_PROVA=1 ;;
        [0-9]*)
            if [[ "$arg" =~ \. ]]; then
                IPS+=("$arg")
            else
                MINUTOS="$arg"
            fi
            ;;
        *)
            echo ""
            echo "  ERRO: argumento desconhecido: '$arg'"
            echo "  Esperado: +ia, +social, +prova, um IP ou minutos."
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------
# status
# ------------------------------------------------------------

if [ "$BASE" = "status" ]; then
    echo ""
    if [ ! -f "$MODO_CONF" ]; then
        echo "  $MODO_CONF nao existe. Rode: $0 restrito"
        exit 1
    fi

    grep -m1 "^# MODO:" "$MODO_CONF" | sed 's/^# /  /' || echo "  (sem cabecalho)"
    grep -m1 "^# ALVO:" "$MODO_CONF" | sed 's/^# /  /'
    echo ""
    echo "  Regras em vigor:"
    grep -E "^(acl|http_access)" "$MODO_CONF" | sed 's/^/    /'
    echo ""

    if systemctl is-active "${TIMER}.timer" >/dev/null 2>&1; then
        echo "  Volta automatica: AGENDADA"
    else
        echo "  Volta automatica: nao agendada"
    fi

    echo ""
    echo "  Ultimas trocas:"
    tail -6 "$LOG" 2>/dev/null | sed 's/^/    /' || echo "    (sem historico)"
    echo ""
    exit 0
fi

# ------------------------------------------------------------
# Coerencia das flags
# ------------------------------------------------------------

if [ $FLAG_PROVA -eq 1 ] && [ "$BASE" != "bloqueado" ]; then
    echo ""
    echo "  AVISO: +prova so tem efeito com a base 'bloqueado'."
    echo "  Nas bases 'restrito' e 'aberto' os sites de prova ja passam."
    echo "  A flag sera ignorada."
    FLAG_PROVA=0
fi

if [ "$BASE" = "bloqueado" ] && { [ $FLAG_IA -eq 1 ] || [ $FLAG_SOCIAL -eq 1 ]; }; then
    echo ""
    echo "  AVISO: +ia e +social nao fazem sentido com 'bloqueado',"
    echo "  que nega tudo. Serao ignoradas."
    FLAG_IA=0
    FLAG_SOCIAL=0
fi

# ------------------------------------------------------------
# Descricao e ACL de alvo
# ------------------------------------------------------------

DESCR="$BASE"
[ $FLAG_PROVA -eq 1 ]  && DESCR="$DESCR +prova"
[ $FLAG_IA -eq 1 ]     && DESCR="$DESCR +ia"
[ $FLAG_SOCIAL -eq 1 ] && DESCR="$DESCR +social"

if [ ${#IPS[@]} -eq 0 ]; then
    ACL_ALVO="acl alvo src $REDE_LAB"
    DESCR_ALVO="sala inteira"
else
    ACL_ALVO=""
    for ip in "${IPS[@]}"; do
        ACL_ALVO="${ACL_ALVO}acl alvo src $ip"$'\n'
    done
    ACL_ALVO="${ACL_ALVO%$'\n'}"
    DESCR_ALVO="${IPS[*]}"
fi

# ------------------------------------------------------------
# Gera o modo.conf
# ------------------------------------------------------------

{
    echo "# gerado por proxy-modo.sh em $(date)"
    echo "# MODO: $DESCR"
    echo "# ALVO: $DESCR_ALVO"
    echo "# NAO EDITAR A MAO - reescrito a cada troca de modo."
    echo ""
    echo "$ACL_ALVO"
    echo ""

    case "$BASE" in
        bloqueado)
            # Nega tudo para o alvo. Os allows, quando existem, precisam
            # vir ANTES do deny - senao nunca sao alcancados.
            if [ $FLAG_PROVA -eq 1 ]; then
                echo "http_access allow alvo sistema_prova porta_prova"
                echo "http_access allow alvo sites_prova"
            fi
            echo "http_access deny alvo"
            ;;

        restrito)
            # A whitelist continua valendo (regras 5 e 6 do squid.conf).
            # As flags apenas acrescentam allows para o alvo.
            [ $FLAG_IA -eq 1 ]     && echo "http_access allow alvo sites_ia"
            [ $FLAG_SOCIAL -eq 1 ] && echo "http_access allow alvo redes_sociais"
            ;;

        aberto)
            # Allow amplo. O que NAO foi liberado por flag precisa ser
            # negado ANTES dele, senao passa junto.
            [ $FLAG_IA -eq 0 ]     && echo "http_access deny alvo sites_ia"
            [ $FLAG_SOCIAL -eq 0 ] && echo "http_access deny alvo redes_sociais"
            echo "http_access allow alvo"
            ;;
    esac

    echo ""
    echo "# Quem nao e alvo mantem o bloqueio padrao das duas categorias."
    echo "http_access deny localnet redes_sociais"
    echo "http_access deny localnet sites_ia"
} > "$MODO_CONF"

# ------------------------------------------------------------
# Aplica
# ------------------------------------------------------------

echo ""
echo "  MODO : $DESCR"
echo "  ALVO : $DESCR_ALVO"
echo ""

case "$BASE" in
    bloqueado)
        if [ $FLAG_PROVA -eq 1 ]; then
            echo "  MODO PROVA - so os dominios de sites_prova.txt passam."
        else
            echo "  BLOQUEIO TOTAL - nenhum acesso a internet."
        fi
        echo "  O Veyon continua funcionando (nao usa o proxy)."
        ;;
    restrito)
        echo "  Whitelist em vigor."
        [ $FLAG_IA -eq 1 ]     && echo "  IA liberada."            || echo "  IA bloqueada."
        [ $FLAG_SOCIAL -eq 1 ] && echo "  Redes sociais liberadas." || echo "  Redes sociais bloqueadas."
        ;;
    aberto)
        echo "  Whitelist SUSPENSA - horario controlado e contorno tambem."
        [ $FLAG_IA -eq 1 ]     && echo "  IA liberada."            || echo "  IA bloqueada."
        [ $FLAG_SOCIAL -eq 1 ] && echo "  Redes sociais liberadas." || echo "  Redes sociais bloqueadas."
        ;;
esac
echo ""

cancelar_expiracao

if aplicar; then
    registrar "$DESCR | alvo: $DESCR_ALVO"

    if [ -n "$MINUTOS" ]; then
        agendar_expiracao "$MINUTOS"
    elif [ "$BASE" != "restrito" ] || [ $FLAG_IA -eq 1 ] || [ $FLAG_SOCIAL -eq 1 ]; then
        echo ""
        if [ "$BASE" = "bloqueado" ]; then
            echo "  ATENCAO: bloqueio sem prazo. A sala fica sem internet ate"
            echo "  alguem rodar:  $0 restrito"
        else
            echo "  ATENCAO: liberacao sem prazo. Ao terminar, rode:"
            echo "    $0 restrito"
        fi
    fi
fi
