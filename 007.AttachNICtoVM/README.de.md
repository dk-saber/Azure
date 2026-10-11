# Netzwerkschnittstelle (NIC) an eine virtuelle Azure-Maschine anhängen: GUI, Azure CLI und Terraform

🌐 **Sprachen:** [Français](README.fr.md) · [English](README.en.md) · **Deutsch**

## Kontext

Ein Unternehmen verlagert einen Teil seiner Infrastruktur nach Azure. Um das Risiko gering zu halten und die Kontrolle zu behalten, wird die Migration nicht in einem großen Schritt durchgeführt, sondern in kleine, voneinander unabhängige Aufgaben aufgeteilt. Diese Aufgabe ist einer dieser Schritte: **eine bestehende Netzwerkschnittstelle (NIC) an eine bestehende virtuelle Maschine (VM) anhängen**.

**Ziel:** die NIC `datacenter-nic` an die VM `datacenter-vm` anhängen, prüfen, dass die NIC als angehängt angezeigt wird, und sicherstellen, dass die Initialisierung der VM abgeschlossen ist.

Die Aufgabe wird auf drei Arten gelöst:

1. **Azure-Portal (GUI)**
2. **Azure CLI**
3. **Terraform** (Modul, vom eigenen Rechner aus, **ohne** Azure CLI)

## ⚠️ Zwingender erster Schritt: die VM stoppen **und deallozieren**

Azure kann einer laufenden VM keine NIC hinzufügen. Die VM muss vor dem Anhängen **deallokiert** und danach wieder gestartet werden.

| | Beispiel | Gegenbeispiel |
|---|---|---|
| Deallokiert | Schaltfläche **Stop** im Portal oder `az vm deallocate`: Status `Stopped (deallocated)`, Rechenressourcen freigegeben | Herunterfahren innerhalb des Betriebssystems oder `az vm stop`: die VM ist gestoppt, aber **weiterhin zugewiesen**, das Anhängen schlägt trotzdem fehl |
| Laufende VM | Ein Datenträger lässt sich im Betrieb anhängen | Das Anhängen einer NIC wird abgelehnt |

Reihenfolge: **deallozieren → anhängen → starten → prüfen**.

## Wichtige Konzepte

| Konzept | Beispiel | Gegenbeispiel |
|---|---|---|
| Bestehende NIC anhängen | `datacenter-nic` existiert bereits: sie wird nur mit `datacenter-vm` verbunden | Eine neue NIC zu erstellen hinterlässt eine überzählige Schnittstelle |
| Primäre vs. sekundäre NIC | Die ursprüngliche NIC bleibt primär; `datacenter-nic` kommt als sekundäre hinzu | Die primäre NIC zu „ersetzen“ ist nicht verlangt |
| Gleiche Region und gleiches VNet | Beide liegen in derselben Region und demselben virtuellen Netzwerk | Eine NIC aus einem anderen VNet oder einer anderen Region wird abgelehnt |
| Angehängt ≠ im Betriebssystem konfiguriert | Azure zeigt die NIC als angehängt an | Die Schnittstelle muss im Betriebssystem noch konfiguriert werden (außerhalb des Umfangs) |

Warum das Ganze? Eine VM mit zwei NICs trennt Datenströme: zum Beispiel eine NIC für Nutzerverkehr und eine für Administration oder Backups, jeweils mit eigenen Network-Security-Group-Regeln. Das ist auch bei virtuellen Firewalls und Proxys üblich.

## Voraussetzungen

- Ein Azure-Abonnement und eine **bestehende Ressourcengruppe**, die die VM und die NIC enthält (Namen notieren).
- Die VM-Größe muss zwei NICs erlauben.
- Für Terraform: Terraform >= 1.5 auf dem eigenen Rechner (beliebige Shell, z. B. Git Bash). Die Azure CLI wird **nicht** benötigt.
- Für Terraform: ein **Service Principal** (Client-ID + Client-Secret) mit der Rolle *Contributor* auf der Ressourcengruppe sowie Tenant-ID und Subscription-ID.

> In einer Shell sind `<` und `>` Umleitungsoperatoren. Platzhalter wie `<RG>` niemals unverändert einfügen: durch echte Werte ersetzen.

## Vorher prüfen: VM und NIC

```bash
RG="meine-ressourcengruppe"      # durch den Namen der eigenen Ressourcengruppe ersetzen

# Die VM muss bereitgestellt sein und laufen
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState, groesse:hardwareProfile.vmSize}" -o table

# Bereits an der VM hängende NICs (die erste ist die primäre)
az vm nic list -g "$RG" --vm-name datacenter-vm -o table

# Die NIC muss frei sein: vm muss null sein
az network nic show -g "$RG" -n datacenter-nic \
  --query "{vm:virtualMachine.id, region:location}" -o json
```

Danach die VM deallozieren:

```bash
az vm deallocate -g "$RG" -n datacenter-vm
```

