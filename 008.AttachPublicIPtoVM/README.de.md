# Öffentliche IP-Adresse an eine virtuelle Azure-Maschine anhängen: GUI, Azure CLI und Terraform

🌐 **Sprachen:** [Français](README.fr.md) · [English](README.en.md) · **Deutsch**

## Kontext

Ein Unternehmen verlagert einen Teil seiner Infrastruktur nach Azure. Die Migration wird in kleine, voneinander unabhängige Aufgaben aufgeteilt, um das Risiko gering zu halten und die Kontrolle zu behalten. Diese Aufgabe ist einer dieser Schritte: **eine bestehende öffentliche IP-Adresse an eine bestehende virtuelle Maschine (VM) anhängen**, damit die VM aus dem Internet erreichbar ist (Administration per SSH oder RDP oder ein öffentlicher Dienst).

In dieser README heißen die Ressourcen `my-vm` (die VM) und `my-public-ip` (die öffentliche IP). Diese Namen durch die eigenen ersetzen.

Die Aufgabe wird auf drei Arten gelöst:

1. **Azure-Portal (GUI)**
2. **Azure CLI**
3. **Terraform** (Modul, vom eigenen Rechner aus, **ohne** Azure CLI)

## Allgemeines Vorgehen: öffentliche IP an eine VM anhängen

Diese Schritte gelten für jede VM, unabhängig vom verwendeten Werkzeug.

| Schritt | Was zu tun ist | Warum |
|---|---|---|
| 1. Das Ziel verstehen | Eine öffentliche IP wird **nicht** an die VM selbst angehängt, sondern an die **IP-Konfiguration der Netzwerkschnittstelle (NIC) der VM**, meist `ipconfig1` genannt | Die NIC ist die Netzwerkbuchse der VM; die öffentliche IP ist die von außen sichtbare Adresse, die dort eingesteckt wird |
| 2. Voraussetzungen prüfen | Die öffentliche IP existiert, ist **frei** (mit nichts verknüpft), liegt in der **gleichen Region** wie die NIC und hat dieselbe IP-Version (IPv4) | Azure lehnt eine bereits genutzte IP oder eine IP in einer anderen Region ab |
| 3. NIC und ihre IP-Konfiguration finden | Die NICs der VM auflisten, dann die IP-Konfigurationen dieser NIC | Die IP wird einer bestimmten IP-Konfiguration zugeordnet |
| 4. IP zuordnen | Portal, CLI oder Terraform: die öffentliche IP mit der IP-Konfiguration verbinden | Das ist das eigentliche Anhängen |
| 5. Prüfen | Die VM zeigt eine öffentliche IP, und die öffentliche IP zeigt die IP-Konfiguration, der sie zugeordnet ist | Bestätigt, dass die VM die IP korrekt besitzt |
| 6. Ports bei Bedarf öffnen | Eine Regel der Network Security Group (NSG) für SSH (22) oder RDP (3389) hinzufügen | Eine öffentliche Standard-IP bleibt geschlossen, bis eine NSG Datenverkehr erlaubt |

Gut zu wissen:

- **Die VM muss nicht gestoppt werden.** Eine öffentliche IP lässt sich im laufenden Betrieb zuordnen. Das unterscheidet sich vom Hinzufügen einer NIC zu einer VM, wofür sie deallokiert werden muss.
- Eine IP-Konfiguration trägt **eine** öffentliche IP. Eine NIC kann mehrere IP-Konfigurationen haben.
- Eine **statische** IP behält ihre Adresse. Eine **dynamische** (Basic) IP erhält ihre Adresse erst nach der Zuweisung, sie kann also keine Adresse anzeigen, solange die VM deallokiert ist.

## Wichtige Konzepte

