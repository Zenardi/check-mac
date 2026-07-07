# Guia de Diagnóstico e Check-up para MacBooks Apple Silicon

Este repositório contém um guia prático e um script de automação para realizar uma auditoria completa e profunda em MacBooks seminovos (com foco em chips Apple Silicon M1, M2, M3, M4, etc.) antes de fechar a compra.

O objetivo é extrair dados reais do hardware diretamente do sistema operacional e executar testes físicos para identificar fraudes, desgastes excessivos ou defeitos ocultos.

---

## 🚀 Como Usar o Script de Diagnóstico (Terminal)

Este método utiliza apenas ferramentas nativas do macOS (`system_profiler`, `diskutil`, `pmset`, `ioreg`, `profiles`, `csrutil`, `fdesetup`, `sw_vers`), dispensando a necessidade de instalar pacotes de terceiros (como Homebrew) na máquina do vendedor. Nenhum comando pede senha (`sudo`), então é seguro rodar na frente do vendedor.

### Passo a Passo:

1. **Abra o Terminal** do Mac (pressione `Cmd + Espaço`, digite `Terminal` e pressione `Enter`).
2. **Crie o arquivo do script** executando o seguinte comando:

```bash
nano check.sh
```

3. **Cole o código do script** (fornecido abaixo) dentro do editor que se abriu no terminal.
4. **Salve e saia**:
* Pressione `Ctrl + O` e depois `Enter` para salvar.
* Pressione `Ctrl + X` para fechar o editor.


5. **Dê permissão de execução** ao arquivo:
```bash
chmod +x check.sh
```


6. **Execute o script**:
```bash
./check.sh
```

### ⚙️ Opções de Linha de Comando

O script funciona sem nenhum argumento (roda tudo que **não** exige senha). Para rodar **todas** as verificações de uma vez, use `--all`. Demais opções:

```bash
./check.sh --all         # ⭐ roda TUDO: padrão + temperatura + secure boot + estresse
./check.sh --help        # mostra todas as opções disponíveis
./check.sh --advanced    # + pressão térmica e Secure Boot (pede senha uma vez)
./check.sh --temp        # + só pressão térmica/consumo (powermetrics)
./check.sh --boot        # + só a política de Secure Boot (bputil)
./check.sh --stress      # + teste de carga (60s): força 100% da CPU com cálculo pesado
./check.sh --stress=180  # idem, por 180s (recomendado p/ tentar acelerar as ventoinhas)
```

> ✅ **Recomendado para a compra:** rode `./check.sh --all` para uma auditoria completa numa tacada só (as 13 checagens padrão + as 3 avançadas). Ele pedirá a senha uma única vez.

> ⚠️ As opções `--advanced`, `--temp` e `--boot` usam `sudo` (senha de administrador) apenas para **ler** sensores e a política de inicialização — nada é alterado. O `--stress` roda mesmo sem senha (mas fica mais preciso com ela) e coloca a CPU a 100% por alguns segundos de propósito, para as ventoinhas ligarem — é seguro. Se preferir não usar senha, rode `./check.sh` sem argumentos.
>
> 💡 **Importante (Apple Silicon):** ferramentas nativas não expõem temperatura em °C nem RPM da ventoinha (isso era exclusivo dos Macs Intel). Por isso o diagnóstico térmico se baseia na **pressão térmica** (`Nominal → Moderate → Heavy`) e no som das ventoinhas durante o `--stress`.

### 📄 Código do Script (`check.sh`)

> 💡 **Dica:** o script completo e sempre atualizado está no arquivo [`check.sh`](check.sh) deste repositório. O bloco abaixo é uma cópia fiel para você colar direto no `nano`.

```bash
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
```

---

## 🔍 O que Analisar nos Resultados (Alertas e Red Flags)

> A saída usa uma legenda visual: **✔ verde = OK**, **⚠ amarelo = atenção**, **✖ vermelho = problema sério**, **🚫 vermelho = impeditivo (não compre)**.

### 🏁 Resumo e Nota Final (automático)

Ao terminar, o script exibe uma seção **RESUMO E NOTA FINAL** que consolida tudo:

