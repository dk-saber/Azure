# Tags auf einer virtuellen Azure-Maschine hinzufügen und verwalten: GUI, Azure CLI und Terraform

🌐 **Sprachen:** [Français](README.fr.md) · [English](README.en.md) · **Deutsch**

## Kontext

Ein Unternehmen verlagert einen Teil seiner Infrastruktur nach Azure. Während der Migration wurden mehrere virtuelle Maschinen (VMs) in verschiedenen Regionen erstellt, und einige davon sind nicht korrekt gekennzeichnet. Diese Aufgabe ist einer der Aufräumschritte: **das Tag `Environment=dev` zu einer bestehenden VM hinzufügen**.

In dieser README heißt die VM `my-vm`. Diesen Namen durch den eigenen ersetzen.

Die Aufgabe wird auf drei Arten gelöst:

1. **Azure-Portal (GUI)**
2. **Azure CLI**
3. **Terraform** (Modul, vom eigenen Rechner aus, **ohne** Azure CLI)

## Was ist ein Tag und wozu dient es

Ein **Tag** ist ein Schlüssel-Wert-Etikett an einer Azure-Ressource, hier `Environment` = `dev`. Es verändert das Verhalten der VM nicht: Es dient dazu, Ressourcen zu klassifizieren, zu finden und abzurechnen.

| Konzept | Beispiel | Gegenbeispiel |
|---|---|---|
| Azure-Tag | `Environment=dev` an der Ressource `my-vm`: sichtbar im Portal, in Kostenberichten und in Richtlinien | Ein Etikett in einer Datei innerhalb der VM: Azure kann es nicht sehen |
| Hinzufügen (Merge) | `Environment=dev` kommt hinzu, die bestehenden Tags (`Owner`, `Project` …) bleiben | Ein Befehl, der **ersetzt**: Alle bisherigen Tags verschwinden |
| Exakter Wert | `Environment=dev` | `Environment=Dev`: Der **Name** des Tags unterscheidet nicht zwischen Groß- und Kleinschreibung, der **Wert** aber schon, für eine Prüfung ist es also nicht dasselbe Etikett |
| Keine Vererbung | Das Tag liegt an der VM | Ein Tag an der Ressourcengruppe wird nicht auf die VM kopiert, und ein Tag an der VM nicht auf ihre NIC oder Datenträger |

Praktischer Nutzen:

- **Kostenverteilung**: Ein Cost-Management-Bericht, gruppiert nach `Environment`, trennt Entwicklung, Test und Produktion.
- **Governance**: Eine Azure-Richtlinie kann ein Tag verlangen, oder eine Automatisierung kann nachts alle VMs mit `Environment=dev` ausschalten.
- **Auffindbarkeit**: Die Ressourcenliste nach Tag filtern.

## Allgemeines Vorgehen: eine VM taggen

Diese Schritte gelten für jede VM, unabhängig vom verwendeten Werkzeug.

| Schritt | Was zu tun ist | Warum |
|---|---|---|
| 1. Die VM finden | Die VM über alle Regionen hinweg nach Namen suchen, um ihre Ressourcengruppe zu erhalten | VMs derselben Migration können in verschiedenen Regionen liegen |
| 2. Aktuelle Tags lesen | Die bereits vorhandenen Tags der VM anzeigen | Man muss später prüfen können, dass keines verloren ging |
| 3. Das Tag per **Merge** hinzufügen | Bereich **Tags** im Portal, `az tag update --operation merge` oder Terraform | Merge behält die bestehenden Tags |
| 4. Prüfen | Die Tags erneut anzeigen | Bestätigt, dass `Environment=dev` vorhanden und die übrigen unverändert sind |

Gut zu wissen:

- Ein Tag hinzuzufügen **startet die VM nicht neu** und beeinflusst ihren Betrieb nicht.
- Ein Tag-Name darf `<`, `>`, `%`, `&`, `\`, `?` und `/` nicht enthalten.
- Eine Ressource trägt höchstens 50 Tags.

## Voraussetzungen

- Ein Azure-Abonnement und die **Ressourcengruppe**, die die VM enthält (Namen notieren).
- Für Terraform: Terraform >= 1.5 auf dem eigenen Rechner (beliebige Shell, z. B. Git Bash). Die Azure CLI wird **nicht** benötigt.
- Für Terraform: ein **Service Principal** (Client-ID + Client-Secret) mit der Rolle *Contributor* auf der Ressourcengruppe sowie Tenant-ID und Subscription-ID.

> In einer Shell sind `<` und `>` Umleitungsoperatoren. Platzhalter wie `<RG>` niemals unverändert einfügen: durch echte Werte ersetzen.

## Vorher prüfen: die VM und ihre Tags finden

```bash
# Die VM kann in jeder Region liegen: nach Namen suchen
az vm list --query "[?name=='my-vm'].{gruppe:resourceGroup, region:location}" -o table