| Konzept | Beispiel | Gegenbeispiel |
|---|---|---|
| An die NIC zuordnen | `my-public-ip` wird mit `ipconfig1` der NIC der VM verbunden | Nach einer Schaltfläche „an VM anhängen“ suchen: Es gibt sie nicht, alles geschieht auf der NIC-Seite |
| Freie IP | `my-public-ip` ist mit nichts verknüpft | Eine IP, die bereits einer anderen NIC zugeordnet ist, wird abgelehnt |
| Gleiche Region | Öffentliche IP und NIC liegen in derselben Region | Verschiedene Regionen: Die Zuordnung wird abgelehnt |
| Zugeordnet ≠ erreichbar | Die VM besitzt die öffentliche Adresse | Die Ports bleiben geschlossen, bis eine NSG-Regel sie erlaubt |
| Statische Zuweisung | Die Adresse ändert sich nie, DNS-Einträge bleiben gültig | Eine dynamische Adresse kann sich ändern, und der DNS-Eintrag zeigt ins Leere |

Warum die öffentliche IP als eigene Ressource führen? Sie kann die VM überdauern: Wird die VM gelöscht und neu erstellt, bleiben die Adresse (und Firewall-Regeln, die auf sie verweisen) unverändert.

## Voraussetzungen

- Ein Azure-Abonnement und eine **bestehende Ressourcengruppe**, die die VM und die öffentliche IP enthält (Namen notieren).
- Für Terraform: Terraform >= 1.5 auf dem eigenen Rechner (beliebige Shell, z. B. Git Bash). Die Azure CLI wird **nicht** benötigt.
- Für Terraform: ein **Service Principal** (Client-ID + Client-Secret) mit der Rolle *Contributor* auf der Ressourcengruppe sowie Tenant-ID und Subscription-ID.

> In einer Shell sind `<` und `>` Umleitungsoperatoren. Platzhalter wie `<RG>` niemals unverändert einfügen: durch echte Werte ersetzen.

## Vorher prüfen: VM und öffentliche IP

```bash
RG="meine-ressourcengruppe"      # durch den Namen der eigenen Ressourcengruppe ersetzen

# Die VM muss bereitgestellt sein und darf noch keine öffentliche IP haben
az vm show -d -g "$RG" -n my-vm \
  --query "{provisioning:provisioningState, power:powerState, oeffentlicheIp:publicIps}" -o table

# NIC der VM und Name ihrer IP-Konfiguration
NIC=$(az vm nic list -g "$RG" --vm-name my-vm --query "[0].id" -o tsv | awk -F/ '{print $NF}')
echo "NIC = $NIC"
az network nic ip-config list -g "$RG" --nic-name "$NIC" --query "[].{name:name, primaer:primary}" -o table

# Die öffentliche IP muss frei sein: zugeordnetZu muss null sein
az network public-ip show -g "$RG" -n my-public-ip \
  --query "{ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod, region:location, zugeordnetZu:ipConfiguration.id}" -o json
```

Erwartet: `Succeeded`, `VM running`, leeres `oeffentlicheIp`, ein Name der IP-Konfiguration (wahrscheinlich `ipconfig1`) und `zugeordnetZu` auf `null`.

## Methode 1: Azure-Portal (GUI)

1. Unter <https://portal.azure.com> anmelden.
2. **Virtual machines** → die VM → **Networking** (oder **Network settings**): den Namen der NIC notieren.
3. **Public IP addresses** → `my-public-ip` → **Overview** → **Associate**.
4. **Resource type**: **Network interface**; **Resource**: die NIC der VM; **IP configuration**: `ipconfig1` → **OK**.
5. Prüfen: Auf der **Overview** der VM zeigt das Feld **Public IP address** die Adresse von `my-public-ip`.

Alternativer Weg: **Network interfaces** → die NIC → **IP configurations** → `ipconfig1` → **Public IP address**: **Associate** → `my-public-ip` wählen → **Save**.

## Methode 2: Azure CLI

