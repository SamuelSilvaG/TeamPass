#!/bin/bash
# ==============================================================================
# Script de Reset do Ambiente TeamPass no Kubernetes (k3s)
# Limpa banco MariaDB, chaves residuais e permissões para reiniciar a instalação
# ==============================================================================

set -euo pipefail

NAMESPACE="${1:-teampass}"

echo "======================================================"
echo "  🔄 TeamPass — Reset de Instalação (Namespace: ${NAMESPACE})"
echo "======================================================"

echo "📦 1/5. Localizando pods..."
DB_POD=$(kubectl get pod -n "$NAMESPACE" -l app=teampass-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
TP_POD=$(kubectl get pod -n "$NAMESPACE" -l app=teampass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$DB_POD" ] || [ -z "$TP_POD" ]; then
    echo "❌ Erro: Pods do MariaDB ou TeamPass não encontrados no namespace '$NAMESPACE'!"
    exit 1
fi

echo "   - Pod Banco : $DB_POD"
echo "   - Pod Web   : $TP_POD"

echo "🔑 2/5. Obtendo credenciais dos secrets..."
ROOT_PASS=$(kubectl get secret teampass-db-secret -n "$NAMESPACE" -o jsonpath='{.data.db-root-password}' | base64 -d)
DB_PASS=$(kubectl get secret teampass-db-secret -n "$NAMESPACE" -o jsonpath='{.data.db-password}' | base64 -d)

echo "🗄️  3/5. Recriando banco de dados no MariaDB..."
kubectl exec -n "$NAMESPACE" "$DB_POD" -- mariadb -u root -p"$ROOT_PASS" -e "
DROP DATABASE IF EXISTS teampass;
CREATE DATABASE teampass CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON teampass.* TO 'teampass'@'%';
FLUSH PRIVILEGES;
"
echo "   ✓ Banco 'teampass' recriado e limpo!"

echo "🧹 4/5. Limpando chaves e arquivos temporários no TeamPass..."
kubectl exec -n "$NAMESPACE" "$TP_POD" -c teampass -- sh -c "
rm -rf /var/www/html/sk/*
rm -f /var/www/html/includes/config/settings*.php
chmod 755 /var/www/html/includes/config
chmod 700 /var/www/html/sk
chown -R nginx:nginx /var/www/html/includes/config /var/www/html/sk /var/www/html/files /var/www/html/upload
"
echo "   ✓ Diretórios /var/www/html/sk e includes/config limpos!"

echo "🔍 5/5. Validando prontidão..."
TABLE_COUNT=$(kubectl exec -n "$NAMESPACE" "$DB_POD" -- mariadb -u teampass -p"$DB_PASS" teampass -sse "SELECT count(*) FROM information_schema.tables WHERE table_schema='teampass';")
echo "   - Tabelas no MariaDB: $TABLE_COUNT (esperado: 0)"

echo "======================================================"
echo "  ✅ Reset concluído com sucesso!"
echo "  Acesse: http://<NODE-IP>:30090/install/install.php"
echo "======================================================"