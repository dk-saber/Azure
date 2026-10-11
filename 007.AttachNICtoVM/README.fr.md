# Attacher une interface réseau (NIC) à une machine virtuelle Azure : GUI, Azure CLI et Terraform

🌐 **Langues :** **Français** · [English](README.en.md) · [Deutsch](README.de.md)

## Contexte

Une entreprise migre une partie de son infrastructure vers Azure. Pour limiter les risques et garder le contrôle, la migration est découpée en petites tâches indépendantes plutôt qu'en un seul grand basculement. Cette tâche est l'une de ces étapes : **attacher une interface réseau (NIC) existante à une machine virtuelle (VM) existante**.

**Objectif :** attacher la NIC `datacenter-nic` à la VM `datacenter-vm`, vérifier que la NIC est bien attachée et que l'initialisation de la VM est terminée.

La tâche est résolue de trois façons :

1. **Portail Azure (GUI)**
2. **Azure CLI**
3. **Terraform** (module, exécuté depuis ta propre machine, **sans** Azure CLI)

## ⚠️ Première étape obligatoire : arrêter **et désallouer** la VM

Azure ne peut pas ajouter une NIC à une VM en cours d'exécution. La VM doit être **désallouée** avant l'attache, puis redémarrée ensuite.

| | Exemple | Contre-exemple |
|---|---|---|
| Désallouée | Bouton **Stop** du portail, ou `az vm deallocate` : statut `Stopped (deallocated)`, ressources de calcul libérées | Arrêt depuis l'intérieur de l'OS, ou `az vm stop` : la VM est arrêtée mais **toujours allouée**, l'attache échoue encore |
| VM en cours d'exécution | Un disque de données peut être attaché à chaud | L'attache d'une NIC est refusée |

Ordre à suivre : **désallouer → attacher → démarrer → vérifier**.

## Concepts clés

| Concept | Exemple | Contre-exemple |
|---|---|---|
| Attacher une NIC existante | `datacenter-nic` existe déjà : on la relie seulement à `datacenter-vm` | Créer une nouvelle NIC laisse une carte en trop |
| NIC primaire vs secondaire | La NIC d'origine reste primaire ; `datacenter-nic` est ajoutée en secondaire | « Remplacer » la NIC primaire n'est pas la demande |
| Même région et même VNet | Les deux sont dans la même région et le même réseau virtuel | Une NIC d'un autre VNet ou d'une autre région est refusée |
| Attachée ≠ configurée dans l'OS | Azure affiche la NIC comme attachée | L'interface doit encore être configurée dans l'OS (hors périmètre) |

Pourquoi le faire ? Une VM à deux NIC sépare les flux : par exemple une NIC pour le trafic utilisateurs et une pour l'administration ou les sauvegardes, chacune avec ses propres règles de Network Security Group. C'est aussi courant pour les pare-feu et proxys virtuels.

## Prérequis

