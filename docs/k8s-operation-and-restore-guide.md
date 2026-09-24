# Guia de Operação, Replicabilidade e Restauração — TeamPass no Kubernetes (k3s)

Este documento descreve como o ambiente TeamPass no Kubernetes foi estruturado para ser **100% replicável** e como realizar **restaurações periódicas** de backups da aplicação original de produção.

---

## 1. Arquitetura e Estrutura Replicável

O ambiente é composto por:
* **Namespace:** `teampass`
* **Banco de Dados:** MariaDB (`app=teampass-db`) com PVC persistente para os dados.
* **Aplicação:** Nginx + PHP-FPM 8.3 (`app=teampass`) com PVCs persistentes:
  * `/var/www/html/sk`: Chave mestra criptográfica (SECUREFILE).
  * `/var/www/html/includes/config`: Configurações (`settings.php`, `include.php`).
  * `/var/www/html/files`: Uploads e backups.
  * `/var/www/html/upload`: Arquivos temporários.
  * `/var/www/html/secrets`: Chaves do Defuse.

### Correções Implementadas para Garantir Replicabilidade:
1. **Bootstrap Automático de Configurações (`Dockerfile` e `docker-entrypoint.sh`):**
   * Durante o build da imagem, é gerado um backup template em `includes/config.dist`.
   * Quando o pod sobe pela primeira vez sobre um PVC vazio, o `docker-entrypoint.sh` popula os arquivos essenciais (`include.php`, `.htaccess`) automaticamente.
2. **Correção do Instalador (`run.step6.php`):**
   * A alteração dinâmica de permissões foi neutralizada para evitar lockout de execução no Nginx dentro do container.
3. **Polyfill de Clipboard (`includes/core/load.js.php`):**
   * Garante a cópia de senhas e logins mesmo em acessos via HTTP (sem SSL/HTTPS), utilizando fallback com `document.execCommand('copy')`.

---

## 2. Procedimento de Restauração de Backups Periódicos

Sempre que você quiser restaurar um backup atualizado da aplicação original de produção para manter este ambiente sincronizado:

### Passo 1: Fazer o Upload do Backup na Interface
1. Faça login no TeamPass: `http://192.168.3.2:30090/`
2. Vá em **Settings / Administrador** -> **Backups** -> aba **Restore**.
3. Selecione o arquivo `.sql` do seu backup de produção e clique em **Upload**.
4. O TeamPass gerará um comando de CLI contendo o caminho do arquivo e o `--auth-token`, por exemplo:
   ```text
   cd '/var/www/html' && sudo -u 'nginx' php scripts/restore.php --file '/var/www/html/files/SEU_ARQUIVO.sql' --auth-token 'SEU_TOKEN'
   ```

### Passo 2: Executar a Restauração e Ajuste Automático
No nó Raspberry Pi (ou máquina com `kubectl`), execute o script automatizado passando os parâmetros gerados:

```bash
bash ~/TeamPass/scripts/k8s-restore.sh --file '/var/www/html/files/SEU_ARQUIVO.sql' --auth-token 'SEU_TOKEN'
```

O script cuidará de tudo:
1. Executa a restauração dentro do pod com o usuário `nginx`.
2. Corrige automaticamente os caminhos legados do banco de produção (`/var/www/html/TeamPass/` -> `/var/www/html`).
3. Garante o symlink de compatibilidade `/var/www/html/TeamPass`.
4. Testa e valida o status HTTP 200 da aplicação.

---

## 3. Scripts Utilitários Disponíveis

Todos os scripts estão em `~/TeamPass/scripts/`:

| Script | Finalidade | Comando |
|---|---|---|
| **`k8s-restore.sh`** | Executa o restore e corrige os caminhos de uma vez só | `bash ~/TeamPass/scripts/k8s-restore.sh --file '...' --auth-token '...'` |
| **`post-restore-fix.sh`** | Ajusta caminhos e symlinks se você rodar o restore manualmente | `bash ~/TeamPass/scripts/post-restore-fix.sh` |
| **`reset-install.sh`** | Reseta o banco e chaves para reiniciar a instalação do zero | `bash ~/TeamPass/scripts/reset-install.sh` |
| **`build-push.sh`** | Reconstrói a imagem Docker para ARM64 no registry local | `bash ~/TeamPass/scripts/build-push.sh 3.1.7.6` |

---

## 4. Como Reconstruir e Reaplicar do Zero

Se você precisar recriar todo o cluster ou subir em outro nó:

```bash
# 1. Build da imagem local ARM64
cd ~/TeamPass
bash scripts/build-push.sh 3.1.7.6

# 2. Aplicar os manifests do Kubernetes
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-secrets.yaml
kubectl apply -f k8s/02-configmap.yaml
kubectl apply -f k8s/03-pvc.yaml
kubectl apply -f k8s/04-mariadb.yaml
kubectl apply -f k8s/05-teampass.yaml
```