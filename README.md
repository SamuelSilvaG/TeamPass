# TeamPass no k3s

Este projeto sobe o TeamPass no `k3s` com `NodePort` e uma imagem `arm64` própria, construída localmente com `docker buildx` a partir do código oficial do TeamPass.

## Build das imagens

```powershell
.\scripts\build-teampass-arm64.ps1
```

A imagem atual é enviada para `192.168.3.159:30500/teampass:3.1.7.5-arm64-r5` e o cluster faz pull por `localhost:30500/teampass:3.1.7.5-arm64-r5`.

Para gerar a imagem legada usada na restauração do backup:

```powershell
.\scripts\build-teampass-3.1.4.30-arm64.ps1
```

Essa imagem fica em `192.168.3.159:30500/teampass:3.1.4.30-arm64` e também deve existir no registry local do nó como `localhost:30500/teampass:3.1.4.30-arm64`.

## Aplicar

```powershell
kubectl apply -k .\k8s
```

Para usar explicitamente a versão mais nova:

```powershell
kubectl kustomize --load-restrictor LoadRestrictionsNone .\k8s\overlays\latest | kubectl apply -f -
```

Para subir a versão `3.1.4.30` e restaurar backup:

```powershell
kubectl kustomize --load-restrictor LoadRestrictionsNone .\k8s\overlays\legacy-3.1.4.30 | kubectl apply -f -
```

## Acesso

- TeamPass: `http://192.168.3.159:30088`

## Instalação do TeamPass

Preencha o instalador com:

- Absolute path of the application: `/var/www/html`
- URL of the application: `http://192.168.3.159:30088`
- Absolute path to secure key: `/var/TeampassSecurity`
- Saltkey absolute path: `/var/www/html/sk`
- Database host: `db`
- Database port: `3306`
- Database name: `teampass`
- Database login: `teampass`
- Database password: `11111@111`
- Table prefix: `teampass_`

## Observações

- A imagem oficial `teampass/teampass` não publica `arm64`, então este projeto usa uma imagem própria para Raspberry Pi.
- Os dados persistentes seguem o modelo oficial: `sk`, `files`, `upload`, `secure key` e banco.
- O acesso continua em `NodePort` por enquanto.
- A imagem atual remove automaticamente a pasta `install` assim que o `settings.php` é criado, evitando o bloqueio de login após a instalação.
