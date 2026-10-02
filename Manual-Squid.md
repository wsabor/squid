# Manual de Operação — Squid Proxy

**Laboratório de Informática · SENAI 9.14 - CE283**
Revisão: 02/10/2026

Este manual cobre a operação do dia a dia do proxy: como conectar no servidor, como ligar e desligar o bloqueio, como liberar um site e como diagnosticar quando alguém reclama que "não abre".

---

## 1. Como o sistema está montado

```
Notebook do aluno (10.137.144.201–234)
        │  proxy configurado: 10.187.226.125:8150
        ▼
T420 (ss283ehyper1) — alias 10.187.226.125
        │  DNAT
        ▼
CT100 — Nginx Proxy Manager (10.0.0.2)
        │  stream 8150, com PROXY protocol
        ▼
CT101 — Squid (10.0.0.5:3129)
```

O PROXY protocol faz o Squid enxergar o IP real de cada notebook. Isso é o que permite liberar acesso para uma máquina específica.

O modelo é **whitelist**: por padrão nada passa, só o que está explicitamente liberado.

> **Importante:** os notebooks têm o proxy travado por política de máquina (HKLM). O aluno não consegue desativá-lo — ele não é administrador. Não adianta tentar liberar acesso mexendo no notebook; tudo se resolve no servidor.

Desde o script Fix-Veyon V11, o **Squid é o único caminho para a internet**. O firewall de cada notebook bloqueia as portas 80 e 443 para qualquer endereço público, então nada sai direto: nem navegador portátil, nem VM, nem ferramenta de linha de comando. A rede interna (servidores, sistema de prova, redes de IoT) continua acessível normalmente.

Consequência prática: **tudo que os alunos usam precisa estar na whitelist**, inclusive o que antes funcionava "por fora" — o Spotify, o npm, o git, o pip.

A configuração completa (squid.conf, listas e este manual) está versionada no repositório privado `github.com/wsabor/squid`.

---

## 2. Preparação do acesso (fazer uma vez)

O servidor **não aceita login por senha**. É obrigatório usar chave SSH.

### 2.1. Gerar sua chave

No seu computador (Mac ou Linux, no Terminal; no Windows, no PowerShell):

```bash
ssh-keygen -t ed25519 -C "seu.nome@senai"
```

Aceite o caminho padrão. Defina uma senha para a chave (opcional, mas recomendado).

Isso cria dois arquivos:

| Arquivo | O que é | Pode compartilhar? |
|---|---|---|
| `~/.ssh/id_ed25519` | chave **privada** | **NUNCA** |
| `~/.ssh/id_ed25519.pub` | chave **pública** | sim |

### 2.2. Enviar a chave pública

Mostre o conteúdo da chave pública:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copie a linha inteira (começa com `ssh-ed25519`) e envie ao Wagner. Ele adiciona no servidor.

### 2.3. Instalação da chave (feito pelo Wagner)

No T420, acrescentar a linha recebida em:

```
/root/.ssh/authorized_keys
```

### 2.4. Testar

```bash
ssh -p 9922 root@10.187.226.79
```

Se entrar sem pedir senha do servidor, está pronto.

> Para facilitar, dá para criar um atalho em `~/.ssh/config`:
>
> ```
> Host t420
>     HostName 10.187.226.79
>     Port 9922
>     User root
> ```
>
> Depois basta digitar `ssh t420`.

---

## 3. Chegando no Squid

O Squid não roda no T420 diretamente — ele está dentro do container **CT101**.

```bash
ssh -p 9922 root@10.187.226.79    # 1. entra no T420
pct enter 101                      # 2. entra no container do Squid
```

Para sair do container: `exit` (volta ao T420). Outro `exit` encerra a sessão.

Confirme que está no lugar certo:

```bash
systemctl status squid
```

Deve aparecer `active (running)`.

---

## 4. Operação do dia a dia

### 4.1. Controlar a filtragem

O controle funciona com **três bases** e **três flags**. Todos os comandos rodam **dentro do CT101**.

**As bases**, da mais restritiva para a mais permissiva:

| Base | O que faz |
|---|---|
| `bloqueado` | Nada passa — **provas e avaliações** |
| `restrito` | Só passa o que está na whitelist — **padrão de aula** |
| `aberto` | Tudo passa, sem whitelist |

**As flags** liberam categorias que normalmente ficam bloqueadas:

| Flag | O que libera | Usar com |
|---|---|---|
| `+ia` | Ferramentas de IA (ChatGPT, Claude, Gemini, Copilot…) | `restrito`, `aberto` |
| `+social` | Redes sociais e mensageria (Instagram, TikTok, Discord…) | `restrito`, `aberto` |
| `+prova` | O sistema de prova em `10.187.226.125:8104` | `bloqueado` |

Sem a flag, a categoria fica bloqueada — **inclusive na base `aberto`**. Isso é intencional: `aberto` sozinho significa "internet liberada, mas sem redes sociais e sem IA".

O script avisa e ignora flags que não fazem sentido com a base escolhida (como `+ia` junto de `bloqueado`).

### 4.2. As combinações

```bash
/root/proxy-modo.sh restrito                 # padrão de aula
/root/proxy-modo.sh restrito +ia             # whitelist + IA
/root/proxy-modo.sh restrito +social         # whitelist + redes sociais
/root/proxy-modo.sh restrito +ia +social     # whitelist + as duas
/root/proxy-modo.sh bloqueado                # nada passa
/root/proxy-modo.sh bloqueado +prova         # só o sistema de prova
/root/proxy-modo.sh aberto                   # tudo, menos IA e redes sociais
/root/proxy-modo.sh aberto +ia               # tudo + IA
/root/proxy-modo.sh aberto +ia +social       # tudo liberado
```

Resumindo o efeito de cada combinação:

| Comando | Internet | IA | Redes sociais |
|---|---|---|---|
| `bloqueado` | nenhuma | — | — |
| `bloqueado +prova` | só o sistema de prova | — | — |
| `restrito` | whitelist | bloqueada | bloqueadas |
| `restrito +ia` | whitelist | **liberada** | bloqueadas |
| `restrito +social` | whitelist | bloqueada | **liberadas** |
| `aberto` | tudo | bloqueada | bloqueadas |
| `aberto +ia` | tudo | **liberada** | bloqueadas |
| `aberto +ia +social` | tudo | **liberada** | **liberadas** |

> **Atenção com a base `aberto`:** ela suspende também os bloqueios de contorno (tradutor, Meet, Chat) e o controle de sincronismo. Use só quando necessário.

### 4.3. Modo prova

Para avaliações, a base `bloqueado` corta o acesso à internet. Com a flag `+prova`, o sistema de simulado continua acessível:

```bash
/root/proxy-modo.sh bloqueado +prova 90        # prova de 90 minutos
/root/proxy-modo.sh bloqueado +prova 10.137.144.209 90   # só numa máquina
```

Três coisas que valem saber sobre esse modo:

**O Veyon continua funcionando.** Ele usa a porta 11100 direta, sem passar pelo proxy. Monitoramento, bloqueio de tela e demonstração seguem disponíveis durante a prova.

**Use sempre um prazo.** Bloqueio esquecido significa a turma seguinte sem internet. Com os minutos definidos, a sala reabre sozinha ao fim do tempo.

**Teste antes da prova real.** Rode em uma máquina e confirme que a plataforma abre completa. Se abrir quebrada, algum recurso está vindo de outro domínio — descubra qual com:

```bash
tail -f /var/log/squid/access.log | grep TCP_DENIED | grep 10.137.144.
```

### 4.4. Aplicar só a algumas máquinas

Passe um ou mais IPs. As demais máquinas continuam como estavam:

```bash
/root/proxy-modo.sh restrito +ia 10.137.144.209
/root/proxy-modo.sh aberto +social 10.137.144.209 10.137.144.215
```

O IP segue a regra **hostname + 200**: NOTE09 = `.209`, NOTE15 = `.215`, NOTE34 = `.234`.

> Se a liberação por IP não funcionar, o primeiro suspeito é o número do IP. Confira no `status` qual endereço foi gravado.

### 4.5. Prazo automático — recomendado

Qualquer combinação aceita um número de minutos como último argumento. Ao fim do prazo, o Squid volta sozinho para `restrito`:

```bash
/root/proxy-modo.sh aberto +social 30            # libera por 30 min
/root/proxy-modo.sh restrito +ia 10.137.144.209 45
```

**Use prazo sempre que liberar algo.** Sem ele, a liberação fica valendo até alguém lembrar de desfazer — e é exatamente isso que costuma ser esquecido. O script avisa quando você libera sem definir prazo.