(Portal: **Virtual machines → datacenter-vm → Stop**, dann auf **Stopped (deallocated)** warten.)

## Methode 1: Azure-Portal (GUI)

1. Unter <https://portal.azure.com> anmelden.
2. Die VM stoppen und auf **Stopped (deallocated)** warten.
3. **Networking** (oder **Network settings**) → **Attach network interface**. Die Schaltfläche ist ausgegraut, solange die VM läuft.
4. `datacenter-nic` auswählen → **OK**.
5. **Overview** → **Start** und auf **Running** warten.
6. Prüfen: `datacenter-nic` erscheint unter **Networking**, und bei der NIC zeigt das Feld **Virtual machine** `datacenter-vm`.

## Methode 2: Azure CLI

```bash
az vm deallocate -g "$RG" -n datacenter-vm
az vm nic add -g "$RG" --vm-name datacenter-vm --nics datacenter-nic
az vm start -g "$RG" -n datacenter-vm
```

Liegt die NIC in einer anderen Ressourcengruppe, an `--nics` ihre **vollständige ID** übergeben.

## Methode 3: Terraform

### Warum ein besonderer Ansatz nötig ist

Der Provider `azurerm` hat keine eigene Ressource zum „Anhängen einer NIC an eine VM“: Die NIC-Liste ist eine Eigenschaft der VM selbst. Die VM mit `azurerm_linux_virtual_machine` zu verwalten hieße, sie zu importieren und alle ihre Einstellungen zu übernehmen (Größe, Image, SSH-Schlüssel …), mit dem Risiko, dass sie ersetzt wird. Ein leichterer Ansatz nutzt den Provider `azapi`, der **nur** die Änderung an `networkProfile` an die Azure-API sendet.

Zwei Details, die man auf die harte Tour lernt:

- Die Datenquelle `azurerm_virtual_machine` exportiert `network_interface_ids` **nicht**. Die aktuellen NICs werden stattdessen mit einer `azapi_resource`-Datenquelle gelesen.
- `azapi` **deallokiert** die VM **nicht** für dich: vor `terraform apply` selbst erledigen.

Warum ein Modul? Ein Modul ist wiederverwendbar (nur seine Eingaben ändern sich). Das Gegenbeispiel: denselben Ressourcenblock in jedes Projekt kopieren.

### Projektstruktur

```
attach-nic/
├── providers.tf
├── variables.tf
├── main.tf                     # Wurzel: enthält module "nic_attachment"
├── outputs.tf
├── terraform.tfvars            # enthält Geheimnisse: niemals einchecken
├── .gitignore
└── modules/
    └── vm_nic_attachment/
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
  default = "datacenter-vm"
}

variable "nic_name" {
  type    = string
  default = "datacenter-nic"
}
```

### `main.tf` (Wurzel)

```hcl
# Bestehende VM: gelesen, nicht verwaltet
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# Aktuell an der VM hängende NICs, über die Azure-API gelesen
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

# Bestehende NIC zum Anhängen
data "azurerm_network_interface" "new" {
  name                = var.nic_name
  resource_group_name = var.resource_group_name
}

locals {
  # Die erste NIC der Liste ist die primäre
  primary_nic_id = data.azapi_resource.vm.output.properties.networkProfile.networkInterfaces[0].id
}

module "nic_attachment" {
  source = "./modules/vm_nic_attachment"

  vm_id              = data.azurerm_virtual_machine.vm.id
  primary_nic_id     = local.primary_nic_id
  additional_nic_ids = [data.azurerm_network_interface.new.id]
}
```

### `outputs.tf`

```hcl
output "attached_nic_ids" {
  value = module.nic_attachment.nic_ids
}
```

### `modules/vm_nic_attachment/variables.tf`

```hcl
variable "vm_id" {
  type        = string
  description = "ID der bestehenden VM"
}

variable "primary_nic_id" {
  type        = string
  description = "Bereits angehängte primäre NIC"
}

variable "additional_nic_ids" {
  type        = list(string)
  description = "Zusätzlich anzuhängende NICs"
}
```

### `modules/vm_nic_attachment/main.tf`

```hcl
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id = var.vm_id

  body = {
    properties = {
      networkProfile = {
        networkInterfaces = concat(
          [{ id = var.primary_nic_id, properties = { primary = true } }],
          [for id in var.additional_nic_ids : { id = id, properties = { primary = false } }]
        )
      }
    }
  }
}
```

### `modules/vm_nic_attachment/outputs.tf`

```hcl
output "nic_ids" {
  value = concat([var.primary_nic_id], var.additional_nic_ids)
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

### Ausführung, mit **bereits deallokierter** VM

```bash
terraform init
terraform validate
terraform plan      # erwartet: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply

# danach die VM wieder starten
az vm start -g "$RG" -n datacenter-vm      # oder Portal: Overview → Start
```

Hinweis: Die `main.tf` mit `module "nic_attachment"` ist die im **Wurzelverzeichnis** des Ordners, nicht die innerhalb von `modules/`.

## Abschließende Prüfung (alle Methoden)

```bash
# Zwei NICs aufgelistet
az vm nic list -g "$RG" --vm-name datacenter-vm -o table

