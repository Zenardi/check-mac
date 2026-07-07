#!/bin/bash

# ==========================================================
#   DIAGNÓSTICO PROFUNDO - MACBOOK APPLE SILICON
#   Auditoria para compra de MacBook seminovo (M1/M2/M3/M4...)
#   Usa apenas ferramentas nativas do macOS (sem Homebrew, sem sudo)
# ==========================================================

# --- Cores (desativa automaticamente se não for terminal interativo) ---
if [ -t 1 ]; then
  BOLD=$(tput bold); RED=$(tput setaf 1); GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3); BLUE=$(tput setaf 6); RESET=$(tput sgr0)
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

# --- Helpers ---
section() {
  echo ""
  echo "${BOLD}${BLUE}==================================================${RESET}"
  echo "${BOLD}${BLUE} $1${RESET}"
  echo "${BOLD}${BLUE}==================================================${RESET}"
}

# Acumuladores para o RESUMO final (nota, impeditivos e pontos de atenção)
CRIT_LIST=(); ALERT_LIST=(); WARN_LIST=()
ok()    { echo "  ${GREEN}✔ $1${RESET}"; }
warn()  { echo "  ${YELLOW}⚠ $1${RESET}"; WARN_LIST+=("$1"); }
alert() { echo "  ${RED}✖ $1${RESET}"; ALERT_LIST+=("$1"); }
crit()  { echo "  ${BOLD}${RED}🚫 $1${RESET}"; CRIT_LIST+=("$1"); }
info()  { echo "    $1"; }

# Lê um valor numérico top-level do ioreg da bateria (ex: DesignCapacity, CycleCount).
# Casa apenas ' = ' (com espaços) para ignorar o blob compacto "BatteryData".
ioreg_batt() {
  ioreg -r -c AppleSmartBattery 2>/dev/null | grep -m1 "\"$1\" = " | awk -F' = ' '{print $2}' | tr -d ' '
}

# --- Opções avançadas (--temp e --boot exigem sudo) ---
RUN_TEMP=0
RUN_BOOT=0
RUN_STRESS=0
STRESS_SECS=60

show_help() {
  cat <<EOF
Uso: ./check.sh [opções]

Sem opções, roda todas as verificações que NÃO exigem senha (sudo).

Opções avançadas:
  -A, --all        Roda TUDO de uma vez: padrão + temperatura + Secure Boot +
                   teste de estresse (pede a senha do Mac uma única vez)
  -a, --advanced   Temperatura + Secure Boot (pedem a senha do Mac uma única vez)
      --temp       Só pressão térmica/consumo em tempo real (powermetrics, sudo)
      --boot       Só a política de Secure Boot do Apple Silicon (bputil, sudo)
      --stress     Teste de estresse: força 100% da CPU por ${STRESS_SECS}s para ativar
                   as ventoinhas e medir throttling (use --stress=N para N segundos)
  -h, --help       Mostra esta ajuda e sai

Exemplos:
  ./check.sh                 # diagnóstico padrão, sem senha
  ./check.sh --all           # executa TODAS as verificações de uma vez (pede senha)
  ./check.sh --advanced      # inclui temperatura e secure boot (pede senha)
  ./check.sh --stress        # roda o teste de carga por ${STRESS_SECS}s
  ./check.sh --stress=90     # teste de carga por 90 segundos
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -A|--all)      RUN_TEMP=1; RUN_BOOT=1; RUN_STRESS=1 ;;
    -a|--advanced) RUN_TEMP=1; RUN_BOOT=1 ;;
    --temp)        RUN_TEMP=1 ;;
    --boot)        RUN_BOOT=1 ;;
    --stress)      RUN_STRESS=1 ;;
    --stress=*)    RUN_STRESS=1; STRESS_SECS="${1#*=}" ;;
    -h|--help)     show_help; exit 0 ;;
    *) echo "Opção desconhecida: $1"; echo; show_help; exit 1 ;;
  esac
  shift
done