* **Nota de 0 a 10**, calculada automaticamente a partir dos achados: cada **ponto de atenção** (⚠) desconta 1, cada **problema sério** (✖) desconta 2, e cada **impeditivo** (🚫) desconta 5. **Qualquer impeditivo trava a nota em no máximo 2** — o recado é claro: não feche a compra.
* **🚫 Impeditivos:** motivos objetivos para *não comprar* (ex.: Activation Lock ativo, inscrição em MDM/DEP, SSD com SMART falhando).
* **⚠ Pontos de atenção e ✖ problemas sérios:** lista consolidada do que apareceu ao longo do diagnóstico.
* **📋 A verificar manualmente:** checklist dos testes físicos que o software não cobre (tela, portas, teclado, câmera, som, ventoinhas, garantia e o teste de hardware da Apple).

Regra prática: **nota 8–10** = tranquilo; **5–7** = negocie o preço/investigue; **abaixo de 5 ou qualquer 🚫** = risco alto.

Abaixo, o detalhamento de cada verificação:

* **[1] Sistema Operacional:** confira a versão do macOS (um Mac muito antigo pode já estar sem suporte a atualizações) e o `Uptime`. Se acabaram de reiniciar a máquina antes de você chegar, o histórico de throttling e panics pode ter sido zerado — peça para rodar o script depois de usar o notebook por alguns minutos.
* **[2] Hardware:** verifique se o chip, o número de núcleos e a quantidade de memória RAM (`Memory`) batem exatamente com o anúncio. Anote o `Serial Number` e consulte a garantia/AppleCare em https://checkcoverage.apple.com.
* **[3] Bateria:** a `Condition` deve ser **Normal**. Se exibir *Service Recommended*, a bateria precisará ser trocada em breve. Avalie o `Cycle Count` (ciclos) em conjunto com a `Maximum Capacity` e a **saúde calculada via `ioreg`**. Se a saúde estiver abaixo de 80%, a Apple já considera a bateria degradada.
* **[4] SSD / Armazenamento:** o `SMART Status` deve ser **Verified**. Se aparecer *Failing*, o SSD está prestes a falhar — e como ele é soldado à placa lógica, a máquina perde a utilidade. Confira também se a capacidade total do disco bate com o anúncio.
* **[5] Throttling Térmico (`pmset -g therm`):** o ideal é `CPU_Speed_Limit = 100`. Se estiver abaixo (ex.: 50 ou 70) sem nenhum app pesado rodando, a máquina está limitando o desempenho por superaquecimento ou defeito em sensores térmicos.
* **[6] Activation Lock (Bloqueio de Ativação):** deve estar obrigatoriamente **Disabled**. Se estiver *Enabled*, o Mac está vinculado ao iCloud de outra pessoa. **Não compre** até que o vendedor desative a opção e formate o Mac na sua frente.
* **[7] MDM / Gerenciamento Remoto (`profiles`):** 🚨 red flag frequentemente ignorada. Se aparecer `Enrolled via DEP: Yes` ou `MDM enrollment: Yes`, é um **equipamento corporativo/institucional** (empresa, escola). A organização pode **re-bloquear e apagar** o Mac remotamente mesmo depois de você formatar. **Não compre** máquinas com inscrição em MDM/DEP.
* **[8] Integridade do Sistema (SIP / FileVault):** o `SIP` deve estar **habilitado** — se estiver desativado, alguém pode ter alterado o sistema. Se o `FileVault` estiver ligado, exija que o vendedor o desative ou formate a máquina, senão o disco fica criptografado com a senha dele.
* **[9] Tela e GPU:** confira a resolução e o tipo de tela. Faça também o teste físico de pixels mortos/manchas (imagem branca e preta em tela cheia).
* **[10] Conectividade (Wi-Fi / Bluetooth):** o Wi-Fi deve aparecer como `Connected` e o Bluetooth como `On`. Ausência ou instabilidade pode indicar defeito no módulo de rede (relacionado aos códigos NDT do teste físico).
* **[11] Portas (USB / Thunderbolt):** teste **cada** porta USB-C fisicamente com um pendrive ou carregador — portas queimadas são comuns e o software sozinho não detecta.
* **[12] Câmera e Áudio:** confirme que a câmera e os alto-falantes/microfones internos são detectados. Faça uma chamada de teste (Photo Booth / gravador de voz) para validar na prática.
* **[13] Kernel Panics:** se houver relatórios `.panic` registrados, a máquina travou de forma anormal no passado — possível sinal de instabilidade de hardware. Investigue o histórico com o vendedor.

