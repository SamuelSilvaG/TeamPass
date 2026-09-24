#!/bin/bash
# ==============================================================================
# TeamPass k8s - Correção Rápida de Caminhos Pós-Restore
# Use sempre que restaurar um backup de outro servidor/ambiente
# Uso:
#   bash scripts/post-restore-fix.sh [namespace]
# ==============================================================================

set -euo pipefail

NAMESPACE="${1:-teampass}"

echo "======================================================"
echo "  🔧 TeamPass - Ajuste de Caminhos Pós-Restore"
echo "======================================================"

TP_POD=$(kubectl get pod -n "$NAMESPACE" -l app=teampass -o jsonpath='{.items[0].metadata.name}')
DB_POD=$(kubectl get pod -n "$NAMESPACE" -l app=teampass-db -o jsonpath='{.items[0].metadata.name}')
DB_PASS=$(kubectl get secret teampass-db-secret -n "$NAMESPACE" -o jsonpath='{.data.db-password}' | base64 -d)

echo "1. Ajustando paths na tabela teampass_misc..."
kubectl exec -n "$NAMESPACE" "$DB_POD" -- mariadb -u teampass -p"$DB_PASS" teampass -e "
UPDATE teampass_misc SET valeur = '/var/www/html' WHERE intitule = 'cpassman_dir';
UPDATE teampass_misc SET valeur = '/var/www/html/upload' WHERE intitule = 'path_to_upload_folder';
UPDATE teampass_misc SET valeur = '/var/www/html/files' WHERE intitule = 'path_to_files_folder';
UPDATE teampass_misc SET valeur = '/var/www/html/backups' WHERE intitule = 'bck_script_path';
"

echo "2. Criando symlink /var/www/html/TeamPass -> /var/www/html no pod..."
kubectl exec -n "$NAMESPACE" "$TP_POD" -c teampass -- ln -sfn /var/www/html /var/www/html/TeamPass

echo "3. Testando HTTP em index.php..."
curl -sI http://127.0.0.1:30090/index.php 2>/dev/null | head -n 5 || curl -sI http://192.168.3.2:30090/index.php | head -n 5

echo "======================================================"
echo "  ✅ Ajustes concluídos com sucesso!"
echo "======================================================"