# Valida a duração do estresse (inteiro positivo; mínimo de 10s)
case "$STRESS_SECS" in ''|*[!0-9]*) STRESS_SECS=45 ;; esac
[ "$STRESS_SECS" -lt 10 ] 2>/dev/null && STRESS_SECS=10

clear
echo "${BOLD}=================================================="
echo "    DIAGNÓSTICO PROFUNDO - MACBOOK APPLE SILICON  "
echo "==================================================${RESET}"
echo "  Data do teste: $(date '+%d/%m/%Y %H:%M')"
echo "  Máquina:       $(scutil --get ComputerName 2>/dev/null || hostname)"

# ----------------------------------------------------------
section "[1] SISTEMA OPERACIONAL"
# ----------------------------------------------------------
echo "  ${BOLD}macOS:${RESET} $(sw_vers -productName) $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
# Tempo ligado desde o último boot (ajuda a ver se reiniciaram para esconder travamentos)
echo "  ${BOLD}Uptime:${RESET}$(uptime | sed 's/.*up/ /' | sed 's/,.*load.*//')"

# ----------------------------------------------------------
section "[2] ESPECIFICAÇÕES REAIS DO HARDWARE"
# ----------------------------------------------------------
system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '
/Model Name|Model Identifier|Model Number|Chip|Total Number of Cores|Memory|Serial Number|Hardware UUID/{
  gsub(/^ +/, "", $1); printf "  %-24s %s\n", $1":", $2
}'
echo "  ${YELLOW}Dica:${RESET} confira o número de série em https://checkcoverage.apple.com para ver garantia/AppleCare."

# ----------------------------------------------------------
section "[3] BATERIA (Saúde real)"
# ----------------------------------------------------------
# Dados da interface do sistema
system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '
/Cycle Count|Condition|Maximum Capacity|Fully Charged|Charging|State of Charge/{
  gsub(/^ +/, "", $1); printf "  %-24s %s\n", $1":", $2
}'

# Cálculo detalhado via ioreg (capacidade de design vs. capacidade máxima atual)
DESIGN=$(ioreg_batt DesignCapacity)
RAWMAX=$(ioreg_batt AppleRawMaxCapacity)
CYCLES=$(ioreg_batt CycleCount)
[ -n "$CYCLES" ] && echo "  ${BOLD}Ciclos (ioreg):${RESET}          $CYCLES"
if [ -n "$DESIGN" ] && [ -n "$RAWMAX" ] && [ "$DESIGN" -gt 0 ] 2>/dev/null; then
  # LC_ALL=C garante ponto decimal (evita vírgula em locales pt-BR); %d dá o inteiro para comparação
  HEALTH=$(LC_ALL=C awk "BEGIN{printf \"%.1f\", ($RAWMAX/$DESIGN)*100}")
  HEALTH_INT=$(LC_ALL=C awk "BEGIN{printf \"%d\", ($RAWMAX/$DESIGN)*100}")
  info "Capacidade de design:  $DESIGN mAh"
  info "Capacidade atual:      $RAWMAX mAh (estimativa; confira também 'Maximum Capacity' acima)"
  if [ "$HEALTH_INT" -ge 85 ] 2>/dev/null; then
    ok "Saúde calculada da bateria: ${HEALTH}%"
  elif [ "$HEALTH_INT" -ge 80 ] 2>/dev/null; then
    warn "Saúde calculada da bateria: ${HEALTH}% (aceitável, mas já em desgaste)"
  else
    alert "Saúde calculada da bateria: ${HEALTH}% (abaixo de 80% = degradada, troca recomendada)"
  fi
fi

# ----------------------------------------------------------
section "[4] ARMAZENAMENTO (SSD)"
# ----------------------------------------------------------
echo "  ${BOLD}Armazenamento interno:${RESET}"
diskutil info disk0 2>/dev/null | grep -E "Solid State|Device / Media Name" | sed 's/^ */    /'
SMART=$(diskutil info disk0 2>/dev/null | awk -F': ' '/SMART Status/{gsub(/^ +/,"",$2);print $2}')
if [ -z "$SMART" ]; then
  warn "SMART Status não reportado por este disco."