```bash
RG="meine-ressourcengruppe"

NIC=$(az vm nic list -g "$RG" --vm-name my-vm --query "[0].id" -o tsv | awk -F/ '{print $NF}')
IPCONFIG=$(az network nic ip-config list -g "$RG" --nic-name "$NIC" --query "[0].name" -o tsv)

az network nic ip-config update \
  -g "$RG" \
  --nic-name "$NIC" \
  -n "$IPCONFIG" \
  --public-ip-address my-public-ip
```

Liegt die öffentliche IP in einer anderen Ressourcengruppe, an `--public-ip-address` ihre **vollständige ID** übergeben.

## Methode 3: Terraform

### Zwei Situationen

**Neue Bereitstellung (die NIC wird mit Terraform erstellt).** Das ist der Normalfall: Die öffentliche IP wird in der IP-Konfiguration der NIC referenziert.

```hcl
resource "azurerm_public_ip" "this" {
  name                = "my-public-ip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "this" {
  name                = "my-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id   # die Zuordnung
  }
}
```

**Bestehende VM und bestehende öffentliche IP (diese Aufgabe).** `azurerm` hat keine eigene Ressource zum „Zuordnen einer öffentlichen IP zu einer bestehenden NIC“: Die IP ist eine Eigenschaft der IP-Konfiguration der NIC. Die NIC mit `azurerm_network_interface` zu verwalten hieße, sie zu importieren und ihre Einstellungen zu übernehmen. Ein leichterer Ansatz nutzt den Provider `azapi`, der **nur** die Änderung der IP-Konfiguration an die Azure-API sendet. Der Rest dieses Abschnitts verwendet ihn. Die VM kann weiterlaufen.

Warum ein Modul? Ein Modul ist wiederverwendbar (nur seine Eingaben ändern sich). Das Gegenbeispiel: denselben Ressourcenblock in jedes Projekt kopieren.

### Projektstruktur

```
attach-public-ip/
├── providers.tf
├── variables.tf
├── main.tf                     # Wurzel: enthält module "nic_public_ip"
├── outputs.tf
├── terraform.tfvars            # enthält Geheimnisse: niemals einchecken
├── .gitignore
└── modules/
    └── nic_public_ip/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### `providers.tf`

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}

  # Nötig, wenn der Service Principal keine Rechte auf Abonnement-Ebene hat
  resource_provider_registrations = "none"

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}
```

### `variables.tf`

```hcl
variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "resource_group_name" {
  type = string
}

variable "vm_name" {
  type    = string
  default = "my-vm"
}

variable "public_ip_name" {
  type    = string
  default = "my-public-ip"
}
```

### `main.tf` (Wurzel)

```hcl
# Bestehende VM: gelesen, nicht verwaltet
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# Bestehende öffentliche IP, die zugeordnet wird
data "azurerm_public_ip" "pip" {
  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
}

# NICs der VM, über die Azure-API gelesen
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

locals {
  # Die erste NIC der VM ist die primäre
  nic_id = data.azapi_resource.vm.output.properties.networkProfile.networkInterfaces[0].id
}

# Aktuelle IP-Konfiguration dieser NIC
data "azapi_resource" "nic" {
  type                   = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id            = local.nic_id
  response_export_values = ["properties.ipConfigurations"]
}

module "nic_public_ip" {
  source = "./modules/nic_public_ip"

  nic_id           = local.nic_id
  ip_configuration = data.azapi_resource.nic.output.properties.ipConfigurations[0]
  public_ip_id     = data.azurerm_public_ip.pip.id
}
```

### `outputs.tf`

```hcl
output "public_ip_address" {
  value = data.azurerm_public_ip.pip.ip_address
}

output "nic_id" {
  value = local.nic_id
}
```

### `modules/nic_public_ip/variables.tf`

```hcl
variable "nic_id" {
  type        = string
  description = "ID der bestehenden NIC"
}

variable "ip_configuration" {
  type        = any
  description = "Aktuelle IP-Konfiguration der NIC (über die Azure-API gelesen)"
}

variable "public_ip_id" {
  type        = string
  description = "ID der zuzuordnenden öffentlichen IP"
}
```