- Un abonnement Azure et un **groupe de ressources existant** contenant la VM et la NIC (note son nom).
- La taille de la VM doit autoriser deux NIC.
- Pour Terraform : Terraform >= 1.5 sur ta machine (n'importe quel shell, par exemple Git Bash). Azure CLI **n'est pas** nécessaire.
- Pour Terraform : un **Service Principal** (client ID + client secret) avec le rôle *Contributor* sur le groupe de ressources, ainsi que le tenant ID et le subscription ID.

> Dans un shell, `<` et `>` sont des opérateurs de redirection. Ne colle jamais des emplacements comme `<RG>` tels quels : remplace-les par de vraies valeurs.

## Avant de commencer : vérifier la VM et la NIC

```bash
RG="mon-groupe-de-ressources"      # remplace par le nom de ton groupe de ressources

# La VM doit être provisionnée et en cours d'exécution
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState, taille:hardwareProfile.vmSize}" -o table

# NIC déjà sur la VM (la première est la primaire)
az vm nic list -g "$RG" --vm-name datacenter-vm -o table

# La NIC doit être libre : vm doit valoir null
az network nic show -g "$RG" -n datacenter-nic \
  --query "{vm:virtualMachine.id, region:location}" -o json
```

Puis désalloue la VM :

```bash
az vm deallocate -g "$RG" -n datacenter-vm
```

(Portail : **Virtual machines → datacenter-vm → Stop**, puis attendre **Stopped (deallocated)**.)

## Méthode 1 : portail Azure (GUI)

1. Connecte-toi sur <https://portal.azure.com>.
2. Arrête la VM et attends **Stopped (deallocated)**.
3. **Networking** (ou **Network settings**) → **Attach network interface**. Le bouton est grisé tant que la VM tourne.
4. Choisis `datacenter-nic` → **OK**.
5. **Overview** → **Start**, et attends **Running**.
6. Vérifie : `datacenter-nic` apparaît dans **Networking**, et sur la NIC le champ **Virtual machine** affiche `datacenter-vm`.

## Méthode 2 : Azure CLI

```bash
az vm deallocate -g "$RG" -n datacenter-vm
az vm nic add -g "$RG" --vm-name datacenter-vm --nics datacenter-nic
az vm start -g "$RG" -n datacenter-vm
```

Si la NIC est dans un autre groupe de ressources, passe son **ID complet** à `--nics`.

## Méthode 3 : Terraform

### Pourquoi une approche particulière

Le provider `azurerm` n'a pas de ressource dédiée « attacher une NIC à une VM » : la liste des NIC est une propriété de la VM elle-même. Gérer la VM avec `azurerm_linux_virtual_machine` obligerait à l'importer et à recopier tous ses paramètres (taille, image, clé SSH…), avec un risque de remplacement. Une approche plus légère utilise le provider `azapi`, qui envoie **uniquement** la modification de `networkProfile` à l'API Azure.

Deux détails appris à la dure :

- Le data source `azurerm_virtual_machine` n'exporte **pas** `network_interface_ids`. Les NIC actuelles sont lues avec un data source `azapi_resource`.
- `azapi` **ne désalloue pas** la VM à ta place : fais-le avant `terraform apply`.

Pourquoi un module ? Un module se réutilise (seules ses entrées changent). Le contre-exemple : copier-coller le même bloc de ressource dans chaque projet.

### Structure du projet

```
attach-nic/
├── providers.tf
├── variables.tf
├── main.tf                     # racine : contient module "nic_attachment"
├── outputs.tf
├── terraform.tfvars            # contient des secrets : ne jamais le versionner
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

  # Nécessaire quand le Service Principal n'a pas de droits au niveau de l'abonnement
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

### `main.tf` (racine)

```hcl
# VM existante : lue, pas gérée
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# NIC actuellement attachées à la VM, lues via l'API Azure
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

# NIC existante à attacher
data "azurerm_network_interface" "new" {
  name                = var.nic_name
  resource_group_name = var.resource_group_name
}

locals {
  # La première NIC de la liste est la NIC primaire
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
  description = "ID de la VM existante"
}

variable "primary_nic_id" {
  type        = string
  description = "NIC primaire déjà attachée"
}

variable "additional_nic_ids" {
  type        = list(string)
  description = "NIC supplémentaires à attacher"
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

### Exécution, avec la VM **déjà désallouée**

```bash
terraform init
terraform validate
terraform plan      # attendu : Plan: 1 to add, 0 to change, 0 to destroy
terraform apply

# puis redémarrer la VM
az vm start -g "$RG" -n datacenter-vm      # ou Portail : Overview → Start
```

Remarque : le `main.tf` qui contient `module "nic_attachment"` est celui de la **racine** du dossier, pas celui qui se trouve dans `modules/`.

## Vérification finale (toutes méthodes)

```bash
# Deux NIC listées
az vm nic list -g "$RG" --vm-name datacenter-vm -o table

# L'ID doit se terminer par datacenter-vm
az network nic show -g "$RG" -n datacenter-nic --query "virtualMachine.id" -o tsv

# Initialisation terminée : Succeeded et VM running
az vm show -d -g "$RG" -n datacenter-vm \
  --query "{provisioning:provisioningState, power:powerState}" -o table
```

N'envoie la tâche qu'une fois `Succeeded` et `VM running` affichés.

## Remise à zéro (pour tester une autre méthode)

```bash
az vm deallocate -g "$RG" -n datacenter-vm
az vm nic remove -g "$RG" --vm-name datacenter-vm --nics datacenter-nic
```

Supprime aussi le state local de l'essai précédent (`rm -f terraform.tfstate*`), sinon Terraform croira l'attache déjà faite. `terraform destroy` ne détache **pas** la NIC : cette ressource ne fait qu'envoyer une modification, elle ne sait pas l'annuler.

## Dépannage

| Erreur | Cause | Solution |
|---|---|---|
| Attache de NIC refusée, bouton grisé | La VM tourne, ou est seulement arrêtée mais toujours allouée | **Désallouer** la VM (statut `Stopped (deallocated)`) |
| NIC déjà utilisée | La NIC est attachée à une autre VM | Vérifier `virtualMachine.id`, la détacher d'abord |
| Erreur de région ou de VNet | NIC et VM dans des régions ou réseaux virtuels différents | Elles doivent partager région et VNet |
| Erreur sur le nombre de NIC | La taille de VM n'autorise pas deux NIC | Choisir une taille plus grande |
| `403 AuthorizationFailed ... register/action` sur de nombreux providers | `azurerm` 4.x tente d'enregistrer ~30 Resource Providers sur tout l'abonnement | Ajouter `resource_provider_registrations = "none"` dans le bloc provider |
| Même erreur, ou erreur d'authentification, avec un `providers.tf` vide | Sans bloc provider, les identifiants sont ignorés | Remplir `providers.tf` |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | La valeur du groupe de ressources contient encore des caractères d'exemple comme `<` `>` | Utiliser le vrai nom du groupe de ressources |
| Terraform demande des variables déjà présentes dans ton tfvars | Le fichier n'est pas chargé automatiquement (mauvais nom comme `terraform.tfvars.txt`, mauvais dossier) | Le nommer exactement `terraform.tfvars`, à côté de `main.tf`, ou passer `-var-file="fichier.tfvars"` |
| `Invalid client secret` | Secret vide, tronqué, ou *Secret ID* copié à la place de *Value* | Recréer un secret et copier la colonne **Value** |
| `Module not installed` | `terraform init` n'a pas été lancé | Lancer `terraform init` |
| `No declaration found for var.xxx`, ou soulignements rouges dans VS Code | Un `variables.tf` manque à la racine, ou l'éditeur n'a pas rechargé | Vérifier les fichiers avec `find`, lancer `terraform init` et `terraform validate` ; si valide, **Developer: Reload Window** |
| `Unsupported attribute ... network_interface_ids` | Le data source `azurerm_virtual_machine` ne l'exporte pas | Lire les NIC avec le data source `azapi_resource` |
| `ResourceNotFound` sur une `data` source | Mauvais nom de groupe, ou VM encore en cours de création | Vérifier les noms et attendre `provisioningState = Succeeded` |
| Ancien état ou anciens identifiants après une nouvelle session | Le fichier d'état et les identifiants appartiennent à un environnement précédent | Utiliser un nouveau dossier et les identifiants de la session en cours |

## Nettoyage

```bash
# CLI (VM désallouée d'abord)
az vm nic remove --resource-group "$RG" --vm-name datacenter-vm --nics datacenter-nic
```

`terraform destroy` ne détache pas une NIC (voir plus haut).

## Notes de sécurité

- Ne jamais versionner `terraform.tfvars` ni les fichiers d'état : ils contiennent un secret et des détails de ressources.
- Préférer des secrets à durée de vie courte et le rôle le moins privilégié (Contributor sur un groupe de ressources, pas sur l'abonnement).
- Exécute les trois méthodes l'une après l'autre en annulant la modification entre chaque essai : une NIC ne peut pas être attachée deux fois.
- Dans un vrai projet, crée la VM avec Terraform et liste les deux NIC dans `network_interface_ids` dès le départ : ni import, ni désallocation.
