# Guia de Atualização — TeamPass no k3s (Raspberry Pi 4)

Este documento descreve o passo a passo para atualizar o TeamPass de uma versão para outra no ambiente k3s.

---

## Migração 3.1.7.6 → 3.2.2.5 (última versão)

> Esta seção documenta a migração já realizada. Os manifestos da branch `k8s/3.2.2.5` já estão atualizados.

### Diferenças estruturais entre versões

A estrutura de diretórios mudou significativamente entre 3.1.7.6 e 3.2.x:

| Volume     | 3.1.7.6 (antigo)                    | 3.2.2.5 (novo)                        |
|------------|--------------------------------------|---------------------------------------|
| saltkey    | `/var/www/html/sk`                   | `/var/www/html/storage/sk`            |
| files      | `/var/www/html/files`                | `/var/www/html/storage/files`         |
| upload     | `/var/www/html/upload`               | `/var/www/html/storage/upload`        |
| config     | `/var/www/html/includes/config`      | `/var/www/html/storage/config`        |
| secrets    | `/var/www/html/secrets`              | `/var/www/html/secrets` *(igual)*     |
| vendor     | `./vendor`                           | `./app/vendor`                        |

Os **PVCs (dados persistentes) são os mesmos** — apenas o `mountPath` no manifesto muda.
O entrypoint migra o banco automaticamente ao detectar a diferença de versão.

### Passo a passo completo

```bash
# --- No Raspberry Pi ---

# 1. Fazer checkout do código mais novo (master = 3.2.2.5)
git fetch origin
git checkout master
git pull origin master

# 2. Build da nova imagem a partir do código 3.2.2.5
bash scripts/build-push.sh 3.2.2.5 localhost:30500

# 3. Fazer checkout da branch com os manifestos atualizados
git checkout k8s/3.2.2.5
git pull origin k8s/3.2.2.5

# 4. Aplicar (o pod antigo para, o novo sobe com a nova imagem e migra o banco)
kubectl apply -f k8s/05-teampass.yaml

# 5. Acompanhar o processo de migração automática
kubectl logs -n teampass deployment/teampass --follow
```

Você verá no log algo como:
```
🔄 Upgrading database from 3.1.7.6 to 3.2.2.5...
   ↳ Applying 3.2.0...
   ↳ Applying 3.2.1...
   ↳ Applying 3.2.2...
✅ Database upgraded to 3.2.2.5 (3 step(s) applied)
✅ TeamPass container is ready!
```

### Corrigir caminhos no banco após migração

Após a migração, corrija os caminhos armazenados no banco (via Adminer em `http://<IP>:30081` ou via kubectl):

```bash
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass << 'EOF'
UPDATE teampass_misc SET valeur = '/var/www/html/'
  WHERE intitule = 'cpassman_dir';

UPDATE teampass_misc SET valeur = 'http://<IP-DO-PI>:30080'
  WHERE intitule = 'cpassman_url';

UPDATE teampass_misc SET valeur = '/var/www/html/storage/upload/'
  WHERE intitule = 'path_to_upload_folder';

UPDATE teampass_misc SET valeur = '/var/www/html/storage/files/'
  WHERE intitule = 'path_to_files_folder';
EOF
```

Reinicie o pod após corrigir:
```bash
kubectl rollout restart deployment/teampass -n teampass
```

---

## Antes de começar qualquer atualização

> **NUNCA atualize sem fazer backup.**

### Verificar versão atual em execução

```bash
kubectl exec -n teampass deployment/teampass -- \
  grep "TP_VERSION" /var/www/html/app/config/include.php
```

### Verificar versão no banco

```bash
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass \
  -e "SELECT valeur FROM teampass_misc WHERE intitule IN ('teampass_version','cpassman_version');"
```

---

## 1. Backup (obrigatório)

### 1.1 Backup do banco de dados

```bash
kubectl exec -n teampass deployment/teampass-db -- \
  mysqldump -u root -p'SENHA_ROOT' \
  --single-transaction \
  teampass > backup_teampass_$(date +%Y%m%d_%H%M).sql
```

### 1.2 Anotar caminhos e URL atuais

```bash
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass \
  -e "SELECT intitule, valeur FROM teampass_misc
      WHERE intitule IN ('cpassman_url','cpassman_dir','path_to_upload_folder','path_to_files_folder');"
```

---

## 2. Build da nova imagem com Buildah

```bash
# Checkout do código da versão desejada
git checkout master   # ou a branch da versão
git pull

# Build e push
bash scripts/build-push.sh 3.2.2.5 localhost:30500
```

> As imagens base no Dockerfile já usam `docker.io/library/` para compatibilidade com buildah sem `unqualified-search registries`.

---

## 3. Atualizar tag no manifesto e aplicar

```bash
# Editar a tag em k8s/05-teampass.yaml
sed -i 's|localhost:30500/teampass:.*|localhost:30500/teampass:3.2.2.5|' k8s/05-teampass.yaml

# Aplicar
kubectl apply -f k8s/05-teampass.yaml

# Acompanhar rollout e migrações
kubectl rollout status deployment/teampass -n teampass
kubectl logs -n teampass deployment/teampass --follow
```

---

## 4. Verificação pós-atualização

```bash
# Versão no container
kubectl exec -n teampass deployment/teampass -- \
  grep "TP_VERSION" /var/www/html/app/config/include.php

# Versão no banco
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass \
  -e "SELECT valeur FROM teampass_misc WHERE intitule IN ('teampass_version','cpassman_version');"

# Status dos pods
kubectl get pods -n teampass
```

---

## 5. Rollback em caso de falha

```bash
# 1. Reverter para a imagem anterior
sed -i 's|localhost:30500/teampass:.*|localhost:30500/teampass:3.1.7.6|' k8s/05-teampass.yaml
kubectl apply -f k8s/05-teampass.yaml
kubectl rollout status deployment/teampass -n teampass

# 2. Restaurar banco se necessário
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass < backup_teampass_YYYYMMDD_HHMM.sql

# 3. Reiniciar
kubectl rollout restart deployment/teampass -n teampass
```

---

## Referência rápida de portas NodePort

| Serviço  | NodePort | URL de acesso              |
|----------|----------|----------------------------|
| TeamPass | `30080`  | `http://<IP-DO-PI>:30080`  |
| Adminer  | `30081`  | `http://<IP-DO-PI>:30081`  |
| Registry | `30500`  | usado pelo buildah no push |

---

## Comandos úteis do dia a dia

```bash
# Status geral
kubectl get all -n teampass

# Logs do TeamPass
kubectl logs -n teampass deployment/teampass --tail=50

# Logs do MariaDB
kubectl logs -n teampass deployment/teampass-db --tail=50

# Entrar no container do TeamPass
kubectl exec -it -n teampass deployment/teampass -- sh

# Entrar no banco
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u teampass -p'SENHA_DB' teampass

# Uso de recursos no Pi
kubectl top pods -n teampass
```