Para fechar antes da hora, é só voltar ao padrão:

```bash
/root/proxy-modo.sh restrito
```

O `restrito` também cancela qualquer prazo pendente.

### 4.6. Ver o que está ativo

```bash
/root/proxy-modo.sh status
```

Mostra a combinação em vigor, em quais máquinas, se há volta automática agendada e o histórico das últimas trocas. **Rode antes de mudar qualquer coisa.**

### 4.7. Liberar um site novo

Cenário típico: um site necessário para a aula está bloqueado.

Edite a whitelist dentro do CT101:

```bash
nano /etc/squid/sites_permitidos.txt
```

Acrescente o domínio na seção correspondente. Use o formato com ponto na frente para cobrir subdomínios:

```
.exemplo.com.br
```

| Formato | Cobre |
|---|---|
| `.exemplo.com` | `exemplo.com`, `www.exemplo.com`, `api.exemplo.com` |
| `www.exemplo.com` | somente `www.exemplo.com` |

Salve (`Ctrl+O`, `Enter`, `Ctrl+X`) e aplique:

```bash
squid -k parse && squid -k reconfigure
```

> **Sempre use os dois comandos juntos.** O `parse` valida a configuração; se houver erro, o `reconfigure` não roda e o Squid continua funcionando com a configuração anterior. Rodar `reconfigure` sozinho pode derrubar o proxy da sala inteira.

### 4.8. Onde fica cada coisa

Todos os arquivos em `/etc/squid/` dentro do CT101:

| Arquivo | Conteúdo |
|---|---|
| `sites_permitidos.txt` | Whitelist geral — **é aqui que se libera site novo** |
| `sites_redes_sociais.txt` | Redes sociais — bloqueadas salvo com a flag `+social` |
| `sites_ia.txt` | Ferramentas de IA — bloqueadas salvo com a flag `+ia` |
| `sites_prova.txt` | Domínios liberados durante prova (flag `+prova`) |
| `sites_ruido.txt` | Telemetria barrada cedo, por desempenho |
| `sites_contorno.txt` | Tradutor, Meet, Chat — burlam a whitelist por herança |
| `sites_horario_controlado.txt` | ead, ava, livre — bloqueados em horário de aula |
| `sites_sincronismo_controlado.txt` | OneDrive/SharePoint em janelas específicas |
| `squid.conf` | Configuração principal e ordem das regras |
| `modo.conf` | **Gerado pelo script — não editar à mão** |

### 4.9. O que nenhuma flag libera

Três bloqueios rodam **antes** do controle de modo e valem em qualquer combinação, inclusive `aberto +ia +social`:

| Bloqueio | Por quê |
|---|---|
| `sites_ruido.txt` | Telemetria em loop de retry — barrada por desempenho |
| `sites_redes_sociais.txt` | Só a flag `+social` libera; nenhuma base sozinha |
| **ead / ava / livre em horário de aula** | Política: não devem ser acessados das 7h às 11h e das 12h às 16h, em nenhuma circunstância |

O horário de aula está definido na regra 3c do `squid.conf`. Fora dessas faixas — almoço, depois das 16h, madrugada e fim de semana — o acesso é normal.

> Consequência prática: **não é possível fazer prova no AVA durante o horário de aula.** A regra de horário vence a flag `+prova`. Se a política mudar, o ajuste é na regra 3c, não na lista de prova.

Um caso conhecido: o `.bing.com` está na lista de ruído, e o Copilot do Edge depende dele. Por isso o Copilot não funciona nem com `+ia` ativa.

---

## 5. Diagnóstico

### 5.1. "Professor, o site não abre"

Este comando mostra em tempo real o que está sendo bloqueado:

```bash
tail -f /var/log/squid/access.log | grep TCP_DENIED | grep 10.137.144.
```

Peça ao aluno para tentar acessar de novo. Cada linha que aparecer mostra o IP do notebook e o domínio recusado. Encerre com `Ctrl+C`.

Muitas vezes o site principal está liberado mas ele carrega recursos de outro domínio. Nesse caso vão aparecer vários domínios — todos precisam entrar na whitelist.

### 5.2. "O npm install (ou git, ou pip) não funciona"

Ferramentas de linha de comando não usam o proxy do Windows — usam as variáveis `HTTP_PROXY` e `HTTPS_PROXY`, que o script V11 define em cada notebook. A mensagem de erro no terminal indica a causa:

| Mensagem | Causa | Solução |
|---|---|---|
| `connect EACCES ...:443` | A ferramenta tentou sair direto e o firewall barrou — as variáveis não estão valendo | Fechar e reabrir o VS Code **por completo**. Se persistir, rodar o V11 de novo na máquina |
| `tunneling socket ... statusCode=403` | Passou pelo Squid, mas o domínio não está na whitelist | Descobrir o domínio pelo `tail -f` da seção 5.1 e acrescentar ao `sites_permitidos.txt` |

Domínios que pacotes costumam buscar durante a instalação: `.nodejs.org` (compilação de módulos nativos), `binaries.prisma.sh` (Prisma) e `objects.githubusercontent.com` (binários hospedados no GitHub).

### 5.3. Ver o que uma máquina específica está acessando

```bash
grep 10.137.144.215 /var/log/squid/access.log | tail -30
```

### 5.4. Confirmar a combinação ativa

```bash
/root/proxy-modo.sh status
```

### 5.5. O Squid está no ar?

```bash
systemctl status squid
```

---

## 6. Situações de emergência

### Proxy fora do ar — a sala inteira sem internet

```bash
systemctl status squid          # ver o que houve
squid -k parse                  # mostra erros de configuração
systemctl restart squid
```

Se o `parse` acusar erro, alguma edição recente quebrou a configuração. Restaure o backup:

```bash
cp -a /root/squid-backup-AAAA-MM-DD/. /etc/squid/
squid -k parse && systemctl restart squid
```

### O arquivo `modo.conf` sumiu

O Squid não inicia sem ele. Recrie:

```bash
/root/proxy-modo.sh restrito
```

### Antes de qualquer mudança grande

```bash
cp -a /etc/squid /root/squid-backup-$(date +%F)
```

---

## 7. O que não fazer

- **Não editar `modo.conf` à mão.** Ele é reescrito pelo script; qualquer edição se perde na próxima troca.
- **Não rodar `reconfigure` sem o `parse` antes.** Sempre `squid -k parse && squid -k reconfigure`.
- **Não colocar domínios de IA no `sites_permitidos.txt`.** Eles têm lugar próprio no `sites_ia.txt`. Duplicar cria duas fontes de verdade e o comportamento fica imprevisível.
- **Não reativar a regra 3b do `squid.conf`** (o deny fixo de redes sociais, que está comentado). Se voltar a valer, a flag `+social` para de funcionar sem apresentar erro nenhum.
- **Não mexer na ordem das regras do `squid.conf`** sem entender o efeito. O Squid para na primeira regra que casa — mover um `deny` para depois do `allow` da whitelist o torna inútil.
- **Não tentar resolver bloqueio no notebook do aluno.** A configuração está travada por política e é intencional.
- **Não liberar sem prazo.** Use os minutos no fim do comando; é o que garante a volta ao padrão mesmo se ninguém lembrar.

---

## 8. Referência rápida

```bash
# Conectar
ssh -p 9922 root@10.187.226.79
pct enter 101

# Ver o que está ativo
/root/proxy-modo.sh status

# Voltar ao padrão de aula
/root/proxy-modo.sh restrito

# Prova (sempre com prazo)
/root/proxy-modo.sh bloqueado +prova 90

# Liberar (sempre com prazo em minutos)
/root/proxy-modo.sh restrito +ia 30
/root/proxy-modo.sh restrito +social 20
/root/proxy-modo.sh aberto +ia +social 30

# Aplicar só numa máquina
/root/proxy-modo.sh restrito +ia 10.137.144.209 45

# Liberar site novo
nano /etc/squid/sites_permitidos.txt
squid -k parse && squid -k reconfigure

# Diagnóstico
tail -f /var/log/squid/access.log | grep TCP_DENIED | grep 10.137.144.
systemctl status squid

# Backup
cp -a /etc/squid /root/squid-backup-$(date +%F)
```

**Bases:** `bloqueado` (nada) · `restrito` (whitelist) · `aberto` (tudo)
**Flags:** `+ia` · `+social` · `+prova` — sem a flag, a categoria fica bloqueada

**IPs dos notebooks:** hostname + 200 → NOTE01 = `.201` … NOTE34 = `.234`

---

*Dúvidas ou situações não cobertas aqui: falar com o Wagner antes de alterar a configuração.*