### `modules/nic_public_ip/main.tf`

```hcl
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

locals {
  ipc   = var.ip_configuration
  props = local.ipc.properties

  # privateIPAddress wird nur übernommen, wenn die Zuweisung Static ist
  static_private_ip = {
    for k, v in { privateIPAddress = try(local.props.privateIPAddress, "") } :
    k => v if local.props.privateIPAllocationMethod == "Static"
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id = var.nic_id

  body = {
    properties = {
      ipConfigurations = [
        {
          name = local.ipc.name
          properties = merge(
            {
              subnet                    = { id = local.props.subnet.id }
              privateIPAllocationMethod = local.props.privateIPAllocationMethod
              primary                   = try(local.props.primary, true)
              publicIPAddress           = { id = var.public_ip_id }
            },
            local.static_private_ip
          )
        }
      ]
    }
  }
}
```

### `modules/nic_public_ip/outputs.tf`

```hcl
output "nic_id" {
  value = azapi_update_resource.this.resource_id
}
```

### `terraform.tfvars` (eigene Werte, ohne spitze Klammern)

```hcl
resource_group_name = "meine-ressourcengruppe"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
client_secret   = "dein-client-secret"
```

### `.gitignore`

```gitignore
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

### Wo man die vier Zugangsdaten findet

| Variable | Wo |
|---|---|
| `subscription_id` | Portal → Subscriptions → Abonnement → Overview |
| `tenant_id` | Portal → Microsoft Entra ID → Overview |
| `client_id` | Entra ID → App registrations → eigene App → *Application (client) ID* |
| `client_secret` | Dieselbe App → Certificates & secrets → New client secret → Spalte **Value** kopieren (wird nur einmal angezeigt) |

Anschließend der App die Rolle **Contributor** auf der Ressourcengruppe zuweisen (Resource group → Access control (IAM) → Add role assignment). Stellt die Umgebung fertige Zugangsdaten bereit, diese stattdessen verwenden; sie können sich mit jeder Sitzung ändern.

### Ausführung (die VM darf weiterlaufen)

```bash
terraform init
terraform validate
terraform plan      # erwartet: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

Hinweise:

- Die `main.tf` mit `module "nic_public_ip"` ist die im **Wurzelverzeichnis** des Ordners, nicht die innerhalb von `modules/`.
- Das Modul ändert die **erste** IP-Konfiguration der **ersten** NIC der VM, was der Standardfall ist. Bei einer NIC mit mehreren IP-Konfigurationen die richtige gezielt auswählen.

## Abschließende Prüfung (alle Methoden)

```bash
# Die VM zeigt die öffentliche IP
az vm show -d -g "$RG" -n my-vm \
  --query "{oeffentlicheIp:publicIps, provisioning:provisioningState, power:powerState}" -o table

# zugeordnetZu muss auf .../networkInterfaces/<NIC>/ipConfigurations/<ipconfig> enden
az network public-ip show -g "$RG" -n my-public-ip \
  --query "{ip:ipAddress, zugeordnetZu:ipConfiguration.id}" -o json

# NIC-Seite
az network nic ip-config show -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" \
  --query "publicIPAddress.id" -o tsv
```

Erwartet: `oeffentlicheIp` gefüllt (gleiche Adresse wie `ip`), `zugeordnetZu` nicht leer und eine ID, die auf `my-public-ip` endet.

## Zurücksetzen (um eine andere Methode zu testen)

```bash
az network nic ip-config update -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" --remove publicIpAddress
```

(Oder Portal: **Public IP addresses → my-public-ip → Dissociate**.) Auch den lokalen State des vorigen Versuchs löschen (`rm -f terraform.tfstate*`), sonst hält Terraform die Zuordnung für erledigt. `terraform destroy` hebt die Zuordnung der IP **nicht** auf: Diese Ressource sendet nur eine Änderung und kann sie nicht rückgängig machen.

