# Squid para laboratório escolar

Configuração de proxy Squid usada no laboratório de desenvolvimento de sistemas do SESI CE283, compartilhada para que outras unidades possam adaptar.

O modelo é **whitelist**: nada passa por padrão, só o que está listado em `sites_permitidos.txt`. Sobre isso há um controle de modos que o professor troca em sala com um comando, sem editar arquivos.

```bash
proxy-modo.sh restrito                # padrão de aula
proxy-modo.sh restrito +ia 30         # libera IA por 30 minutos
proxy-modo.sh bloqueado +prova 90     # prova: só o sistema de avaliação
proxy-modo.sh aberto +ia 10.137.144.209   # libera tudo para um notebook só
```

Testado com Squid 6.13 em Debian, dentro de um container LXC no Proxmox.

---

## O que tem aqui

| Arquivo | Função |
|---|---|
| `squid.conf` | Configuração principal. **A ordem das regras é o que define o comportamento** — leia os comentários antes de mexer |
| `proxy-modo.sh` | Troca de modo (bases `bloqueado` / `restrito` / `aberto` e flags `+ia` / `+social` / `+prova`), com prazo automático |
| `modo.conf.exemplo` | Estado inicial em modo restrito. O `modo.conf` real é gerado pelo script e não é versionado |
| `sites_permitidos.txt` | Whitelist geral |
| `sites_ia.txt` | Ferramentas de IA — bloqueadas salvo com `+ia` |
| `sites_redes_sociais.txt` | Redes sociais — bloqueadas salvo com `+social` |
| `sites_prova.txt` | Domínios liberados no modo prova |
| `sites_horario_controlado.txt` | Bloqueados em horário de aula, em qualquer modo |
| `sites_sincronismo_controlado.txt` | OneDrive/SharePoint liberados só em janelas definidas |
| `sites_contorno.txt` | Subdomínios que burlariam a whitelist (tradutor, Meet, Chat) |
| `sites_ruido.txt` | Telemetria em loop de retry, barrada no início da cadeia por desempenho |
| `sites_jogos_bloqueados.txt` | Padrões de URL — desativado, ver comentário no `squid.conf` |
| `errorpage.css` | Estilo da página de bloqueio |
| `Manual-Squid.md` | Manual de operação do dia a dia (específico desta unidade) |

---

## Como a filtragem decide

O Squid para na primeira regra que casa. A ordem no `squid.conf` é:

1. Proteções básicas e corte de origem
2. **Bloqueios que nenhum modo libera:** telemetria, e os sites de horário controlado durante a aula
3. **`modo.conf`** — o que o professor ligou ou desligou
4. Sincronismo fora da janela e serviços de contorno
5. Whitelist
6. `deny all`

Por isso o horário controlado fica *antes* do `modo.conf`: nem o modo `aberto` libera essas plataformas durante a aula. E as listas de contorno ficam *antes* da whitelist, porque domínios amplos como `.google.com` arrastariam o tradutor junto.

---

## Adaptando para outra unidade

Os pontos abaixo são específicos desta escola. Ajuste antes de usar.

**No `squid.conf`:**

- `http_port` — o IP e as portas em que o Squid escuta.
- `acl localnet` — a faixa de IP dos computadores dos alunos.
- **PROXY protocol** — aqui o Squid fica atrás de um Nginx Proxy Manager, que repassa o IP real do aluno pelo PROXY protocol (`require-proxy-header`, `acl npm_upstream`, `proxy_protocol_access`). Se os computadores falam direto com o Squid, remova essas linhas e deixe um `http_port` simples. Sem o IP real, a liberação por máquina não funciona.
- `acl sistema_prova` e `acl porta_prova` — endereço do sistema de avaliação.
- `acl horario_aula` e `acl horario_sincronismo` — horários da sua unidade. **O fuso do servidor precisa estar correto**; em UTC, todas as janelas ficam deslocadas.

**No `proxy-modo.sh`:** a variável `REDE_LAB`, com a faixa dos alunos.

**Nas listas:** revise `sites_permitidos.txt` conforme as ferramentas das suas aulas.

---

## Instalação

```bash
# 1. Backup do que existe
cp -a /etc/squid /root/squid-backup-$(date +%F)

# 2. Listas primeiro: o squid.conf as referencia e nao sobe sem elas
cp sites_*.txt errorpage.css /etc/squid/
cp modo.conf.exemplo /etc/squid/modo.conf
cp squid.conf /etc/squid/

# 3. Script de modo
cp proxy-modo.sh /root/ && chmod +x /root/proxy-modo.sh

# 4. Validar e aplicar
squid -k parse && squid -k reconfigure
/root/proxy-modo.sh restrito
/root/proxy-modo.sh status
```

Sempre use `squid -k parse` antes de `reconfigure`: com erro de sintaxe, o reload não acontece e o proxy continua com a configuração anterior.

---

## O lado dos computadores dos alunos

O Squid só filtra o que passa por ele. Para a filtragem valer, os computadores precisam:

- **Ter o proxy travado** em nível de máquina, para o aluno não conseguir desativar.
- **Ter a saída direta bloqueada** no firewall (portas 80 e 443 para endereços públicos). Sem isso, qualquer coisa que ignore a configuração de proxy — VMs, navegadores portáteis, aplicativos — sai pela internet sem passar pelo filtro.
- **Ter as variáveis `HTTP_PROXY` e `HTTPS_PROXY`** definidas, porque npm, git e pip não usam o proxy do Windows.

Nesta unidade isso é feito por um script PowerShell aplicado em cada notebook.

---

## Diagnóstico

O comando que resolve a maioria dos "não abre":

```bash
tail -f /var/log/squid/access.log | grep TCP_DENIED
```

Cada linha mostra o IP de origem e o domínio recusado. Se o domínio for legítimo, acrescente-o ao `sites_permitidos.txt` e rode `squid -k parse && squid -k reconfigure`.
