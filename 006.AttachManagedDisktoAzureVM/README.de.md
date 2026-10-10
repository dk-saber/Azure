# Azure-Migrationsaufgaben: GUI, Azure CLI und Terraform

🌐 **Sprachen:** [Français](README.fr.md) · [English](README.en.md) · **Deutsch**

## Kontext

Ein Unternehmen verlagert einen Teil seiner Infrastruktur nach Azure. Um das Risiko gering zu halten und die Kontrolle zu behalten, wird die Migration nicht in einem großen Schritt durchgeführt, sondern in kleine, voneinander unabhängige Aufgaben aufgeteilt. Jede Aufgabe unten wird auf drei Arten gelöst:

1. **Azure-Portal (GUI)**
2. **Azure CLI**
3. **Terraform** (Module, vom eigenen Rechner aus, **ohne** Azure CLI)

| # | Aufgabe | Ressourcen |
|---|---|---|
| 1 | [Öffentliche IP-Adresse erstellen](#aufgabe-1-öffentliche-ip-adresse-erstellen) | `datacenter-pip` |
| 2 | [Verwaltete Festplatte an eine virtuelle Maschine anhängen](#aufgabe-2-verwaltete-festplatte-an-eine-virtuelle-maschine-anhängen) | `datacenter-vm`, `datacenter-disk` |

## Voraussetzungen

- Ein Azure-Abonnement und eine **bestehende Ressourcengruppe** (Name und Region notieren).
- Für Terraform: Terraform >= 1.5 auf dem eigenen Rechner. Die Azure CLI wird **nicht** benötigt.
- Für Terraform: ein **Service Principal** (Client-ID + Client-Secret) mit der Rolle *Contributor* auf der Ressourcengruppe sowie Tenant-ID und Subscription-ID.

> In einer Shell sind `<` und `>` Umleitungsoperatoren. Platzhalter wie `<RG>` niemals unverändert einfügen: durch echte Werte ersetzen.

## Gemeinsames Terraform-Setup

Jede Aufgabe bekommt einen eigenen Ordner, damit jede ihre eigene State-Datei hat:

```
azure-migration/
├── task-01-public-ip/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars        # enthält Geheimnisse: niemals einchecken
│   └── modules/public_ip/
├── task-02-attach-disk/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   └── modules/disk_attachment/
└── .gitignore
```

Warum Module? Ein Modul ist wiederverwendbar (nur seine Eingaben ändern sich). Das Gegenbeispiel: denselben Ressourcenblock in jedes Projekt kopieren und jede Kopie von Hand anpassen.

### `providers.tf` (in jedem Aufgabenordner identisch)

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
```

### Authentifizierungsvariablen (in jede `variables.tf` aufnehmen)

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

### Ausführung (in jedem Aufgabenordner)

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Aufgabe 1: Öffentliche IP-Adresse erstellen

**Ziel:** eine öffentliche IP-Adresse mit dem Namen `datacenter-pip` in einer bestehenden Ressourcengruppe erstellen.

### Wichtige Konzepte

| Konzept | Beispiel | Gegenbeispiel |
|---|---|---|
| Öffentliche vs. private IP | `20.50.10.4` ist aus dem Internet erreichbar (z. B. per SSH) | `10.0.0.4` ist nur innerhalb des Azure-Netzwerks erreichbar |
| Statische Zuweisung | Die Adresse ändert sich nie, auch wenn die VM gestoppt wird; DNS-Einträge bleiben gültig | Eine dynamische Adresse kann sich nach einem Stopp/Start ändern, und der DNS-Eintrag zeigt ins Leere |
| SKU Standard | Standardmäßig sicher (geschlossen, bis eine Network Security Group Datenverkehr erlaubt) | Die SKU Basic wird von Azure abgekündigt (seit dem 30. September 2025): nicht mehr verwenden |

Warum die IP getrennt von der VM anlegen? Sie kann die VM überdauern: Wird die VM gelöscht und neu erstellt, bleiben die Adresse (und Firewall-Regeln, die auf sie verweisen) unverändert.

### Methode 1: Azure-Portal (GUI)

1. Unter <https://portal.azure.com> anmelden.
2. Nach **Public IP addresses** suchen, den Dienst öffnen, auf **Create** klicken.
3. Ausfüllen:
   - **Subscription** und **Resource group**: die bereits vorhandenen
   - **Region**: dieselbe wie die Ressourcengruppe
   - **Name**: `datacenter-pip`
   - **IP Version**: IPv4
   - **SKU**: Standard
   - **Assignment**: Static
4. Auf **Review + create** und danach auf **Create** klicken.
5. Prüfen, dass `datacenter-pip` mit einer IP-Adresse in der Liste erscheint.

### Methode 2: Azure CLI

```bash
az login

RG="meine-ressourcengruppe"   # durch den Namen der eigenen Ressourcengruppe ersetzen
LOCATION="eastus"             # durch deren Region ersetzen

az network public-ip create \
  --resource-group "$RG" \
  --name datacenter-pip \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static

# Überprüfen
az network public-ip show \
  --resource-group "$RG" \
  --name datacenter-pip \
  --query "{name:name, ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod}" -o table
```

### Methode 3: Terraform (`task-01-public-ip/`)

`modules/public_ip/variables.tf`
```hcl
variable "name" {
  type        = string
  description = "Name der öffentlichen IP"
}

variable "resource_group_name" {
  type        = string
  description = "Bestehende Ressourcengruppe"
}

variable "location" {
  type        = string
  description = "Azure-Region"
}

variable "allocation_method" {
  type    = string
  default = "Static"
}

variable "sku" {
  type    = string
  default = "Standard"
}
```

`modules/public_ip/main.tf`
```hcl
resource "azurerm_public_ip" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.allocation_method
  sku                 = var.sku
}
```

`modules/public_ip/outputs.tf`
```hcl
output "id" {
  value = azurerm_public_ip.this.id
}

output "ip_address" {
  value = azurerm_public_ip.this.ip_address
}
```

`variables.tf` (zusätzlich die Authentifizierungsvariablen von oben)
```hcl
variable "resource_group_name" {
  type = string
}
```

`main.tf`
```hcl
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

module "datacenter_pip" {
  source = "./modules/public_ip"

  name                = "datacenter-pip"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}
```

`outputs.tf`
```hcl
output "datacenter_pip_address" {
  value = module.datacenter_pip.ip_address
}
```

Erwarteter Plan: `Plan: 1 to add, 0 to change, 0 to destroy`.

---

## Aufgabe 2: Verwaltete Festplatte an eine virtuelle Maschine anhängen

**Ziel:** die bestehende verwaltete Festplatte `datacenter-disk` an die bestehende VM `datacenter-vm` (Region `eastus`) als **Datenträger** anhängen, nachdem die Initialisierung der VM abgeschlossen ist.

### Wichtige Konzepte

| Konzept | Beispiel | Gegenbeispiel |
|---|---|---|
| Bestehende Festplatte anhängen | `datacenter-disk` existiert bereits: sie wird nur mit `datacenter-vm` verbunden | „Create and attach“ erstellt eine **neue**, leere Festplatte, was nicht verlangt ist |
| Datenträger vs. Betriebssystem-Datenträger | Ein Datenträger speichert eine Datenbank oder Logs | Der OS-Datenträger enthält das System und wird mit der VM erstellt |
| LUN | Jeder Datenträger hat auf der VM eine eindeutige Nummer (0, 1, 2…) | Zwei Datenträger mit derselben LUN: Azure lehnt ab |
| Angehängt ≠ nutzbar | Nach dem Anhängen erscheint die Festplatte in der VM | Sie ist noch nicht partitioniert, formatiert oder eingehängt: das geschieht im Betriebssystem |

Warum das Ganze? Daten auf einer eigenen Festplatte **überdauern die VM**. Man kann die VM löschen, vergrößern oder ersetzen, ohne Daten zu verlieren: Festplatte abhängen und an eine andere VM anhängen.

### Vorher prüfen: VM und Festplatte

```bash
RG="meine-ressourcengruppe"

# Die VM muss bereitgestellt sein und laufen (Initialisierung abgeschlossen)
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState}" -o table