elif echo "$SMART" | grep -qi "Verified"; then
  ok "SMART Status: $SMART (disco saudável)."
else
  crit "SMART Status: $SMART — falha iminente do SSD; como é soldado, a placa perde utilidade."
fi
echo "  ${BOLD}Uso da partição principal:${RESET}"
df -h / | awk 'NR==2 {print "    Tamanho: "$2" | Usado: "$3" | Livre: "$4" ("$5" ocupado)"}'
echo "  ${BOLD}Discos físicos detectados:${RESET}"
diskutil list physical 2>/dev/null | grep -E "^/dev/disk" | sed 's/^/    /'

# ----------------------------------------------------------
section "[5] THROTTLING TÉRMICO (CPU limitada?)"
# ----------------------------------------------------------
# CPU_Speed_Limit = 100 é o ideal (sem limitação por calor/defeito)
pmset -g therm 2>/dev/null | sed 's/^/  /'
LIMIT=$(pmset -g therm 2>/dev/null | awk -F= '/CPU_Speed_Limit/{gsub(/ /,"",$2); print $2}')
if [ "$LIMIT" = "100" ]; then
  ok "CPU rodando a 100% (sem throttling)."
elif [ -n "$LIMIT" ]; then
  alert "CPU limitada a ${LIMIT}% sem carga pesada — possível superaquecimento ou sensor defeituoso."
else
  # No Apple Silicon em repouso o pmset costuma não reportar CPU_Speed_Limit — sem evento = bom sinal.
  ok "Nenhum evento de throttling registrado (comportamento normal do Apple Silicon em repouso)."
  echo "  ${YELLOW}Obs.:${RESET} para forçar o teste térmico sob carga, rode './check.sh --stress'."
fi

# ----------------------------------------------------------
section "[6] BLOQUEIO DE ATIVAÇÃO (Activation Lock)"
# ----------------------------------------------------------
# DEVE estar Disabled. Se Enabled, o Mac está preso ao iCloud de outra pessoa.
AL=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Activation Lock/{gsub(/^ +/,"",$2); print $2}')
if [ -z "$AL" ]; then
  warn "Status de Activation Lock não reportado por esta versão do macOS."
elif echo "$AL" | grep -qi "Disabled"; then
  ok "Activation Lock: $AL"
else
  crit "Activation Lock: $AL — Mac preso ao iCloud de outra pessoa. NÃO COMPRE até desativar e formatar na sua frente."
fi

# ----------------------------------------------------------
section "[7] GERENCIAMENTO REMOTO / MDM (Red flag corporativa)"
# ----------------------------------------------------------
# Macs de empresa podem re-bloquear remotamente mesmo após formatar (DEP/ABM).
ENROLL=$(profiles status -type enrollment 2>/dev/null)
if [ -z "$ENROLL" ]; then
  warn "Não foi possível ler o status de enrollment."
else
  echo "$ENROLL" | sed 's/^/    /'
  if echo "$ENROLL" | grep -qi "DEP: Yes\|MDM enrollment: Yes"; then
    crit "Inscrita em MDM/DEP — equipamento corporativo que pode RE-BLOQUEAR remotamente mesmo após formatar. NÃO COMPRE."
  else
    ok "Sem inscrição em MDM/DEP."
  fi
fi

# ----------------------------------------------------------
section "[8] INTEGRIDADE DO SISTEMA (SIP / FileVault)"
# ----------------------------------------------------------
SIP=$(csrutil status 2>/dev/null)
if echo "$SIP" | grep -qi "enabled"; then
  ok "SIP (System Integrity Protection): habilitado."
else
  warn "SIP: ${SIP:-desconhecido} — se desabilitado, alguém pode ter alterado o sistema."
fi
FV=$(fdesetup status 2>/dev/null)
echo "    FileVault: ${FV:-desconhecido}"
echo "  ${YELLOW}Dica:${RESET} peça para o vendedor DESATIVAR o FileVault ou formatar, senão o disco fica criptografado com a senha dele."

