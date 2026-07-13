# telegraf-sw-dell

Helm chart para monitoreo SNMP de switches Dell OS10 via Telegraf, desplegado con ArgoCD.

Recolecta métricas SNMP de switches Dell (sysName, sysUpTime, interfaces, CPU, chasis, fuentes de poder, ventiladores) y las expone en formato Prometheus para scraping.

## Arquitectura

```
Prometheus (grafana-operaciones)
  |
  | scrape :9273/metrics (cada 30-60s)
  v
Telegraf (1 pod por site)
  |
  | SNMP v2 UDP/161
  v
Switches Dell OS10 (34 por site)
```

- **Cluster origen:** TTOOLS-CUY (donde corre ArgoCD, ns `whitecicd`)
- **Cluster destino:** wcr-operaciones (donde corren los pods, ns `telegraf-sw-dell`)
- **Namespace destino:** `telegraf-sw-dell`
- **GitLab repo:** `https://whitecicd-tt.cuyows.tcloud.ar/operaciones-red-cloud/telegraf-sw-dell.git`
- **Proyecto ArgoCD:** `operaciones-red-cloud`

## Estructura del repo

```
.
├── argocd/
│   ├── application-set.yaml    # ApplicationSet (genera 1 App por site)
│   └── root-app.yaml           # (obsoleto, no usar)
├── templates/
│   ├── _helpers.tpl            # Helpers Helm (fullname, labels)
│   ├── configmap.yaml          # Config de Telegraf (SNMP input, Prometheus output)
│   ├── deployment.yaml         # Deployment + init container para MIBs
│   ├── pvc.yaml                # PVC para almacenar MIBs descargadas
│   └── service.yaml            # ClusterIP :9273
├── values.yaml                 # Valores por defecto
├── values-cuyo.yaml            # Overrides para site Cuyo (34 switches)
├── values-republica.yaml       # Overrides para site Republica (8 switches)
├── values-barracas.yaml        # Overrides para site Barracas (34 switches)
├── Chart.yaml                  # Metadata del chart
└── prometheus-scrape-config.yaml  # Config de scraping para Prometheus
```

## Configuracion

### values.yaml (defaults)

```yaml
global:
  image: docker.io/library/telegraf:1.29-alpine
  imagePullPolicy: IfNotPresent
  proxy:
    http: http://10.166.15.178:8080
    https: http://10.166.15.178:8080
    noProxy: "*.tcloud.telefonica.com.ar,..."

site:
  name: ""           # REQUIRED: identificador del site
  environment: production

snmp:
  community: "SupportAssistSNMP"
  version: 2
  interval: 60s
  deviceTagName: "device"
  agents: []         # REQUIRED: lista de IPs de switches

replicaCount: 1

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi

service:
  type: ClusterIP
  port: 9273

pvc:
  size: 100Mi
  storageClass: tcloud-unity-iscsi-nlsas
  existingClaim: ""

mibs:
  enabled: true
  repo: "https://github.com/Poil/MIBs.git"
  dirs:
    - dell-os10
    - dell
```

### Campos obligatorios por site

Para crear un nuevo archivo `values-<site>.yaml`, minimo hay que definir:

```yaml
site:
  name: <site>                  # identificador unico (cuyo, republica, barracas, ...)

snmp:
  agents:                       # lista de IPs de los switches del site
    - 172.28.9.4                # PSP-CYO1-001
    - 172.28.9.5                # PSP-CYO1-002
    # ...
```

### Campos opcionales

| Campo | Default | Descripcion |
|---|---|---|
| `replicaCount` | `1` | Numbero de replicas (0 para desactivar) |
| `snmp.community` | `SupportAssistSNMP` | Comunidad SNMP v2 |
| `snmp.version` | `2` | Version SNMP |
| `snmp.interval` | `60s` | Intervalo de recoleccion SNMP |
| `snmp.deviceTagName` | `device` | Nombre del tag para sysName en Prometheus |
| `resources.limits.memory` | `512Mi` | Limite de memoria (ver Sizing) |
| `pvc.existingClaim` | `""` | Reusar PVC existente |
| `mibs.enabled` | `true` | Habilitar descarga de MIBs via init container |

## Metricas recolectadas