# Die Festplatte muss frei sein: managedBy muss leer sein
az disk show -g "$RG" -n datacenter-disk \
  --query "{status:diskState, region:location, angehaengtAn:managedBy}" -o table
```

Erwartet: `Succeeded`, `VM running` und eine Festplatte im Zustand `Unattached` in `eastus`.

### Methode 1: Azure-Portal (GUI)

1. **Virtual machines** → `datacenter-vm` öffnen.
2. Auf **Overview** prüfen, dass der Status **Running** ist.
3. Menü links: **Settings → Disks**.
4. Unter **Data disks** auf **Attach existing disks** klicken.
5. In der neuen Zeile **LUN** `0` und **Disk name** `datacenter-disk` setzen; **Host caching** auf dem Standardwert lassen.
6. Oben auf der Seite auf **Save** klicken. Ohne Speichern wird nichts angehängt, auch wenn die Festplatte im Formular steht.
7. Prüfen, dass `datacenter-disk` in der Liste der Datenträger steht.

### Methode 2: Azure CLI

```bash
az vm disk attach \
  --resource-group "$RG" \
  --vm-name datacenter-vm \
  --name datacenter-disk

# Auf der VM-Seite prüfen
az vm show -g "$RG" -n datacenter-vm \
  --query "storageProfile.dataDisks[].{name:name, lun:lun, caching:caching}" -o table

