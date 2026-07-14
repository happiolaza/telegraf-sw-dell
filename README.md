# telegraf-sw-dell

Helm chart para monitoreo SNMP de switches via Telegraf, desplegado con ArgoCD. Soporte multi-vendor (Dell OS10, Cisco IOS, etc.).

Recolecta metricas SNMP de switches y las expone en formato Prometheus para scraping.

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
Switches Dell/Cisco/etc. (varia por site)
```

- **Cluster origen:** TTOOLS-CUY (donde corre ArgoCD, ns `whitecicd`)
- **Cluster destino:** wcr-operaciones (donde corren los pods, ns `telegraf-sw-dell`)
- **GitLab repo:** `https://whitecicd-tt.cuyows.tcloud.ar/operaciones-red-cloud/telegraf-sw-dell.git`
- **Proyecto ArgoCD:** `operaciones-red-cloud`

## Estructura del repo

```
.
├── argocd/
│   ├── application-set.yaml    # ApplicationSet (genera 1 App por site)
│   └── root-app.yaml           # (obsoleto, no usar)
├── vendors/                    # Templates de referencia por vendor
│   ├── dell-os10.yaml          # SNMP tables para Dell OS10
│   └── cisco-ios.yaml          # SNMP tables para Cisco IOS
├── templates/
│   ├── _helpers.tpl            # Helpers Helm (fullname, labels, ports)
│   ├── configmap.yaml          # Config dinamica de Telegraf (desde values)
│   ├── deployment.yaml         # Deployment + init container para MIBs
│   ├── pvc.yaml                # PVC para almacenar MIBs descargadas
│   └── service.yaml            # ClusterIP :9273
├── values.yaml                 # Defaults globales (multi-vendor)
├── values-cuyo.yaml            # Overrides para site Cuyo (34 switches Dell)
├── values-republica.yaml       # Overrides para site Republica (8 switches Dell)
├── values-barracas.yaml        # Overrides para site Barracas (34 switches Dell)
├── Chart.yaml                  # Metadata del chart
└── prometheus-scrape-config.yaml  # Config de scraping para Prometheus
```

## Agregar un site nuevo

1. Copiar el template del vendor:
   ```bash
   cp vendors/dell-os10.yaml values-<site>.yaml
   ```

2. Editar `values-<site>.yaml`:
   - Definir `site.name` (identificador unico)
   - Agregar la lista de IPs en `snmp.agents`
   - Ajustar `snmp.tables` si necesita MIBs diferentes
   - Ajustar `mibs.dirs` si necesita MIBs adicionales

3. Agregar el site al ApplicationSet en `argocd/application-set.yaml`:
   ```yaml
   - site: <nuevosite>
     valuesFile: values-<nuevosite>.yaml
   ```

4. Agregar el job de scraping en `prometheus-scrape-config.yaml`:
   ```yaml
   - job_name: 'telegraf-sw-<nuevosite>'
     scrape_interval: 30s
     scrape_timeout: 30s
     metrics_path: /metrics
     static_configs:
     - targets: ['telegraf-<nuevosite>.telegraf-sw-dell.svc.cluster.local:9273']
     relabel_configs:
     - target_label: site
       replacement: <nuevosite>
   ```

5. Commit y push. ArgoCD sincronizara automaticamente.

## Configuracion multi-vendor

### Estructura de values por site

```yaml
site:
  name: rosario          # identificador unico
  vendor: cisco-ios      # informativo

snmp:
  community: "comunidad"  # override por site
  interval: "30s"         # override por site
  agents:
    - 10.20.30.1
  tables:                 # listado completo de tablas SNMP
    - oid: "SNMPv2-MIB::sysName.0"
      name: "device"
      is_tag: true
      field: true
    - oid: "IF-MIB::ifTable"
```

### Templates de vendor

Los archivos en `vendors/` son **templates de referencia**, no son consumidos por Helm. Sirven como base para crear nuevos sites:

| Vendor | Archivo | MIBs necesarias |
|---|---|---|
| Dell OS10 | `vendors/dell-os10.yaml` | Dell + IETF (descargadas via init container) |
| Cisco IOS | `vendors/cisco-ios.yaml` | IETF estandar (incluidas en el switch) |