## Fehlerbehebung

| Fehler | Ursache | Lösung |
|---|---|---|
| Öffentliche IP bereits in Benutzung | `my-public-ip` ist einer anderen NIC zugeordnet | `zugeordnetZu` prüfen, zuerst die Zuordnung aufheben |
| Regionsfehler | Öffentliche IP und NIC liegen in verschiedenen Regionen | Sie müssen dieselbe Region teilen |
| `oeffentlicheIp` leer, obwohl zugeordnet | Dynamische IP auf einer deallokierten VM | VM starten oder eine statische IP verwenden |
| SSH oder RDP trotz öffentlicher IP abgelehnt | Keine NSG-Regel erlaubt den Port | NSG-Regel für den Port hinzufügen |
| `403 AuthorizationFailed ... register/action` bei vielen Providern | `azurerm` 4.x versucht, ca. 30 Resource Provider im gesamten Abonnement zu registrieren | `resource_provider_registrations = "none"` im Provider-Block ergänzen |
| Derselbe Fehler oder ein Authentifizierungsfehler bei leerer `providers.tf` | Ohne Provider-Block werden die Zugangsdaten ignoriert | `providers.tf` ausfüllen |
| Terraform fragt Variablen ab, die bereits in der tfvars-Datei stehen | Die Datei wird nicht automatisch geladen (falscher Name wie `terraform.tfvars.txt`, falscher Ordner) | Exakt `terraform.tfvars` neben `main.tf` nennen oder `-var-file="datei.tfvars"` übergeben |
| `Invalid client secret` | Secret leer, abgeschnitten, oder statt *Value* die *Secret ID* kopiert | Neues Secret erstellen und die Spalte **Value** kopieren |
| `Module not installed` | `terraform init` wurde nicht ausgeführt | `terraform init` ausführen |
| `No declaration found for var.xxx` oder rote Unterstreichungen in VS Code | Eine `variables.tf` im Wurzelverzeichnis fehlt, oder der Editor hat nicht neu geladen | Dateien mit `find` prüfen, `terraform init` und `terraform validate` ausführen; wenn gültig, **Developer: Reload Window** |
| Fehler bei `.output.properties...` | Die `azapi`-Ausgabe hat eine andere Form | Die NIC mit `az network nic show -o json` ausgeben und den Pfad anpassen |
| Typfehler bei `merge` oder `ip_configuration` | Ungewöhnliche NIC (mehrere IP-Konfigurationen, IPv6) | Die richtige IP-Konfiguration gezielt auswählen |
| `ResourceNotFound` bei einer `data`-Quelle | Falscher Name der Ressourcengruppe, oder die VM wird noch erstellt | Namen prüfen und auf `provisioningState = Succeeded` warten |
| Alter State oder alte Zugangsdaten nach einer neuen Sitzung | State-Datei und Zugangsdaten gehören zu einer früheren Umgebung | Neuen Ordner und die Zugangsdaten der aktuellen Sitzung verwenden |

## Aufräumen

```bash
# CLI
az network nic ip-config update -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" --remove publicIpAddress
```

`terraform destroy` hebt die Zuordnung der IP nicht auf (siehe oben).

## Sicherheitshinweise

- `terraform.tfvars` und State-Dateien niemals einchecken: Sie enthalten ein Secret und Ressourcendetails.
- Kurzlebige Secrets und die am wenigsten privilegierte Rolle bevorzugen (Contributor auf einer Ressourcengruppe, nicht auf dem Abonnement).
- Eine öffentliche IP setzt die VM dem Internet aus: Nur die nötigen Ports in der NSG öffnen und SSH mit Schlüsseln bevorzugen.
- Die drei Methoden nacheinander ausführen und die Änderung dazwischen rückgängig machen: Eine IP-Konfiguration trägt nur eine öffentliche IP.