### Checagens avançadas (só aparecem com `--advanced`, `--temp`, `--boot` ou `--stress`)

* **[14] Pressão Térmica e Consumo (`powermetrics`):** em repouso, a `pressure` (pressão térmica) deve estar **Nominal**. Se já estiver *Moderate* ou *Heavy* com a máquina parada, há problema de refrigeração (pasta térmica ressecada, ventoinha travada, sensor defeituoso). Lembre-se: no Apple Silicon **não existe leitura nativa de °C nem de RPM** — a pressão térmica é o indicador oficial.
* **[15] Secure Boot (`bputil`):** o ideal é **Full Security** (segurança máxima). Se aparecer *Reduced Security* ou *Permissive*, alguém rebaixou a segurança de inicialização — comum para instalar drivers não assinados ou sistemas modificados. Pergunte ao vendedor o porquê; o normal em um Mac "de fábrica" é Full Security. Esta seção também mostra `SIP Status`, `Signed System Volume` e `3rd Party Kexts` — todos devem estar como esperado (SIP e SSV *Enabled*).
* **[16] Teste de Estresse Térmico (`--stress`):** força 100% da CPU com cálculo de ponto flutuante para simular uso pesado. **O critério principal é a coluna `pressão`**, não o barulho: subir gradualmente até *Moderate* sob carga é normal; chegar a *Heavy*/*Trapping* rápido demais indica refrigeração comprometida.
  * ⚠️ **Ventoinha silenciosa NÃO é defeito.** O MacBook Pro 14"/16" (M2/M3/M4 Pro) é tão eficiente que costuma manter as ventoinhas quietas mesmo sob carga — isso é folga de refrigeração, e é *bom*. O Apple Silicon pode levar **1–3 minutos** de carga pesada até acelerá-las; para um teste auditivo real, use `./check.sh --stress=180`. O **MacBook Air não tem ventoinha alguma**.
  * 🚩 O sinal ruim é a combinação **pressão em Heavy/Trapping + ventoinha muda** (num Pro), que pode indicar ventoinha travada ou refrigeração comprometida.

---

## 🛠️ Diagnóstico de Hardware da Apple (Teste Físico)

O script acima valida dados do sistema operacional, mas não testa os componentes físicos (sensores, ventoinhas, módulos de memória defeituosos). Para isso, execute o teste nativo da Apple antes de inicializar o sistema.

### Como Executar:

1. Desligue o MacBook completamente.
2. Mantenha pressionado o **botão de energia (Touch ID)**.
3. Continue pressionando até ver a mensagem **"Carregando opções de inicialização..."** na tela.
4. Quando as opções aparecerem (ícone do HD e Configurações), solte o botão de energia.
5. Pressione e mantenha pressionada a combinação de teclas **Command (⌘) + D** no teclado.
6. O Mac reiniciará em uma tela de diagnóstico preta ou cinza. Selecione o idioma (se solicitado) e o teste começará automaticamente.

### Principais Códigos de Referência:

* **ADP000:** Nenhum problema encontrado. O hardware está 100% íntegro.
* **NDT001 a NDT006:** Possível problema no hardware de rede (Wi-Fi/Bluetooth).
* **NNN001:** Falha ao detetar o número de série (pode indicar que a placa lógica foi trocada por uma de terceiros ou reparada incorretamente).
* **PFM001 a PFM007:** Problema no Gerenciador de Energia (SMC) ou sensores térmicos. Geralmente faz as ventoinhas rodarem na rotação máxima e a CPU travar na velocidade mínima.
* **PFR001:** Problema no firmware da máquina.
* **PPT001 a PPT007:** Problema na bateria ou circuito de alimentação.
* **VFD001 a VFD007:** Problema no ecrã/tela ou na placa gráfica (GPU).