### merging de values

Helm mergea automaticamente defaults + overrides del site:
- **Escalares y maps**: el site overridea lo que define, lo demas se preserva del default
- **Listas** (como `snmp.tables`): el site DEBE definir la lista completa, no se concatenan con el default

## Parametros configurables por site

| Parametro | Default | Descripcion |
|---|---|---|
| `site.name` | `""` (REQUIRED) | Identificador unico del site |
| `site.vendor` | `""` | Vendor informativo |
| `snmp.community` | `SupportAssistSNMP` | Comunidad SNMP v2 |
| `snmp.version` | `2` | Version SNMP |
| `snmp.interval` | `60s` | Intervalo de recoleccion |
| `snmp.tables` | `[]` (REQUIRED) | Tablas/fields SNMP a recolectar |
| `telegraf.agent.metricBatchSize` | `5000` | Batch size para metricas |
| `telegraf.agent.flushInterval` | `15s` | Intervalo de flush |
| `telegraf.output.prometheusPort` | `9273` | Puerto del endpoint /metrics |
| `mibs.enabled` | `true` | Habilitar init container de MIBs |
| `mibs.dirs` | `[]` | Directorios a clonar del repo de MIBs |
| `replicaCount` | `1` | Numero de replicas |
| `resources.limits.memory` | `512Mi` | Limite de memoria |

## Metricas por vendor

### Dell OS10

| MIB | Tabla | Metrica |
|---|---|---|
| RFC1213-MIB | `sysName.0` | Tag `device` |
| RFC1213-MIB | `sysUpTime.0` | `sw_sysUpTime` |
| IF-MIB | `ifTable`, `ifXTable`, `ifStackTable`, `ifRcvAddressTable` | Interfaces |
| HOST-RESOURCES-MIB | `hrProcessorTable` | CPU load |
| DELLEMC-OS10-CHASSIS-MIB | `os10ChassisTable`, `os10CardTable`, `os10PowerSupplyTable`, `os10FanTrayTable`, `os10FanTable` | Chassis, tarjetas, PSU, fans |

### Cisco IOS

| MIB | Tabla | Metrica |
|---|---|---|
| SNMPv2-MIB | `sysName.0` | Tag `device` |
| SNMPv2-MIB | `sysUpTime.0` | `sw_sysUpTime` |
| IF-MIB | `ifTable`, `ifXTable` | Interfaces |
| CISCO-PROCESS-MIB | `cpmCPUTotalTable` | CPU load |
| CISCO-ENTITY-SENSOR-MIB | `entSensorValueTable` | Sensores ambientales |

## Deploy con ArgoCD

### ApplicationSet

El `argocd/application-set.yaml` genera automaticamente 1 Application por site.

**Requisitos en ArgoCD:**
- Namespace: `whitecicd`
- Proyecto: `operaciones-red-cloud`
- Secret de repo: `repo-telegraf-sw-dell` con label `argocd.argoproj.io/secret-type: repository`
- Cluster destino: `https://api.wcr-operaciones.cuyows.tcloud.ar:6443`

### Configuracion de Prometheus

El `prometheus-scrape-config.yaml` contiene la configuracion para agregar al ConfigMap `prometehus-config` en namespace `grafana-operaciones`.

Los Services ClusterIP se resuelven cross-namespace via DNS interno:
```
telegraf-<site>.telegraf-sw-dell.svc.cluster.local:9273
```

Aplicar con:
```bash
kubectl edit configmap prometehus-config -n grafana-operaciones
kubectl rollout restart deployment prometheus -n grafana-operaciones
```

## Sizing de recursos

| Switches por site | Memoria recomendada | CPU recomendada |
|---|---|---|
| 1-10 | 256Mi | 200m |
| 10-35 | 512Mi | 500m |
| 35-60 | 1Gi | 500m |

**Regla empirica:** ~7Mi de memoria por switch, ~300 series de metricas por switch.

## Mantenedor

- gapiolaz