# ----------------------------------------------------------
section "[9] TELA E GPU"
# ----------------------------------------------------------
system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '
/Chipset Model|Total Number of Cores|Resolution|Display Type|Mirror|Main Display|UI Looks like/{
  gsub(/^ +/, "", $1); printf "  %-24s %s\n", $1":", $2
}'
echo "  ${YELLOW}Teste físico:${RESET} abra uma imagem branca e uma preta em tela cheia para caçar pixels mortos/manchas/burn-in."

# ----------------------------------------------------------
section "[10] CONECTIVIDADE (Wi-Fi / Bluetooth)"
# ----------------------------------------------------------
echo "  ${BOLD}Wi-Fi:${RESET}"
system_profiler SPAirPortDataType 2>/dev/null | awk -F': ' '
/Card Type|Firmware Version|Supported PHY Modes|Status/{
  gsub(/^ +/, "", $1); printf "    %-22s %s\n", $1":", $2
}' | head -n 6
echo "  ${BOLD}Bluetooth:${RESET}"
system_profiler SPBluetoothDataType 2>/dev/null | awk -F': ' '
/State|Chipset|Firmware Version|Bluetooth Low Energy Supported/{
  gsub(/^ +/, "", $1); printf "    %-22s %s\n", $1":", $2
}' | head -n 4

# ----------------------------------------------------------
section "[11] PORTAS (USB / Thunderbolt)"
# ----------------------------------------------------------
echo "  ${BOLD}Barramentos Thunderbolt/USB4:${RESET}"
system_profiler SPThunderboltDataType 2>/dev/null | grep -E "Thunderbolt.*Bus|Status|Device Name" | sed 's/^ */    /' | head -n 10
echo "  ${BOLD}Dispositivos USB conectados agora:${RESET}"
system_profiler SPUSBDataType 2>/dev/null | grep -E "Product ID|Manufacturer|USB.*Bus" | sed 's/^ */    /' | head -n 10
echo "  ${YELLOW}Teste físico:${RESET} conecte um pendrive/carregador em CADA porta USB-C para confirmar que todas funcionam."

# ----------------------------------------------------------
section "[12] CÂMERA E ÁUDIO"
# ----------------------------------------------------------
echo "  ${BOLD}Câmera:${RESET}"
system_profiler SPCameraDataType 2>/dev/null | grep -E "Model ID|Unique ID|:" | grep -vi "Camera:" | sed 's/^ */    /' | head -n 4
echo "  ${BOLD}Áudio:${RESET}"
system_profiler SPAudioDataType 2>/dev/null | grep -E "MacBook.*Speakers|Microphone|Built-in|Output|Input" | sed 's/^ */    /' | head -n 6