# Auf der Festplatten-Seite prüfen: Zustand Attached und managedBy = die VM
az disk show -g "$RG" -n datacenter-disk \
  --query "{status:diskState, angehaengtAn:managedBy}" -o table
```

Liegt die Festplatte in einer anderen Ressourcengruppe als die VM, an `--name` ihre **vollständige ID** übergeben (`az disk show ... --query id -o tsv`).

### Methode 3: Terraform (`task-02-attach-disk/`)

VM und Festplatte existieren bereits: Sie werden mit `data`-Quellen **gelesen**, und nur die Anhängung wird erstellt.

`modules/disk_attachment/variables.tf`
```hcl
variable "virtual_machine_id" {
  type        = string
  description = "ID der Ziel-VM"
}

variable "managed_disk_id" {
  type        = string
  description = "ID der bestehenden verwalteten Festplatte"
}

variable "lun" {
  type        = number
  default     = 0
  description = "Logische Gerätenummer, eindeutig pro VM"
}

variable "caching" {
  type    = string
  default = "ReadWrite"
}

variable "create_option" {
  type        = string
  default     = "Attach"
  description = "Attach = bestehende Festplatte verbinden"
}
```

`modules/disk_attachment/main.tf`
```hcl
resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  virtual_machine_id = var.virtual_machine_id
  managed_disk_id    = var.managed_disk_id
  lun                = var.lun
  caching            = var.caching
  create_option      = var.create_option
}
```

`modules/disk_attachment/outputs.tf`
```hcl
output "id" {
  value = azurerm_virtual_machine_data_disk_attachment.this.id
}
```

`variables.tf` (zusätzlich die Authentifizierungsvariablen von oben)
```hcl
variable "resource_group_name" {
  type = string
}

variable "vm_name" {
  type    = string
  default = "datacenter-vm"
}

variable "disk_name" {
  type    = string
  default = "datacenter-disk"
}
```

`main.tf`
```hcl
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

data "azurerm_managed_disk" "disk" {
  name                = var.disk_name
  resource_group_name = var.resource_group_name
}

