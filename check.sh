#!/bin/bash

echo "=================================================="
echo "    DIAGNÓSTICO PROFUNDO - MACBOOK APPLE SILICON  "
echo "=================================================="

echo -e "\n[1] ESPECIFICAÇÕES REAIS DO HARDWARE:"
system_profiler SPHardwareDataType | awk '/Model Name|Model Identifier|Chip|Memory|Serial Number/{print $0}'

echo -e "\n[2] VERIFICAÇÃO DE BATERIA (Real vs Interface):"
# Puxa os dados brutos de energia
system_profiler SPPowerDataType | awk '/Cycle Count|Condition|Maximum Capacity/{print $0}'

echo -e "\n[3] SAÚDE DO SSD (Status S.M.A.R.T):"
# Verifica o status de falha do disco interno principal
diskutil info disk0 | grep -E "SMART Status|Solid State"
echo "Capacidade e uso da partição principal:"
df -h / | awk 'NR==2 {print "Tamanho: "$2" | Usado: "$3" | Livre: "$4}'

echo -e "\n[4] VERIFICAÇÃO DE THROTTLING TÉRMICO:"
# Verifica se o sistema está limitando a CPU por aquecimento no momento
pmset -g therm

echo -e "\n[5] BLOQUEIO DE ATIVAÇÃO (Activation Lock):"
# Fundamental: Verifica se o Mac está atrelado ao iCloud de outra pessoa
system_profiler SPHardwareDataType | grep "Activation Lock"

echo -e "\n=================================================="
echo " Concluído. Analise os dados acima com cuidado."
echo "=================================================="
