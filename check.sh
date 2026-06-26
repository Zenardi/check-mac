clear
echo "\033[1;36m=================================================\033[0m"
echo "\033[1;32m       DIAGNÓSTICO RÁPIDO DE HARDWARE E MDM      \033[0m"
echo "\033[1;36m=================================================\033[0m"

echo "\n\033[1;33m► 1. PROCESSADOR E MEMÓRIA RAM\033[0m"
system_profiler SPHardwareDataType | grep -E "Model Name|Chip|Total Number of Cores|Memory" | sed 's/^[ \t]*//'

echo "\n\033[1;33m► 2. ARMAZENAMENTO (SSD)\033[0m"
diskutil info / | grep -E "Container Total Space|Volume Total Space" | sed 's/^[ \t]*//'

echo "\n\033[1;33m► 3. SAÚDE DA BATERIA E CICLOS\033[0m"
system_profiler SPPowerDataType | grep -E "Cycle Count|Condition|Maximum Capacity" | sed 's/^[ \t]*//'

echo "\n\033[1;33m► 4. BLOQUEIO DE ATIVAÇÃO (iCloud)\033[0m"
system_profiler SPiBridgeDataType | grep -E "Activation Lock" | sed 's/^[ \t]*//'

echo "\n\033[1;33m► 5. GERENCIAMENTO REMOTO (MDM / EMPRESARIAL)\033[0m"
profiles status -type enrollment

echo "\n\033[1;36m=================================================\033[0m"
echo "\033[1;32m                 TESTE CONCLUÍDO                 \033[0m"
echo "\033[1;36m=================================================\033[0m"