# ----------------------------------------------------------
section "[13] HISTÓRICO DE TRAVAMENTOS (Kernel Panics)"
# ----------------------------------------------------------
PANIC_DIR="/Library/Logs/DiagnosticReports"
PANICS=$(ls "$PANIC_DIR"/*.panic 2>/dev/null | wc -l | tr -d ' ')
if [ "$PANICS" -gt 0 ] 2>/dev/null; then
  alert "$PANICS relatório(s) de kernel panic encontrados (sinal de instabilidade de hardware):"
  ls -t "$PANIC_DIR"/*.panic 2>/dev/null | head -n 5 | sed 's|.*/|    |'
else
  ok "Nenhum kernel panic registrado."
fi

# ==========================================================
#   VERIFICAÇÕES AVANÇADAS (OPCIONAIS)
#   Ativadas por: --advanced, --temp, --boot e/ou --stress
# ==========================================================
if [ "$RUN_TEMP" = "1" ] || [ "$RUN_BOOT" = "1" ] || [ "$RUN_STRESS" = "1" ]; then
  section "[AVANÇADO] Checagens adicionais"
  echo "  Algumas seções pedem a senha do Mac (sudo) só para LER sensores — nada é alterado."
  HAVE_SUDO=0
  if sudo -v 2>/dev/null; then
    HAVE_SUDO=1
  else
    warn "Sem privilégios de administrador: seções que dependem de sudo serão limitadas."
  fi

  # ------- [14] Pressão térmica e consumo (powermetrics, sudo) -------
  if [ "$RUN_TEMP" = "1" ]; then
    section "[14] PRESSÃO TÉRMICA E CONSUMO (tempo real, sudo)"
    if [ "$HAVE_SUDO" = "1" ]; then
      echo "  Coletando 1 amostra (aguarde ~2s)..."
      # Obs.: o sampler 'smc' (temperatura °C / ventoinha RPM) NÃO existe no Apple Silicon;
      # usamos pressão térmica + consumo de CPU/GPU, que são os sinais nativos disponíveis.
      PM=$(sudo powermetrics --samplers thermal,cpu_power,gpu_power -n 1 -i 1000 2>/dev/null)
      TLINES=$(echo "$PM" | grep -iE "pressure|CPU Power|GPU Power|Combined Power|temperature|fan")
      if [ -n "$TLINES" ]; then
        echo "$TLINES" | sed 's/^ */    /'
      else
        warn "powermetrics não retornou dados (os samplers podem variar conforme a versão do macOS)."
      fi
      echo "  ${YELLOW}Referência:${RESET} em repouso a pressão térmica deve ser 'Nominal'. Se já estiver 'Heavy'/'Moderate' sem carga, há problema de refrigeração. Temperatura exata em °C exige app de terceiros (fora do escopo 'sem instalação')."
    else
      warn "Requer sudo — seção pulada."
    fi
  fi

  # ------- [15] Política de Secure Boot (bputil, sudo) -------
  if [ "$RUN_BOOT" = "1" ]; then
    section "[15] SECURE BOOT / POLÍTICA DE INICIALIZAÇÃO (sudo)"
    if [ "$HAVE_SUDO" = "1" ]; then
      BP=$(sudo bputil -d 2>&1)
      if echo "$BP" | grep -qi "Security Mode:"; then
        # Mostra só as linhas de segurança relevantes (ignora hashes e IDs do chip)
        echo "$BP" | grep -iE "Security Mode:|Kexts Status:|MDM Control:|SIP Status:|Signed System Volume|CTRR Status:|Boot Args Filtering" | sed 's/^ */    /'
        SECMODE=$(echo "$BP" | grep -i "Security Mode:")
        if echo "$SECMODE" | grep -qiw "Full"; then
          ok "Secure Boot: Full Security (nível máximo, ideal)."
        elif echo "$SECMODE" | grep -qiE "Reduced|Permissive"; then
          alert "Secure Boot rebaixado (Reduced/Permissive) — a segurança de inicialização foi reduzida. Investigue o motivo com o vendedor."
        else
          warn "Não classifiquei a linha 'Security Mode' automaticamente; leia acima. O ideal é 'Full'."
        fi
      else
        warn "bputil não retornou a política de boot nesta máquina."
      fi
    else
      warn "Requer sudo — seção pulada."
    fi
  fi

  # ------- [16] Teste de estresse térmico (carga real de CPU) -------
  if [ "$RUN_STRESS" = "1" ]; then
    section "[16] TESTE DE ESTRESSE TÉRMICO (${STRESS_SECS}s de carga)"
    NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    echo "  Vou usar 100% dos $NCPU núcleos por ${STRESS_SECS}s com cálculo pesado (ponto flutuante)."
    echo "  É SEGURO — apenas força o chip a esquentar."
    echo "  ${BOLD}O que observar:${RESET} a coluna 'pressão' deve subir no máximo até Moderate. Ouvir as ventoinhas é opcional."
    echo "  ${YELLOW}Nota:${RESET} no MacBook Pro 14\"/16\" (M2/M3/M4 Pro) as ventoinhas costumam ficar SILENCIOSAS mesmo sob carga — isso é folga de refrigeração, e é bom. Para tentar acelerá-las de fato, use uma carga longa: './check.sh --stress=180'. O MacBook Air não tem ventoinha alguma."
    [ "$HAVE_SUDO" != "1" ] && warn "Sem sudo: no Apple Silicon a medição de throttling fica limitada (confie no som das ventoinhas e na pressão térmica)."
    # Inicia a carga: um loop de ponto flutuante (sqrt/sin/cos) por núcleo — bem mais "denso"
    # em energia que 'yes', esquentando o chip de verdade, e sem instalar nada.
    PIDS=()
    for _ in $(seq 1 "$NCPU"); do
      awk 'BEGIN{for(i=1;;i++){x=sqrt(i*3.14159)+sin(i)*cos(i); if(x>1e12)i=1}}' >/dev/null 2>&1 &
      PIDS+=($!)
    done
    trap 'kill "${PIDS[@]}" 2>/dev/null' INT TERM
    # No Apple Silicon o sinal confiável é a PRESSÃO TÉRMICA (Nominal<Moderate<Heavy<Trapping).
    WORST="Nominal"; WORST_RANK=0; MINLIM=100; STEP=10; ELAPSED=0
    while [ "$ELAPSED" -lt "$STRESS_SECS" ]; do
      # Ajusta o último passo para não ultrapassar a duração pedida
      REMAIN=$((STRESS_SECS - ELAPSED)); THIS=$STEP; [ "$REMAIN" -lt "$STEP" ] && THIS=$REMAIN
      sleep "$THIS"
      ELAPSED=$((ELAPSED + THIS))
      LIM=$(pmset -g therm 2>/dev/null | awk -F= '/CPU_Speed_Limit/{gsub(/ /,"",$2);print $2}')
      [ -n "$LIM" ] && [ "$LIM" -lt "$MINLIM" ] 2>/dev/null && MINLIM=$LIM
      PRESS=""
      if [ "$HAVE_SUDO" = "1" ]; then
        PRESS=$(sudo powermetrics --samplers thermal -n 1 -i 200 2>/dev/null | awk -F': ' '/pressure level/{print $2; exit}')
        case "$PRESS" in
          *Nominal*)             R=0 ;;
          *Moderate*)            R=1 ;;
          *Heavy*)               R=2 ;;
          *Trapping*|*Sleeping*) R=3 ;;
          *)                     R=0 ;;
        esac
        [ "$R" -gt "$WORST_RANK" ] && { WORST_RANK=$R; WORST=$PRESS; }
      fi
      printf "    t=%-5s pressão=%-12s CPU_Speed_Limit=%s\n" "${ELAPSED}s" "${PRESS:-n/d}" "${LIM:-n/d}"
    done
    # Encerra a carga
    kill "${PIDS[@]}" 2>/dev/null
    trap - INT TERM
    wait "${PIDS[@]}" 2>/dev/null
    # Veredito (primário: pressão térmica; secundário: CPU_Speed_Limit)
    if [ "$HAVE_SUDO" = "1" ]; then
      case "$WORST_RANK" in
        0) ok "Pressão térmica ficou Nominal durante todo o teste — refrigeração excelente." ;;
        1) ok "Pressão chegou a Moderate — comportamento normal sob carga sustentada." ;;
        2) warn "Pressão chegou a Heavy — throttling térmico relevante. Num Pro, confirme que as ventoinhas aceleraram." ;;
        *) alert "Pressão atingiu Trapping/Sleeping — superaquecimento sério; investigue a refrigeração." ;;
      esac
    fi
    if [ "$MINLIM" -lt 100 ] 2>/dev/null; then
      warn "CPU_Speed_Limit caiu a ${MINLIM}% em algum momento (throttling confirmado)."
    fi
    echo "  ${YELLOW}Como ler:${RESET} pressão parada em Nominal/Moderate = refrigeração saudável (ventoinha silenciosa é bom sinal). Chegar a Heavy/Trapping rápido = alerta. Ventoinha muda COM a pressão em Heavy = possível ventoinha travada/defeituosa."
  fi