# Die ID muss auf datacenter-vm enden
az network nic show -g "$RG" -n datacenter-nic --query "virtualMachine.id" -o tsv

# Initialisierung abgeschlossen: Succeeded und VM running
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState}" -o table
```

Die Aufgabe erst abgeben, wenn `Succeeded` und `VM running` angezeigt werden.

## Zurücksetzen (um eine andere Methode zu testen)

```bash
az vm deallocate -g "$RG" -n datacenter-vm
az vm nic remove -g "$RG" --vm-name datacenter-vm --nics datacenter-nic
```

Auch den lokalen State des vorigen Versuchs löschen (`rm -f terraform.tfstate*`), sonst hält Terraform das Anhängen für erledigt. `terraform destroy` hängt die NIC **nicht** ab: Diese Ressource sendet nur eine Änderung und kann sie nicht rückgängig machen.

## Fehlerbehebung

| Fehler | Ursache | Lösung |
|---|---|---|
| NIC-Anhängen abgelehnt, Schaltfläche ausgegraut | Die VM läuft oder ist nur gestoppt, aber weiterhin zugewiesen | VM **deallozieren** (Status `Stopped (deallocated)`) |
| NIC bereits in Benutzung | Die NIC ist an eine andere VM angehängt | `virtualMachine.id` prüfen, zuerst abhängen |
| Regions- oder VNet-Fehler | NIC und VM liegen in verschiedenen Regionen oder virtuellen Netzwerken | Sie müssen Region und VNet teilen |
| Fehler zur NIC-Anzahl | Die VM-Größe erlaubt keine zwei NICs | Größere VM-Größe wählen |
| `403 AuthorizationFailed ... register/action` bei vielen Providern | `azurerm` 4.x versucht, ca. 30 Resource Provider im gesamten Abonnement zu registrieren | `resource_provider_registrations = "none"` im Provider-Block ergänzen |
| Derselbe Fehler oder ein Authentifizierungsfehler bei leerer `providers.tf` | Ohne Provider-Block werden die Zugangsdaten ignoriert | `providers.tf` ausfüllen |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | Der Wert der Ressourcengruppe enthält noch Platzhalterzeichen wie `<` `>` | Den echten Namen der Ressourcengruppe verwenden |
| Terraform fragt Variablen ab, die bereits in der tfvars-Datei stehen | Die Datei wird nicht automatisch geladen (falscher Name wie `terraform.tfvars.txt`, falscher Ordner) | Exakt `terraform.tfvars` neben `main.tf` nennen oder `-var-file="datei.tfvars"` übergeben |
| `Invalid client secret` | Secret leer, abgeschnitten, oder statt *Value* die *Secret ID* kopiert | Neues Secret erstellen und die Spalte **Value** kopieren |
| `Module not installed` | `terraform init` wurde nicht ausgeführt | `terraform init` ausführen |
| `No declaration found for var.xxx` oder rote Unterstreichungen in VS Code | Eine `variables.tf` im Wurzelverzeichnis fehlt, oder der Editor hat nicht neu geladen | Dateien mit `find` prüfen, `terraform init` und `terraform validate` ausführen; wenn gültig, **Developer: Reload Window** |
| `Unsupported attribute ... network_interface_ids` | Die Datenquelle `azurerm_virtual_machine` exportiert es nicht | NICs mit der `azapi_resource`-Datenquelle lesen |
| `ResourceNotFound` bei einer `data`-Quelle | Falscher Name der Ressourcengruppe, oder die VM wird noch erstellt | Namen prüfen und auf `provisioningState = Succeeded` warten |
| Alter State oder alte Zugangsdaten nach einer neuen Sitzung | State-Datei und Zugangsdaten gehören zu einer früheren Umgebung | Neuen Ordner und die Zugangsdaten der aktuellen Sitzung verwenden |

## Aufräumen

```bash
# CLI (VM zuerst deallozieren)
az vm nic remove --resource-group "$RG" --vm-name datacenter-vm --nics datacenter-nic
```

`terraform destroy` hängt eine NIC nicht ab (siehe oben).

## Sicherheitshinweise

- `terraform.tfvars` und State-Dateien niemals einchecken: Sie enthalten ein Secret und Ressourcendetails.
- Kurzlebige Secrets und die am wenigsten privilegierte Rolle bevorzugen (Contributor auf einer Ressourcengruppe, nicht auf dem Abonnement).
- Die drei Methoden nacheinander ausführen und die Änderung dazwischen rückgängig machen: Eine NIC kann nicht zweimal angehängt werden.
- In einem echten Projekt die VM mit Terraform erstellen und beide NICs von Anfang an in `network_interface_ids` auflisten: kein Import und keine Deallokation nötig.
