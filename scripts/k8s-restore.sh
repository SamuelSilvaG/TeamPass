#!/bin/bash
# ==============================================================================
# TeamPass k8s - Script de Restauração Completa e Ajuste Pós-Restore
# Uso:
#   bash scripts/k8s-restore.sh --file "<caminho_no_container>" --auth-token "<token>"
# Exemplo:
#   bash scripts/k8s-restore.sh --file '/var/www/html/files/backup.sql' --auth-token 'U77R7...'
# ==============================================================================

set -euo pipefail

NAMESPACE="teampass"
FILE=""
AUTH_TOKEN=""
FORCE_DISCONNECT="--force-disconnect"

# Processar argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    --file)
      FILE="$2"
      shift 2
      ;;
    --auth-token)
      AUTH_TOKEN="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    *)
      echo "Parâmetro desconhecido: $1"
      exit 1
      ;;
  esac
done

if [ -z "$FILE" ] || [ -z "$AUTH_TOKEN" ]; then
    echo "❌ Erro: --file e --auth-token são obrigatórios!"
    echo "Uso: bash scripts/k8s-restore.sh --file '/var/www/html/files/backup.sql' --auth-token 'TOKEN'"
    exit 1
fi

echo "======================================================"
echo "  🔄 TeamPass - Restauração e Sincronização de Backup"
echo "======================================================"

echo "📦 1/4. Localizando pods no namespace '$NAMESPACE'..."
TP_POD=$(kubectl get pod -n "$NAMESPACE" -l app=teampass -o jsonpath='{.items[0].metadata.name}')
DB_POD=$(kubectl get pod -n "$NAMESPACE" -l app=teampass-db -o jsonpath='{.items[0].metadata.name}')

echo "   - Pod TeamPass : $TP_POD"
echo "   - Pod MariaDB  : $DB_POD"

echo "🚀 2/4. Executando scripts/restore.php no pod..."
kubectl exec -n "$NAMESPACE" "$TP_POD" -c teampass -- su -s /bin/sh nginx -c "
cd /var/www/html && php scripts/restore.php --file '$FILE' --auth-token '$AUTH_TOKEN' $FORCE_DISCONNECT
"

echo "🔧 3/4. Aplicando correções pós-restauração (paths e symlinks)..."
DB_PASS=$(kubectl get secret teampass-db-secret -n "$NAMESPACE" -o jsonpath='{.data.db-password}' | base64 -d)

# Ajustar caminhos de produção para a estrutura de containers
kubectl exec -n "$NAMESPACE" "$DB_POD" -- mariadb -u teampass -p"$DB_PASS" teampass -e "
UPDATE teampass_misc SET valeur = '/var/www/html' WHERE intitule = 'cpassman_dir';
UPDATE teampass_misc SET valeur = '/var/www/html/upload' WHERE intitule = 'path_to_upload_folder';
UPDATE teampass_misc SET valeur = '/var/www/html/files' WHERE intitule = 'path_to_files_folder';
UPDATE teampass_misc SET valeur = '/var/www/html/backups' WHERE intitule = 'bck_script_path';
"

# Symlink preventivo para caminhos legados
kubectl exec -n "$NAMESPACE" "$TP_POD" -c teampass -- ln -sfn /var/www/html /var/www/html/TeamPass

echo "🔍 4/4. Validando status da aplicação..."
HTTP_STATUS=$(curl -sI -o /dev/null -w "%{http_code}" http://127.0.0.1:30090/index.php 2>/dev/null || curl -sI -o /dev/null -w "%{http_code}" http://192.168.3.2:30090/index.php)

echo "======================================================"
if [ "$HTTP_STATUS" = "200" ]; then
    echo "  ✅ Restauração e sincronização concluídas com sucesso!"
    echo "  Status HTTP: 200 OK"
    echo "  Acesse: http://192.168.3.2:30090/"
else
    echo "  ⚠️  Restauração concluída, mas HTTP retornou código: $HTTP_STATUS"
fi
echo "======================================================"