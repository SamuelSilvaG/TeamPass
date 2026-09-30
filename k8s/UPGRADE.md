# Guia de Atualização — TeamPass no k3s (Raspberry Pi 4)

Este documento descreve o passo a passo para atualizar o TeamPass de uma versão para outra no ambiente k3s.

---

## Antes de começar

> **NUNCA atualize sem fazer backup.** Uma atualização mal-sucedida pode corromper o banco ou os arquivos de criptografia.

### Verificar a versão atual em execução

```bash
kubectl exec -n teampass deployment/teampass -- \
  grep "TP_VERSION" /var/www/html/app/config/include.php
```

### Verificar a versão registrada no banco

```bash
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p"$(kubectl get secret teampass-db-secret -n teampass -o jsonpath='{.data.db-root-password}' | base64 -d)" teampass \
  -e "SELECT valeur FROM teampass_misc WHERE intitule = 'teampass_version' OR intitule = 'cpassman_version';"
```

---

## 1. Backup (obrigatório)

### 1.1 Backup do banco de dados

```bash
# Substitua SENHA_ROOT pelo valor real de MARIADB_ROOT_PASSWORD
kubectl exec -n teampass deployment/teampass-db -- \
  mysqldump -u root -p'SENHA_ROOT' \
  --single-transaction \
  teampass > backup_teampass_$(date +%Y%m%d_%H%M).sql

echo "Backup salvo em: backup_teampass_$(date +%Y%m%d_%H%M).sql"
```

### 1.2 Anotar os caminhos e URL atuais do banco

Guarde esses valores — serão necessários se o restore precisar corrigir os caminhos:

```bash
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass \
  -e "SELECT intitule, valeur FROM teampass_misc
      WHERE intitule IN ('cpassman_url','cpassman_dir','path_to_upload_folder','path_to_files_folder');"
```

---

## 2. Build da nova imagem com Buildah

Na raiz do repositório, no próprio Raspberry Pi:

```bash
# Sintaxe: ./scripts/build-push.sh <TAG> <REGISTRY>
bash scripts/build-push.sh 3.2.2.5 localhost:30500
```

O script:
- Usa `buildah` com `--platform linux/arm64`
- Passa o `IMAGE_TAG` como `TEAMPASS_VERSION` para o Dockerfile
- Faz push com `--tls-verify=false` para o registry local do k3s

> **Imagens base no Dockerfile já usam `docker.io/library/` para compatibilidade com buildah** (sem `unqualified-search registries` configurado).

---

## 3. Atualizar a tag no manifesto

Edite a imagem do deployment `k8s/05-teampass.yaml`:

```yaml
# Antes
image: localhost:30500/teampass:3.1.7.6

# Depois
image: localhost:30500/teampass:3.2.2.5
```

Ou use `sed` direto no Pi:

```bash
sed -i 's|localhost:30500/teampass:.*|localhost:30500/teampass:3.2.2.5|' k8s/05-teampass.yaml
```

---

## 4. Aplicar a atualização no cluster

```bash
# Reaplica apenas o deployment do TeamPass
kubectl apply -f k8s/05-teampass.yaml

# Força o reinício para usar a nova imagem (se a tag for a mesma)
kubectl rollout restart deployment/teampass -n teampass

# Acompanhar o rollout
kubectl rollout status deployment/teampass -n teampass

# Ver logs de migração automática
kubectl logs -n teampass deployment/teampass --follow
```

O entrypoint detecta automaticamente a diferença de versão e executa os scripts de migração SQL na ordem correta. Você verá no log:

```
🔄 Upgrading database from 3.1.7.6 to 3.2.2.5...
   ↳ Applying 3.2.0...
   ↳ Applying 3.2.1...
   ↳ Applying 3.2.2...
✅ Database upgraded to 3.2.2.5 (3 step(s) applied)
```

---

## 5. Verificação pós-atualização

```bash
# Versão em execução no container
kubectl exec -n teampass deployment/teampass -- \
  grep "TP_VERSION" /var/www/html/app/config/include.php

# Versão registrada no banco
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass \
  -e "SELECT valeur FROM teampass_misc WHERE intitule IN ('teampass_version','cpassman_version');"

# Status dos pods
kubectl get pods -n teampass

# Healthcheck
kubectl get pods -n teampass -o wide
```

Acesse o TeamPass no navegador e confirme que o login funciona normalmente.

---

## 6. Corrigir URL/caminhos após restore de backup

Se restaurou um backup de outro ambiente e o TeamPass retornou erro 500, corrija os caminhos no banco via Adminer (`http://<IP-DO-PI>:30081`) ou via kubectl:

```bash
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass << 'EOF'

-- Verificar valores atuais
SELECT intitule, valeur FROM teampass_misc
WHERE intitule IN ('cpassman_url','cpassman_dir','path_to_upload_folder','path_to_files_folder');

-- Corrigir para o ambiente k3s
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

Após corrigir, reinicie o pod:

```bash
kubectl rollout restart deployment/teampass -n teampass
```

---

## 7. Rollback em caso de falha

```bash
# 1. Reverter para a imagem anterior
sed -i 's|localhost:30500/teampass:.*|localhost:30500/teampass:3.1.7.6|' k8s/05-teampass.yaml
kubectl apply -f k8s/05-teampass.yaml

# 2. Aguardar o pod subir
kubectl rollout status deployment/teampass -n teampass

# 3. Restaurar o banco (se necessário)
kubectl exec -it -n teampass deployment/teampass-db -- \
  mysql -u root -p'SENHA_ROOT' teampass < backup_teampass_YYYYMMDD_HHMM.sql

# 4. Reiniciar
kubectl rollout restart deployment/teampass -n teampass
```

---

## Referência rápida de portas NodePort

| Serviço   | NodePort | URL de acesso                     |
|-----------|----------|-----------------------------------|
| TeamPass  | `30080`  | `http://<IP-DO-PI>:30080`         |
| Adminer   | `30081`  | `http://<IP-DO-PI>:30081`         |
| Registry  | `30500`  | usado pelo buildah no push        |

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