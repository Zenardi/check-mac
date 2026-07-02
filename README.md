# Guia de Diagnóstico e Check-up para MacBooks Apple Silicon

Este repositório contém um guia prático e um script de automação para realizar uma auditoria completa e profunda em MacBooks seminovos (com foco em chips Apple Silicon M1, M2, M3, M4, etc.) antes de fechar a compra.

O objetivo é extrair dados reais do hardware diretamente do sistema operacional e executar testes físicos para identificar fraudes, desgastes excessivos ou defeitos ocultos.

---

## 🚀 Como Usar o Script de Diagnóstico (Terminal)

Este método utiliza apenas ferramentas nativas do macOS (`system_profiler`, `diskutil`, `pmset`), dispensando a necessidade de instalar pacotes de terceiros (como Homebrew) na máquina do vendedor.

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

### 📄 Código do Script (`check.sh`)

```bash
#!/bin/bash

echo "=================================================="
echo "    DIAGNÓSTICO PROFUNDO - MACBOOK APPLE SILICON  "
echo "=================================================="

echo -e "\\n[1] ESPECIFICAÇÕES REAIS DO HARDWARE:"
system_profiler SPHardwareDataType | awk '/Model Name|Model Identifier|Chip|Memory|Serial Number/{print $0}'

echo -e "\\n[2] VERIFICAÇÃO DE BATERIA (Real vs Interface):"
system_profiler SPPowerDataType | awk '/Cycle Count|Condition|Maximum Capacity/{print $0}'

echo -e "\\n[3] SAÚDE DO SSD (Status S.M.A.R.T):"
diskutil info disk0 | grep -E "SMART Status|Solid State"
echo "Capacidade e uso da partição principal:"
df -h / | awk 'NR==2 {print "Tamanho: "$2" | Usado: "$3" | Livre: "$4}'

echo -e "\\n[4] VERIFICAÇÃO DE THROTTLING TÉRMICO:"
pmset -g therm

echo -e "\\n[5] BLOQUEIO DE ATIVAÇÃO (Activation Lock):"
system_profiler SPiBridgeDataType | grep "Activation Lock"

echo -e "\\n=================================================="
echo " Concluído. Analise os dados acima com cuidado."
echo "=================================================="

```

---

## 🔍 O que Analisar nos Resultados (Alertas e Red Flags)

* **[1] Hardware:** Verifique se o chip e a quantidade de memória RAM (Memory) batem exatamente com o anúncio.
* **[2] Bateria:** - A `Condition` deve ser **Normal**. Se exibir *Service Recommended*, a bateria precisará ser trocada em breve.
* Avalie o `Cycle Count` (Ciclos) em conjunto com a `Maximum Capacity` (Saúde da bateria). Se a saúde estiver abaixo de 80%, a Apple já considera a bateria degradada.


* **[3] SMART Status:** Deve ser **Verified**. Se aparecer *Failing*, o SSD está prestes a falhar e a placa lógica (onde o SSD é soldado) perderá a utilidade.
* **[4] Throttling Térmico (`pmset -g therm`):** O ideal é que indique `CPU_Speed_Limit = 100`. Se estiver abaixo disso (ex: 50 ou 70) sem nenhum app pesado rodando, a máquina está limitando o desempenho devido a superaquecimento ou defeito em sensores térmicos.
* **[5] Activation Lock (Bloqueio de Ativação):** Deve estar obrigatoriamente como **Disabled**. Se estiver *Enabled*, o Mac está vinculado à conta do iCloud de outra pessoa. **Não compre o aparelho** até que o vendedor desative essa opção e formate o Mac na sua frente.

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