module "datacenter_disk_attachment" {
  source = "./modules/disk_attachment"

  virtual_machine_id = data.azurerm_virtual_machine.vm.id
  managed_disk_id    = data.azurerm_managed_disk.disk.id
  lun                = 0
}
```

`outputs.tf`
```hcl
output "attachment_id" {
  value = module.datacenter_disk_attachment.id
}
```

Erwarteter Plan: `Plan: 1 to add, 0 to change, 0 to destroy`. Erscheint die VM oder die Festplatte unter den zu erstellenden Ressourcen, wurde ein `data`-Block durch einen `resource`-Block ersetzt: anhalten und korrigieren.

---

## Fehlerbehebung

| Fehler | Ursache | Lösung |
|---|---|---|
| `403 AuthorizationFailed ... register/action` bei vielen Providern | `azurerm` 4.x versucht, ca. 30 Resource Provider im gesamten Abonnement zu registrieren | `resource_provider_registrations = "none"` im Provider-Block ergänzen |
| Derselbe Fehler oder ein Authentifizierungsfehler bei leerer `providers.tf` | Ohne Provider-Block werden die Zugangsdaten ignoriert | `providers.tf` in jedem Aufgabenordner ausfüllen |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | Der Wert der Ressourcengruppe enthält noch Platzhalterzeichen wie `<` `>` | Den echten Namen der Ressourcengruppe verwenden |
| Terraform fragt Variablen ab, die bereits in der tfvars-Datei stehen | Die Datei wird nicht automatisch geladen (falscher Name wie `terraform.tfvars.txt`, falscher Ordner) | Exakt `terraform.tfvars` im Aufgabenordner nennen oder `-var-file="datei.tfvars"` übergeben |
| `Invalid client secret` | Secret leer, abgeschnitten, oder statt *Value* die *Secret ID* kopiert | Neues Secret erstellen und die Spalte **Value** kopieren |
| `already exists` beim Apply (Aufgabe 1) | Die IP wurde bereits mit einer anderen Methode erstellt | Zuerst löschen oder importieren |
| `Disk ... is already attached to VM ...` (Aufgabe 2) | Die Festplatte ist an eine andere VM angehängt | `managedBy` prüfen, zuerst abhängen |
| Zonen- oder Regionsfehler (Aufgabe 2) | Festplatte und VM liegen in verschiedenen Regionen oder Verfügbarkeitszonen | Beide müssen Region und Zone teilen |
| `LUN ... already in use` (Aufgabe 2) | Ein anderer Datenträger nutzt diese LUN bereits | Andere Nummer wählen |
| `ResourceNotFound` bei einer `data`-Quelle | Falscher Name der Ressourcengruppe, oder die VM wird noch erstellt | Namen prüfen und auf `provisioningState = Succeeded` warten |
| Alter State oder alte Zugangsdaten nach einer neuen Sitzung | State-Datei und Zugangsdaten gehören zu einer früheren Umgebung | Neuen Aufgabenordner und die Zugangsdaten der aktuellen Sitzung verwenden |

## Aufräumen

```bash
# Terraform: im Aufgabenordner
terraform destroy

# Aufgabe 1 mit der CLI
az network public-ip delete --resource-group "$RG" --name datacenter-pip

# Aufgabe 2 mit der CLI
az vm disk detach --resource-group "$RG" --vm-name datacenter-vm --name datacenter-disk
```

## Sicherheitshinweise

- `terraform.tfvars` und State-Dateien niemals einchecken: Sie enthalten ein Secret und Ressourcendetails.
- Kurzlebige Secrets und die am wenigsten privilegierte Rolle bevorzugen (Contributor auf einer Ressourcengruppe, nicht auf dem Abonnement).
- Die drei Methoden nacheinander ausführen und die Änderung dazwischen rückgängig machen: Eine Ressource kann nicht zweimal erstellt und eine Festplatte nicht zweimal angehängt werden.
