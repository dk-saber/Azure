# Öffentliche IP-Adresse in Azure: GUI, Azure CLI und Terraform

🌐 **Sprachen:** [Français](README.fr.md) · [English](README.en.md) · **Deutsch**

## Kontext

Ein Unternehmen verlagert einen Teil seiner Infrastruktur nach Azure. Um das Risiko gering zu halten, wird die Migration nicht in einem großen Schritt durchgeführt, sondern in kleine, voneinander unabhängige Etappen aufgeteilt. Der erste Baustein ist eine **öffentliche IP-Adresse**: eine aus dem Internet erreichbare Adresse, die später an eine virtuelle Maschine, einen Load Balancer oder ein Gateway gebunden werden kann.

**Ziel:** eine öffentliche IP-Adresse mit dem Namen `datacenter-pip` in einer bestehenden Ressourcengruppe erstellen.

## Wichtige Konzepte

| Konzept | Beispiel | Gegenbeispiel |
|---|---|---|
| Öffentliche vs. private IP | `20.50.10.4` ist aus dem Internet erreichbar (z. B. per SSH) | `10.0.0.4` ist nur innerhalb des Azure-Netzwerks erreichbar |
| Statische Zuweisung | Die Adresse ändert sich nie, auch wenn die VM gestoppt wird; DNS-Einträge bleiben gültig | Eine dynamische Adresse kann sich nach einem Stopp/Start ändern, und der DNS-Eintrag zeigt ins Leere |
| SKU Standard | Standardmäßig sicher (geschlossen, bis eine Network Security Group Datenverkehr erlaubt) | Die SKU Basic wird von Azure abgekündigt (seit dem 30. September 2025) und sollte nicht mehr verwendet werden |

Warum die IP getrennt von der VM anlegen? Sie kann die VM überdauern: Wird die VM gelöscht und neu erstellt, bleiben die Adresse (und Firewall-Regeln, die auf sie verweisen) unverändert.

## Voraussetzungen

- Ein Azure-Abonnement und eine **bestehende Ressourcengruppe** (Name und Region notieren).
- Für die Terraform-Methode: Terraform >= 1.5 auf dem eigenen Rechner. Die Azure CLI wird **nicht** benötigt.
- Für die Terraform-Methode: ein **Service Principal** (Client-ID + Client-Secret) mit der Rolle *Contributor* auf der Ressourcengruppe sowie Tenant-ID und Subscription-ID.

## Methode 1: Azure-Portal (GUI)

1. Unter <https://portal.azure.com> anmelden.
2. Nach **Public IP addresses** suchen, den Dienst öffnen und auf **Create** klicken.
3. Folgendes ausfüllen:
   - **Subscription** und **Resource group**: die bereits vorhandenen
   - **Region**: dieselbe wie die Ressourcengruppe
   - **Name**: `datacenter-pip`
   - **IP Version**: IPv4
   - **SKU**: Standard
   - **Assignment**: Static
4. Auf **Review + create** und danach auf **Create** klicken.
5. Prüfen, dass `datacenter-pip` mit einer IP-Adresse in der Liste erscheint.

## Methode 2: Azure CLI

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

> In einer Shell sind `<` und `>` Umleitungsoperatoren. Platzhalter wie `<RG>` niemals unverändert einfügen: durch echte Werte ersetzen.

## Methode 3: Terraform (Module, vom eigenen Rechner aus)

### Projektstruktur

```
azure-public-ip/
├── providers.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars        # enthält Geheimnisse: niemals einchecken
└── modules/
    └── public_ip/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

Ein Modul lässt sich für jede künftige öffentliche IP wiederverwenden (nur der Name ändert sich). Das Gegenbeispiel: einen `azurerm_public_ip`-Block in jedes Projekt kopieren und jede Kopie von Hand anpassen.

### Modul (`modules/public_ip/`)

`variables.tf`
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

`main.tf`
```hcl
resource "azurerm_public_ip" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.allocation_method
  sku                 = var.sku
}
```

`outputs.tf`
```hcl
output "id" {
  value = azurerm_public_ip.this.id
}

output "ip_address" {
  value = azurerm_public_ip.this.ip_address
}
```

### Root-Konfiguration

`providers.tf`
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

`variables.tf`
```hcl
variable "resource_group_name" {
  type = string
}

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

`terraform.tfvars` (eigene Werte eintragen, ohne spitze Klammern)
```hcl
resource_group_name = "meine-ressourcengruppe"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
client_secret   = "dein-client-secret"
```

`.gitignore`
```gitignore
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

### Ausführung

```bash
terraform init
terraform validate
terraform plan      # erwartet: Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

### Wo man die vier Zugangsdaten findet

| Variable | Wo |
|---|---|
| `subscription_id` | Portal → Subscriptions → Abonnement → Overview |
| `tenant_id` | Portal → Microsoft Entra ID → Overview |
| `client_id` | Entra ID → App registrations → eigene App → *Application (client) ID* |
| `client_secret` | Dieselbe App → Certificates & secrets → New client secret → Spalte **Value** kopieren (wird nur einmal angezeigt) |

Anschließend der App die Rolle **Contributor** auf der Ressourcengruppe zuweisen (Resource group → Access control (IAM) → Add role assignment).

## Fehlerbehebung

| Fehler | Ursache | Lösung |
|---|---|---|
| `403 AuthorizationFailed ... register/action` bei vielen Providern | `azurerm` 4.x versucht, ca. 30 Resource Provider im gesamten Abonnement zu registrieren | `resource_provider_registrations = "none"` im Provider-Block ergänzen |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | Der Wert der Ressourcengruppe enthält noch Platzhalterzeichen wie `<` `>` | Den echten Namen der Ressourcengruppe verwenden |
| Terraform fragt Variablen ab, die bereits in der tfvars-Datei stehen | Die Datei wird nicht automatisch geladen (falscher Name wie `terraform.tfvars.txt`, falscher Ordner) | Exakt `terraform.tfvars` im Projektstamm nennen oder `-var-file="datei.tfvars"` übergeben |
| `Invalid client secret` | Secret leer, abgeschnitten, oder statt *Value* die *Secret ID* kopiert | Neues Secret erstellen und die Spalte **Value** kopieren |
| `already exists` beim Apply | Die IP wurde bereits mit einer anderen Methode erstellt | Zuerst löschen (`az network public-ip delete -g "$RG" -n datacenter-pip`) oder importieren |

## Aufräumen

```bash
terraform destroy
# oder
az network public-ip delete --resource-group "$RG" --name datacenter-pip
```

## Sicherheitshinweise

- `terraform.tfvars` und die State-Datei niemals einchecken: Sie enthalten ein Secret und Ressourcendetails.
- Kurzlebige Secrets und die am wenigsten privilegierte Rolle bevorzugen (Contributor auf einer Ressourcengruppe, nicht auf dem Abonnement).
- Die drei Methoden nacheinander ausführen und die IP dazwischen löschen, da eine Ressource mit demselben Namen nicht zweimal erstellt werden kann.