RG="meine-ressourcengruppe"      # Wert der Spalte „gruppe“, ohne spitze Klammern

# Aktuelle Tags (null oder {} wenn keine)
az vm show -g "$RG" -n my-vm --query tags -o json
```

Die vorhandenen Tags notieren: Am Ende müssen **alle** noch da sein.

## Methode 1: Azure-Portal (GUI)

1. Unter <https://portal.azure.com> anmelden.
2. **Virtual machines** → `my-vm`.
3. Menü links: **Tags**.
4. In der ersten leeren Zeile: **Name** = `Environment`, **Value** = `dev`.
5. Unten auf der Seite auf **Apply** klicken. Ohne Speichern wird nichts übernommen.
6. Prüfen: Die Seite **Tags** (oder **Overview**) zeigt `Environment : dev`.

## Methode 2: Azure CLI

```bash
RG="meine-ressourcengruppe"

VM_ID=$(az vm show -g "$RG" -n my-vm --query id -o tsv)

az tag update --resource-id "$VM_ID" --operation merge --tags Environment=dev
```

`--operation merge` fügt das Tag hinzu, **ohne** die anderen zu löschen.

Gleichwertige Variante mit `az vm update`:

```bash
az vm update -g "$RG" -n my-vm --set tags.Environment=dev
```

**Vermeiden**: `az resource tag --tags Environment=dev ...` ohne die Option `--is-incremental` **ersetzt** alle bestehenden Tags durch dieses eine.

## Methode 3: Terraform

### Zwei Situationen

**Neue Bereitstellung (die VM wird mit Terraform erstellt).** Das ist der Normalfall: `tags` an der VM-Ressource setzen.

```hcl
resource "azurerm_linux_virtual_machine" "this" {
  name                = "my-vm"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  # ... Größe, Image, Netzwerkschnittstellen, Zugangsdaten ...

  tags = {
    Environment = "dev"
  }
}
```

**Bestehende VM (diese Aufgabe).** `tags` ist eine Eigenschaft der VM selbst. Die VM mit `azurerm_linux_virtual_machine` zu verwalten hieße, sie zu importieren und alle ihre Einstellungen zu übernehmen (Größe, Image, SSH-Schlüssel …), mit dem Risiko, dass sie ersetzt wird. Ein leichterer Ansatz nutzt den Provider `azapi`, der **nur** die Änderung der Tags an die Azure-API sendet. Der Provider führt den Anfrage-Body mit der bestehenden Ressource zusammen, die anderen Tags sollten also erhalten bleiben: `az vm show --query tags` vorher und nachher vergleichen. Der Rest dieses Abschnitts verwendet ihn.

Warum ein Modul? Ein Modul ist wiederverwendbar (nur seine Eingaben ändern sich). Das Gegenbeispiel: denselben Ressourcenblock in jedes Projekt kopieren.

### Projektstruktur

```
tag-vm/
├── providers.tf
├── variables.tf
├── main.tf                     # Wurzel: enthält module "vm_tags"
├── outputs.tf
├── terraform.tfvars            # enthält Geheimnisse: niemals einchecken
├── .gitignore
└── modules/
    └── vm_tags/
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

variable "tags" {
  type = map(string)
  default = {
    Environment = "dev"
  }
}
```

### `main.tf` (Wurzel)

```hcl
# Bestehende VM: gelesen, nicht verwaltet
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

module "vm_tags" {
  source = "./modules/vm_tags"

  vm_id = data.azurerm_virtual_machine.vm.id
  tags  = var.tags
}
```

### `outputs.tf`

```hcl
output "vm_id" {
  value = module.vm_tags.vm_id
}

output "applied_tags" {
  value = module.vm_tags.tags
}
```

### `modules/vm_tags/variables.tf`

```hcl
variable "vm_id" {
  type        = string
  description = "ID der bestehenden VM"
}

variable "tags" {
  type        = map(string)
  description = "Der VM hinzuzufügende Tags"
}
```

### `modules/vm_tags/main.tf`

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
    tags = var.tags
  }
}
```

### `modules/vm_tags/outputs.tf`

```hcl
output "vm_id" {
  value = azapi_update_resource.this.resource_id
}

output "tags" {
  value = var.tags
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

### Ausführung

```bash
terraform init
terraform validate
terraform plan      # erwartet: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

Hinweise:

- Die VM muss weder gestoppt noch neu gestartet werden.
- Die `main.tf` mit `module "vm_tags"` ist die im **Wurzelverzeichnis** des Ordners, nicht die innerhalb von `modules/`.
- `terraform destroy` entfernt das Tag **nicht**: Diese Ressource sendet nur eine Änderung und kann sie nicht rückgängig machen.

## Abschließende Prüfung (alle Methoden)

```bash
az vm show -g "$RG" -n my-vm --query tags -o json

# Eine weitere Abfrage über die Tags-API
az tag list --resource-id "$(az vm show -g "$RG" -n my-vm --query id -o tsv)" -o json
```

Erwartet: `"Environment": "dev"` ist vorhanden, und die zuvor notierten Tags sind weiterhin da.

## Zurücksetzen (um eine andere Methode zu testen)

```bash
az vm update -g "$RG" -n my-vm --remove tags.Environment
```

Auch den lokalen State des vorigen Versuchs löschen (`rm -f terraform.tfstate*`), sonst hält Terraform das Tag für bereits gesetzt.

## Fehlerbehebung

| Fehler | Ursache | Lösung |
|---|---|---|
| Die alten Tags sind verschwunden | Ein Befehl, der ersetzt (`az resource tag` ohne `--is-incremental` oder `--operation replace`) | `--operation merge` verwenden und die verlorenen Tags wieder hinzufügen |
| Tag im Portal nicht gespeichert | **Apply** wurde nicht angeklickt | Zurück zu **Tags** und **Apply** klicken |
| `Environment=Dev` statt `dev` | Der Wert unterscheidet Groß- und Kleinschreibung | Den Wert auf `dev` korrigieren |
| Unzulässige Zeichen im Tag-Namen | Ein Name darf `<`, `>`, `%`, `&`, `\`, `?`, `/` nicht enthalten | Einen Namen ohne diese Zeichen wählen |
| Mehr als 50 Tags | Azure-Grenze pro Ressource | Nicht benötigte Tags entfernen |
| VM nicht gefunden | Falscher Name der Ressourcengruppe, oder die VM liegt in einer anderen Region | Die Spalte „gruppe“ der obigen Suche verwenden |
| `403 AuthorizationFailed ... register/action` bei vielen Providern | `azurerm` 4.x versucht, ca. 30 Resource Provider im gesamten Abonnement zu registrieren | `resource_provider_registrations = "none"` im Provider-Block ergänzen |
| Derselbe Fehler oder ein Authentifizierungsfehler bei leerer `providers.tf` | Ohne Provider-Block werden die Zugangsdaten ignoriert | `providers.tf` ausfüllen |
| Terraform fragt Variablen ab, die bereits in der tfvars-Datei stehen | Die Datei wird nicht automatisch geladen (falscher Name wie `terraform.tfvars.txt`, falscher Ordner) | Exakt `terraform.tfvars` neben `main.tf` nennen oder `-var-file="datei.tfvars"` übergeben |
| `Invalid client secret` | Secret leer, abgeschnitten, oder statt *Value* die *Secret ID* kopiert | Neues Secret erstellen und die Spalte **Value** kopieren |
| `Module not installed` | `terraform init` wurde nicht ausgeführt | `terraform init` ausführen |
| `No declaration found for var.xxx` oder rote Unterstreichungen in VS Code | Eine `variables.tf` im Wurzelverzeichnis fehlt, oder der Editor hat nicht neu geladen | Dateien mit `find` prüfen, `terraform init` und `terraform validate` ausführen; wenn gültig, **Developer: Reload Window** |
| `azapi`-Fehler beim Update | Operation abgelehnt oder unerwartete Antwortform | Den Fehler ausgeben und die CLI (`az tag update`) als Ausweichlösung nutzen |
| Alter State oder alte Zugangsdaten nach einer neuen Sitzung | State-Datei und Zugangsdaten gehören zu einer früheren Umgebung | Neuen Ordner und die Zugangsdaten der aktuellen Sitzung verwenden |

## Aufräumen

```bash
az vm update -g "$RG" -n my-vm --remove tags.Environment
```

`terraform destroy` entfernt das Tag nicht (siehe oben).

## Sicherheitshinweise

- `terraform.tfvars` und State-Dateien niemals einchecken: Sie enthalten ein Secret und Ressourcendetails.
- Kurzlebige Secrets und die am wenigsten privilegierte Rolle bevorzugen (Contributor auf einer Ressourcengruppe, nicht auf dem Abonnement).
- Keine Geheimnisse oder personenbezogenen Daten in Tags ablegen: Tags erscheinen in Abrechnungsberichten und sind für jeden lesbar, der die Ressource lesen darf.
- Die drei Methoden nacheinander ausführen und die Änderung dazwischen rückgängig machen, damit jede vom selben Zustand ausgeht.