fi

# ==========================================================
#   RESUMO E NOTA FINAL
# ==========================================================
section "RESUMO E NOTA FINAL"
NC=${#CRIT_LIST[@]}; NA=${#ALERT_LIST[@]}; NW=${#WARN_LIST[@]}
# Nota: parte de 10 e desconta por severidade. Qualquer impeditivo trava em no máximo 2.
SCORE=$((10 - 5 * NC - 2 * NA - 1 * NW))
[ "$SCORE" -lt 0 ] && SCORE=0
[ "$NC" -gt 0 ] && [ "$SCORE" -gt 2 ] && SCORE=2

if [ "$SCORE" -ge 8 ]; then SC="$GREEN"
elif [ "$SCORE" -ge 5 ]; then SC="$YELLOW"
else SC="$RED"; fi
echo "  ${BOLD}NOTA FINAL: ${SC}${SCORE}/10${RESET}"
echo "    (${NC} impeditivo(s), ${NA} problema(s) sério(s), ${NW} ponto(s) de atenção)"

if [ "$NC" -gt 0 ]; then
  echo ""
  echo "  ${BOLD}${RED}🚫 IMPEDITIVOS (motivos para NÃO comprar):${RESET}"
  for m in "${CRIT_LIST[@]}"; do echo "    ${RED}• ${m}${RESET}"; done
fi
if [ "$NA" -gt 0 ]; then
  echo ""
  echo "  ${BOLD}${RED}✖ Problemas sérios:${RESET}"
  for m in "${ALERT_LIST[@]}"; do echo "    • ${m}"; done
fi
if [ "$NW" -gt 0 ]; then
  echo ""
  echo "  ${BOLD}${YELLOW}⚠ Pontos de atenção:${RESET}"
  for m in "${WARN_LIST[@]}"; do echo "    • ${m}"; done
fi
if [ "$NC" -eq 0 ] && [ "$NA" -eq 0 ] && [ "$NW" -eq 0 ]; then
  echo "  ${GREEN}Nenhum problema detectado pelo software. Excelente!${RESET}"
fi

echo ""
echo "  ${BOLD}📋 A VERIFICAR MANUALMENTE (o software não cobre):${RESET}"
echo "    [ ] Tela: pixels mortos/manchas (abra uma imagem branca e uma preta em tela cheia)"
echo "    [ ] Todas as portas USB-C/Thunderbolt (teste um cabo/pendrive em cada uma)"
echo "    [ ] Câmera e microfone (grave no Photo Booth ou num app de voz)"
echo "    [ ] Teclado (todas as teclas) e trackpad (clique e gestos)"
echo "    [ ] Alto-falantes (toque um áudio e confira os dois canais)"
echo "    [ ] Wi-Fi e Bluetooth conectando de fato a uma rede/dispositivo"
echo "    [ ] Garantia/AppleCare pelo nº de série em https://checkcoverage.apple.com"
echo "    [ ] Teste de hardware da Apple: reinicie segurando o botão de energia e aperte Cmd+D"
[ "$RUN_STRESS" != "1" ] && echo "    [ ] Estresse térmico + ventoinhas: rode './check.sh --stress'"

# ----------------------------------------------------------
echo ""
echo "${BOLD}${BLUE}==================================================${RESET}"
echo "${BOLD} Concluído. Legenda: ${GREEN}✔ OK${RESET}  ${YELLOW}⚠ atenção${RESET}  ${RED}✖ sério${RESET}  ${RED}🚫 impeditivo${RESET}"
if [ "$RUN_TEMP" = "0" ] && [ "$RUN_BOOT" = "0" ] && [ "$RUN_STRESS" = "0" ]; then
  echo "${YELLOW} Dica: rode './check.sh --all' para incluir as checagens avançadas (temperatura, secure boot, estresse).${RESET}"
fi
echo "${BOLD}${BLUE}==================================================${RESET}"
