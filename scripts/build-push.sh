#!/bin/bash
# ============================================
# TeamPass - Build & Push com Buildah
# Alvo: k3s no Raspberry Pi 4 (ARM64)
# ============================================
# Uso:
#   ./scripts/build-push.sh [IMAGE_TAG] [REGISTRY]
#
# Exemplos:
#   ./scripts/build-push.sh v1
#   ./scripts/build-push.sh 3.1.7.6 192.168.1.100:30500
#   ./scripts/build-push.sh 3.1.7.6 localhost:30500

set -euo pipefail

# ----------------------------------------
# Parâmetros (mesma convenção do projeto)
# ----------------------------------------
IMAGE_TAG="${1:-v1}"
REGISTRY="${2:-localhost:30500}"
IMAGE_NAME="teampass"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# ----------------------------------------
# Validações
# ----------------------------------------
if ! command -v buildah &> /dev/null; then
    echo "❌ Erro: buildah não encontrado. Instale com: sudo apt install buildah"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🔐 TeamPass — Build & Push"
echo "  Imagem  : ${FULL_IMAGE}"
echo "  Plataforma: linux/arm64 (Raspberry Pi 4)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Garantir que estamos na raiz do repositório
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# ----------------------------------------
# Build com Buildah (nativo ARM64 no Pi)
# ----------------------------------------
echo "🔨 Construindo imagem com buildah..."
buildah build \
    --platform linux/arm64 \
    --build-arg TEAMPASS_VERSION="${IMAGE_TAG}" \
    --tag "${FULL_IMAGE}" \
    --file Dockerfile \
    .

echo "✅ Build concluído: ${FULL_IMAGE}"

# ----------------------------------------
# Push para registry local do k3s (30500)
# ----------------------------------------
echo "📤 Enviando para registry ${REGISTRY}..."

# O registry local do k3s geralmente não tem TLS
buildah push \
    --tls-verify=false \
    "${FULL_IMAGE}" \
    "docker://${FULL_IMAGE}"

echo ""
echo "✅ Imagem enviada com sucesso!"
echo ""
echo "🚀 Para aplicar no k3s:"
echo "   kubectl apply -k k8s/"
echo ""
echo "🔄 Para atualizar deployment existente:"
echo "   kubectl rollout restart deployment/teampass -n teampass"
echo ""