| MIB | Tabla/OID | Metrica |
|---|---|---|
| RFC1213-MIB | `sysName.0` | Tag `device` (nombre del switch) |
| RFC1213-MIB | `sysUpTime.0` | `sw_sysUpTime` |
| IF-MIB | `ifTable` | `ifAdminStatus`, `ifOperStatus`, `ifSpeed`, `ifHCInOctets`, etc. |
| IF-MIB | `ifXTable` | `ifHCInUcastPkts`, `ifHCOutUcastPkts`, `ifHighSpeed`, etc. |
| IF-MIB | `ifStackTable` | `ifStackStatus` |
| IF-MIB | `ifRcvAddressTable` | `ifRcvAddressStatus` |
| HOST-RESOURCES-MIB | `hrProcessorTable` | `hrProcessorLoad` (CPU load por procesador) |
| DELLEMC-OS10-CHASSIS-MIB | `os10ChassisTable` | Info del chassis (descripcion, serie, service tag) |
| DELLEMC-OS10-CHASSIS-MIB | `os10CardTable` | Info de tarjetas (PPID, parte#, hw rev, temp) |
| DELLEMC-OS10-CHASSIS-MIB | `os10PowerSupplyTable` | Estado de fuentes de poder |
| DELLEMC-OS10-CHASSIS-MIB | `os10FanTrayTable` | Estado de bandejas de ventiladores |
| DELLEMC-OS10-CHASSIS-MIB | `os10FanTable` | Estado individual de ventiladores |

### Tags en Prometheus

Cada metrica incluye:
- `device` — sysName del switch (ej: `PSP-CYO1-001`)
- `agent_host` — IP del switch
- `site` — identificador del site (`cuyo`, `republica`, `barracas`)
- `host` — nombre del pod de telegraf
- `ifDescr`, `ifIndex`, `ifPhysAddress` — en metricas de interfaces

## Sizing de recursos

| Switches por site | Memoria recomendada | CPU recomendada |
|---|---|---|
| 1-10 | 256Mi | 200m |
| 10-35 | 512Mi | 500m |
| 35-60 | 1Gi | 500m |

**Regla empirica:** ~7Mi de memoria por switch, ~300 series de metricas por switch.

El `flush_interval` y `metric_batch_size` se ajustan para evitar warnings con el scrap interval de Prometheus:

```yaml
# Config actual (en configmap.yaml):
metric_batch_size = 5000    # acumula antes de serializar
flush_interval = "15s"      # tiempo para completar el expose de /metrics
```

## Deploy con ArgoCD

### ApplicationSet

El `argocd/application-set.yaml` genera automaticamente 1 Application por site:

```yaml
generators:
- list:
    elements:
    - site: cuyo
      valuesFile: values-cuyo.yaml
    - site: republica
      valuesFile: values-republica.yaml
    - site: barracas
      valuesFile: values-barracas.yaml
```

**Requisitos en ArgoCD:**
- Namespace: `whitecicd`
- Proyecto: `operaciones-red-cloud`
- Secret de repo: `repo-telegraf-sw-dell` con label `argocd.argoproj.io/secret-type: repository`
- Cluster destino: `https://api.wcr-operaciones.cuyows.tcloud.ar:6443`

### Secret del repo

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: repo-telegraf-sw-dell
  namespace: whitecicd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  name: telegraf-sw-dell
  url: https://whitecicd-tt.cuyows.tcloud.ar/operaciones-red-cloud/telegraf-sw-dell.git
  username: argocd-whitecicd-cuyo
  password: <PAT o password de GitLab>
  project: operaciones-red-cloud
```

### Aplicar el ApplicationSet

El ApplicationSet usa Go templates (`{{ site }}`, `{{ valuesFile }}`), por lo que no se puede aplicar directamente con `kubectl apply`. Opciones:

1. **Via ArgoCD UI/CLI** — crear el ApplicationSet desde el repo
2. **Renderizar y aplicar** — renderizar los templates manualmente

### Agregar un nuevo site

1. Crear `values-<site>.yaml` con la lista de switches
2. Agregar el site al listado en `argocd/application-set.yaml`:
   ```yaml
   - site: <nuevosite>
     valuesFile: values-<nuevosite>.yaml
   ```
3. Agregar el job de scraping en `prometheus-scrape-config.yaml`:
   ```yaml
   - job_name: 'telegraf-sw-<nuevosite>'
     scrape_interval: 30s
     metrics_path: /metrics
     static_configs:
     - targets: ['telegraf-<nuevosite>.telegraf-sw-dell.svc.cluster.local:9273']
   ```
4. Commit y push. ArgoCD sincronizara automaticamente.

## Configuracion de Prometheus

El `prometheus-scrape-config.yaml` contiene la configuracion para el ConfigMap `prometehus-config` en el namespace `grafana-operaciones`.

Los Services ClusterIP se resuelven cross-namespace via DNS interno:
```
telegraf-cuyo.telegraf-sw-dell.svc.cluster.local:9273
telegraf-republica.telegraf-sw-dell.svc.cluster.local:9273
telegraf-barracas.telegraf-sw-dell.svc.cluster.local:9273
```

Aplicar con:
```bash
# Editar el ConfigMap
kubectl edit configmap prometehus-config -n grafana-operaciones

# Reiniciar Prometheus
kubectl rollout restart deployment prometheus -n grafana-operaciones
```

### Scraping recomendado

| Parametro | Valor |
|---|---|
| `scrape_interval` | 30s (ideal), 60s (minimo) |
| `flush_interval` (telegraf) | 15s |
| `snmp.interval` (telegraf) | 60s |

Con scrape=30s, Prometheus siempre captura un snapshot completo de metricas entre ciclos de SNMP.

## Init container: descarga de MIBs

El init container `mibs-downloader` ejecuta al inicio de cada pod:

1. Instala `git` y `net-snmp-tools` (MIBs estandar IETF)
2. Copia las MIBs estandar a `/mibs/`
3. Clona sparse del repo `Poil/MIBs.git` (solo directorios `dell-os10` y `dell`)
4. Copia las Dell MIBs a `/mibs/` (sobre-escribe las estandar si hay conflicto)
5. El volumen PVC se monta en `/usr/share/snmp/mibs` en el contenedor de telegraf

## Mantenedor

- gapiolaz
