# Tâches de migration Azure : GUI, Azure CLI et Terraform

🌐 **Langues :** **Français** · [English](README.en.md) · [Deutsch](README.de.md)

## Contexte

Une entreprise migre une partie de son infrastructure vers Azure. Pour limiter les risques et garder le contrôle, la migration est découpée en petites tâches indépendantes plutôt qu'en un seul grand basculement. Chaque tâche ci-dessous est résolue de trois façons :

1. **Portail Azure (GUI)**
2. **Azure CLI**
3. **Terraform** (modules, exécuté depuis ta propre machine, **sans** Azure CLI)

| # | Tâche | Ressources |
|---|---|---|
| 1 | [Créer une adresse IP publique](#tâche-1--créer-une-adresse-ip-publique) | `datacenter-pip` |
| 2 | [Attacher un disque managé à une machine virtuelle](#tâche-2--attacher-un-disque-managé-à-une-machine-virtuelle) | `datacenter-vm`, `datacenter-disk` |

## Prérequis

- Un abonnement Azure et un **groupe de ressources existant** (note son nom et sa région).
- Pour Terraform : Terraform >= 1.5 sur ta machine. Azure CLI **n'est pas** nécessaire.
- Pour Terraform : un **Service Principal** (client ID + client secret) avec le rôle *Contributor* sur le groupe de ressources, ainsi que le tenant ID et le subscription ID.

> Dans un shell, `<` et `>` sont des opérateurs de redirection. Ne colle jamais des emplacements comme `<RG>` tels quels : remplace-les par de vraies valeurs.

## Configuration Terraform commune

Donne à chaque tâche son propre dossier, pour que chacune ait son propre fichier d'état :

```
azure-migration/
├── task-01-public-ip/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars        # contient des secrets : ne jamais le versionner
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

Pourquoi des modules ? Un module se réutilise (seules ses entrées changent). Le contre-exemple : copier-coller le même bloc de ressource dans chaque projet et corriger chaque copie à la main.

### `providers.tf` (identique dans chaque dossier de tâche)

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

  # Nécessaire quand le Service Principal n'a pas de droits au niveau de l'abonnement
  resource_provider_registrations = "none"

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}
```

### Variables d'authentification (à ajouter dans chaque `variables.tf`)

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

### `terraform.tfvars` (tes propres valeurs, sans chevrons)

```hcl
resource_group_name = "mon-groupe-de-ressources"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
client_secret   = "ton-client-secret"
```

### `.gitignore`

```gitignore
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

### Où trouver les quatre identifiants

| Variable | Où |
|---|---|
| `subscription_id` | Portail → Subscriptions → ton abonnement → Overview |
| `tenant_id` | Portail → Microsoft Entra ID → Overview |
| `client_id` | Entra ID → App registrations → ton application → *Application (client) ID* |
| `client_secret` | Même application → Certificates & secrets → New client secret → copie la colonne **Value** (affichée une seule fois) |

Donne ensuite à l'application le rôle **Contributor** sur le groupe de ressources (Resource group → Access control (IAM) → Add role assignment). Si ton environnement fournit des identifiants prêts à l'emploi, utilise-les à la place : ils peuvent changer à chaque session.

### Exécution (dans chaque dossier de tâche)

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

---

## Tâche 1 : créer une adresse IP publique

**Objectif :** créer une adresse IP publique nommée `datacenter-pip` dans un groupe de ressources existant.

### Concepts clés

| Concept | Exemple | Contre-exemple |
|---|---|---|
| IP publique vs privée | `20.50.10.4` est joignable depuis Internet (ex. SSH) | `10.0.0.4` n'est joignable qu'à l'intérieur du réseau Azure |
| Allocation statique | L'adresse ne change jamais, même si la VM est arrêtée : les enregistrements DNS restent valides | Une adresse dynamique peut changer après un arrêt/démarrage, et le DNS pointe alors dans le vide |
| SKU Standard | Sécurisé par défaut (fermé tant qu'un Network Security Group n'autorise pas le trafic) | Le SKU Basic est retiré par Azure (depuis le 30 septembre 2025) : ne pas l'utiliser |

Pourquoi créer l'IP séparément de la VM ? Elle peut survivre à la VM : si la VM est détruite puis recréée, l'adresse (et les règles de pare-feu qui la référencent) reste identique.

### Méthode 1 : portail Azure (GUI)

1. Connecte-toi sur <https://portal.azure.com>.
2. Recherche **Public IP addresses**, ouvre le service, clique sur **Create**.
3. Renseigne :
   - **Subscription** et **Resource group** : ceux qui existent déjà
   - **Region** : la même que le groupe de ressources
   - **Name** : `datacenter-pip`
   - **IP Version** : IPv4
   - **SKU** : Standard
   - **Assignment** : Static
4. Clique sur **Review + create**, puis **Create**.
5. Vérifie que `datacenter-pip` apparaît dans la liste avec une adresse IP.

### Méthode 2 : Azure CLI

```bash
az login

RG="mon-groupe-de-ressources"   # remplace par le nom de ton groupe de ressources
LOCATION="eastus"               # remplace par sa région

az network public-ip create \
  --resource-group "$RG" \
  --name datacenter-pip \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static

# Vérifier
az network public-ip show \
  --resource-group "$RG" \
  --name datacenter-pip \
  --query "{nom:name, ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod}" -o table
```

### Méthode 3 : Terraform (`task-01-public-ip/`)

`modules/public_ip/variables.tf`
```hcl
variable "name" {
  type        = string
  description = "Nom de l'IP publique"
}

variable "resource_group_name" {
  type        = string
  description = "Groupe de ressources existant"
}

variable "location" {
  type        = string
  description = "Région Azure"
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

`variables.tf` (plus les variables d'authentification ci-dessus)
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

Plan attendu : `Plan: 1 to add, 0 to change, 0 to destroy`.

---

## Tâche 2 : attacher un disque managé à une machine virtuelle

**Objectif :** attacher le disque managé existant `datacenter-disk` à la VM existante `datacenter-vm` (région `eastus`) comme **disque de données**, une fois l'initialisation de la VM terminée.

### Concepts clés

| Concept | Exemple | Contre-exemple |
|---|---|---|
| Attacher un disque existant | `datacenter-disk` existe déjà : on le relie seulement à `datacenter-vm` | « Create and attach » crée un **nouveau** disque vide, ce qui n'est pas la demande |
| Disque de données vs disque OS | Un disque de données stocke une base de données ou des logs | Le disque OS contient le système et est créé avec la VM |
| LUN | Chaque disque de données a un numéro unique (0, 1, 2…) sur la VM | Deux disques avec le même LUN : Azure refuse |
| Attaché ≠ utilisable | Après l'attache, le disque apparaît dans la VM | Il n'est ni partitionné, ni formaté, ni monté : cela se fait dans l'OS |

Pourquoi le faire ? Des données placées sur un disque dédié **survivent à la VM**. On peut détruire, redimensionner ou remplacer la VM sans perdre les données : on détache le disque et on le rattache à une autre VM.

### Avant de commencer : vérifier la VM et le disque

```bash
RG="mon-groupe-de-ressources"

# La VM doit être provisionnée et en cours d'exécution (initialisation terminée)
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState}" -o table

# Le disque doit être libre : managedBy doit être vide
az disk show -g "$RG" -n datacenter-disk \
  --query "{etat:diskState, region:location, attachePar:managedBy}" -o table
```

Attendu : `Succeeded`, `VM running`, et un disque à l'état `Unattached` en `eastus`.

### Méthode 1 : portail Azure (GUI)

1. Ouvre **Virtual machines** → `datacenter-vm`.
2. Sur **Overview**, vérifie que le statut est **Running**.
3. Menu de gauche : **Settings → Disks**.
4. Sous **Data disks**, clique sur **Attach existing disks**.
5. Dans la nouvelle ligne, mets **LUN** `0` et **Disk name** `datacenter-disk` ; garde la valeur par défaut de **Host caching**.
6. Clique sur **Save** en haut de la page. Sans cela, rien n'est attaché, même si le disque s'affiche dans le formulaire.
7. Vérifie que `datacenter-disk` figure dans la liste des disques de données.

### Méthode 2 : Azure CLI

```bash
az vm disk attach \
  --resource-group "$RG" \
  --vm-name datacenter-vm \
  --name datacenter-disk

# Vérifier côté VM
az vm show -g "$RG" -n datacenter-vm \
  --query "storageProfile.dataDisks[].{nom:name, lun:lun, caching:caching}" -o table

# Vérifier côté disque : état Attached et managedBy = la VM
az disk show -g "$RG" -n datacenter-disk \
  --query "{etat:diskState, attachePar:managedBy}" -o table
```

Si le disque est dans un autre groupe de ressources que la VM, passe son **ID complet** à `--name` (`az disk show ... --query id -o tsv`).

### Méthode 3 : Terraform (`task-02-attach-disk/`)

La VM et le disque existent déjà : on les **lit** avec des `data` sources, et on ne crée que l'attache.

`modules/disk_attachment/variables.tf`
```hcl
variable "virtual_machine_id" {
  type        = string
  description = "ID de la VM cible"
}

variable "managed_disk_id" {
  type        = string
  description = "ID du disque managé existant"
}

variable "lun" {
  type        = number
  default     = 0
  description = "Numéro d'unité logique, unique par VM"
}

variable "caching" {
  type    = string
  default = "ReadWrite"
}

variable "create_option" {
  type        = string
  default     = "Attach"
  description = "Attach = relier un disque existant"
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

`variables.tf` (plus les variables d'authentification ci-dessus)
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

Plan attendu : `Plan: 1 to add, 0 to change, 0 to destroy`. Si la VM ou le disque apparaît parmi les ressources à créer, un bloc `data` a été remplacé par un bloc `resource` : arrête-toi et corrige.

---

## Dépannage

| Erreur | Cause | Solution |
|---|---|---|
| `403 AuthorizationFailed ... register/action` sur de nombreux providers | `azurerm` 4.x tente d'enregistrer ~30 Resource Providers sur tout l'abonnement | Ajouter `resource_provider_registrations = "none"` dans le bloc provider |
| Même erreur, ou erreur d'authentification, avec un `providers.tf` vide | Sans bloc provider, les identifiants sont ignorés | Remplir `providers.tf` dans chaque dossier de tâche |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | La valeur du groupe de ressources contient encore des caractères d'exemple comme `<` `>` | Utiliser le vrai nom du groupe de ressources |
| Terraform demande des variables déjà présentes dans ton tfvars | Le fichier n'est pas chargé automatiquement (mauvais nom comme `terraform.tfvars.txt`, mauvais dossier) | Le nommer exactement `terraform.tfvars` dans le dossier de la tâche, ou passer `-var-file="fichier.tfvars"` |
| `Invalid client secret` | Secret vide, tronqué, ou *Secret ID* copié à la place de *Value* | Recréer un secret et copier la colonne **Value** |
| `already exists` à l'apply (tâche 1) | L'IP a déjà été créée avec une autre méthode | La supprimer d'abord ou l'importer |
| `Disk ... is already attached to VM ...` (tâche 2) | Le disque est attaché à une autre VM | Vérifier `managedBy`, le détacher d'abord |
| Erreur de zone ou de région (tâche 2) | Disque et VM dans des régions ou zones de disponibilité différentes | Les deux doivent partager la région et la zone |
| `LUN ... already in use` (tâche 2) | Un autre disque utilise déjà ce LUN | Choisir un autre numéro |
| `ResourceNotFound` sur une `data` source | Mauvais nom de groupe, ou VM encore en cours de création | Vérifier les noms et attendre `provisioningState = Succeeded` |
| Ancien état ou anciens identifiants après une nouvelle session | Le fichier d'état et les identifiants appartiennent à un environnement précédent | Utiliser un nouveau dossier de tâche et les identifiants de la session en cours |

## Nettoyage

```bash
# Terraform : dans le dossier de la tâche
terraform destroy

# Tâche 1 avec la CLI
az network public-ip delete --resource-group "$RG" --name datacenter-pip

# Tâche 2 avec la CLI
az vm disk detach --resource-group "$RG" --vm-name datacenter-vm --name datacenter-disk
```

## Notes de sécurité

- Ne jamais versionner `terraform.tfvars` ni les fichiers d'état : ils contiennent un secret et des détails de ressources.
- Préférer des secrets à durée de vie courte et le rôle le moins privilégié (Contributor sur un groupe de ressources, pas sur l'abonnement).
- Exécute les trois méthodes l'une après l'autre en annulant la modification entre chaque essai : une ressource ne peut pas être créée deux fois, et un disque ne peut pas être attaché deux fois.
